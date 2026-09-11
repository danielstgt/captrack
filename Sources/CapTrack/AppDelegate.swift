import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    let preferences = Preferences()
    let store = UsageStore(dataFileURL: ClaudeCodeIntegration.live.dataFileURL)
    let integrationMonitor = IntegrationMonitor(integration: .live)
    private(set) lazy var updateChecker = UpdateChecker(preferences: preferences)

    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var settingsWindow: SettingsWindowController?
    private var refreshTask: Task<Void, Never>?
    private var outsideClickMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.mainMenu = MainMenu.build(delegate: self)

        // Best effort; the settings window reports problems if this fails.
        try? ClaudeCodeIntegration.live.installBridge()

        setUpStatusItem()
        setUpPopover()
        store.start()
        integrationMonitor.start()
        observeChanges()
        updateStatusItem()

        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                self?.updateStatusItem()
            }
        }
        Task { await checkForUpdatesInBackground() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTask?.cancel()
    }

    // MARK: - Status item

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = item.button else { return }
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.imagePosition = .imageOnly
        statusItem = item
    }

    private func setUpPopover() {
        let view = UsageView(
            store: store,
            monitor: integrationMonitor,
            onOpenSettings: { [weak self] in self?.showSettings(nil) },
            onQuit: { NSApp.terminate(nil) }
        )
        let controller = NSHostingController(rootView: view)
        controller.sizingOptions = .preferredContentSize
        popover.contentViewController = controller
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
    }

    /// Re-renders the menu bar item whenever the snapshot or the display preference changes.
    private func observeChanges() {
        withObservationTracking {
            _ = store.snapshot
            _ = preferences.fiveHourDisplay
            _ = preferences.sevenDayDisplay
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.updateStatusItem()
                self?.observeChanges()
            }
        }
    }

    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }
        let now = Date.now
        let snapshot = store.snapshot
        let fiveHour = WindowState(window: snapshot?.fiveHour, hasRateLimits: snapshot?.hasRateLimits ?? false, now: now)
        let sevenDay = WindowState(window: snapshot?.sevenDay, hasRateLimits: snapshot?.hasRateLimits ?? false, now: now)

        button.image = StatusItemRenderer.image(segments: StatusItemRenderer.segments(
            fiveHour: fiveHour,
            sevenDay: sevenDay,
            fiveHourOptions: preferences.fiveHourDisplay,
            sevenDayOptions: preferences.sevenDayDisplay,
            hasData: snapshot?.hasRateLimits == true,
            now: now
        ))

        if let snapshot {
            button.toolTip = """
            5-hour window: \(Formatting.percent(fiveHour.percentage))\(resetNote(fiveHour, clock: Formatting.clockTime))
            Weekly window: \(Formatting.percent(sevenDay.percentage))\(resetNote(sevenDay, clock: Formatting.weekdayTime))
            Updated \(Formatting.updatedAgo(snapshot.receivedAt, now: now))
            """
        } else {
            button.toolTip = "CapTrack – waiting for data from Claude Code"
        }
    }

    private func resetNote(_ state: WindowState, clock: (Date) -> String) -> String {
        if case .active(let window) = state { return ", resets at \(clock(window.resetsAt))" }
        return ""
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        store.reload()
        integrationMonitor.refresh()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()

        // The app is not activated for the popover, so a transient popover would not notice
        // clicks in other apps. Watch for them and close ourselves.
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.popover.performClose(nil) }
        }
    }

    func popoverDidClose(_ notification: Notification) {
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
    }

    private func showContextMenu() {
        guard let item = statusItem else { return }
        let menu = NSMenu()
        menu.addItem(withTitle: "Show Usage", action: #selector(showPopover(_:)), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Settings…", action: #selector(showSettings(_:)), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Check for Updates…", action: #selector(checkForUpdates(_:)), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "About CapTrack", action: #selector(showAbout(_:)), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Quit CapTrack", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // Temporarily attach the menu so the status item shows it in the standard way.
        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil
    }

    // MARK: - Actions

    @objc func showPopover(_ sender: Any?) {
        if !popover.isShown { togglePopover() }
    }

    @objc func showSettings(_ sender: Any?) {
        popover.performClose(nil)
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(preferences: preferences, updateChecker: updateChecker, monitor: integrationMonitor)
        }
        integrationMonitor.refresh()
        settingsWindow?.show()
    }

    @objc func showAbout(_ sender: Any?) {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc func checkForUpdates(_ sender: Any?) {
        Task {
            let release = await updateChecker.check()
            presentUpdateResult(release)
        }
    }

    // MARK: - Updates

    private func checkForUpdatesInBackground() async {
        try? await Task.sleep(for: .seconds(20))
        guard let release = await updateChecker.checkInBackgroundIfDue() else { return }
        presentUpdateAlert(release)
    }

    private func presentUpdateResult(_ release: UpdateChecker.Release?) {
        if let release {
            presentUpdateAlert(release)
            return
        }
        let alert = NSAlert()
        switch updateChecker.state {
        case .failed(let message):
            alert.messageText = "Could not check for updates"
            alert.informativeText = message
        default:
            alert.messageText = "You're up to date"
            alert.informativeText = "CapTrack \(AppInfo.version) is the latest version."
        }
        NSApp.activate()
        alert.runModal()
    }

    private func presentUpdateAlert(_ release: UpdateChecker.Release) {
        let alert = NSAlert()
        alert.messageText = "CapTrack \(release.version) is available"
        alert.informativeText = "You are using \(AppInfo.version). The download opens in your browser; replace the app in your Applications folder to update."
        alert.addButton(withTitle: "Download")
        alert.addButton(withTitle: "Later")
        alert.addButton(withTitle: "Skip This Version")
        NSApp.activate()
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            NSWorkspace.shared.open(release.downloadURL ?? release.pageURL)
        case .alertThirdButtonReturn:
            preferences.skippedVersion = release.version
        default:
            break
        }
    }
}

/// Minimal main menu so keyboard shortcuts (⌘C, ⌘W, ⌘Q, …) work in the settings window.
enum MainMenu {
    static func build(delegate: AppDelegate) -> NSMenu {
        let main = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About CapTrack", action: #selector(AppDelegate.showAbout(_:)), keyEquivalent: "").target = delegate
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Settings…", action: #selector(AppDelegate.showSettings(_:)), keyEquivalent: ",").target = delegate
        appMenu.addItem(withTitle: "Check for Updates…", action: #selector(AppDelegate.checkForUpdates(_:)), keyEquivalent: "").target = delegate
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit CapTrack", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(submenu: appMenu, title: "CapTrack")

        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        main.addItem(submenu: edit, title: "Edit")

        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        main.addItem(submenu: window, title: "Window")

        return main
    }
}

private extension NSMenu {
    func addItem(submenu: NSMenu, title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        addItem(item)
    }
}
