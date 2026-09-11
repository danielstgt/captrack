import AppKit
import SwiftUI

/// Settings window content. Built from plain SwiftUI containers rather than a grouped
/// `Form` so that expanding sections animate smoothly and the window can follow the
/// content height (see `SettingsWindowController`).
struct SettingsView: View {
    @Bindable var preferences: Preferences
    let updateChecker: UpdateChecker
    let monitor: IntegrationMonitor
    /// Reports the ideal content size whenever it changes.
    var onSizeChange: (CGSize) -> Void

    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchAtLoginMessage: String?
    @State private var integrationMessage: String?
    @State private var showManualSetup: Bool
    @State private var copied = false
    @State private var isChecking = false
    @State private var checkedRecently = false
    @State private var refreshSpin = 0.0
    @State private var checkTask: Task<Void, Never>?

    static let width: CGFloat = 500
    private static let animation = Animation.easeInOut(duration: SettingsWindowController.animationDuration)

    init(
        preferences: Preferences,
        updateChecker: UpdateChecker,
        monitor: IntegrationMonitor,
        expandManualSetup: Bool = false,
        onSizeChange: @escaping (CGSize) -> Void = { _ in }
    ) {
        self.preferences = preferences
        self.updateChecker = updateChecker
        self.monitor = monitor
        self.onSizeChange = onSizeChange
        _showManualSetup = State(initialValue: expandManualSetup)
    }

    var body: some View {
        // Pinned to the top of whatever size the window currently has, so the window can
        // animate its height independently without the content moving.
        TopAnchoredLayout {
            content
                .onGeometryChange(for: CGSize.self) { $0.size } action: { onSizeChange($0) }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 22) {
            generalSection
            claudeCodeSection
            updatesSection
            aboutSection
        }
        .padding(20)
        .frame(width: Self.width)
        .fixedSize(horizontal: false, vertical: true)
        .animation(Self.animation, value: monitor.status)
        .onAppear(perform: refreshStatus)
    }

    // MARK: General

    private var generalSection: some View {
        SettingsSection("General") {
            SettingsRow("Launch at login") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .onChange(of: launchAtLogin) { _, enabled in
                        guard enabled != LaunchAtLogin.isEnabled else { return }
                        do {
                            try LaunchAtLogin.setEnabled(enabled)
                            launchAtLoginMessage = LaunchAtLogin.requiresApproval
                                ? "macOS needs your approval in System Settings › General › Login Items."
                                : nil
                        } catch {
                            launchAtLogin = LaunchAtLogin.isEnabled
                            launchAtLoginMessage = AppInfo.isBundled
                                ? error.localizedDescription
                                : "Only available when running the bundled CapTrack.app."
                        }
                    }
            }
            if let launchAtLoginMessage {
                SettingsNote(launchAtLoginMessage) {
                    if LaunchAtLogin.requiresApproval {
                        Button("Open Login Items…", action: LaunchAtLogin.openSystemSettings)
                            .controlSize(.small)
                    }
                }
            }
            SettingsDivider()
            menuBarOptions
        }
    }

    private var menuBarOptions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Menu bar shows")
            HStack(alignment: .top, spacing: 16) {
                DisplayOptionsColumn(title: "5-hour window", name: "5h", options: $preferences.fiveHourDisplay)
                DisplayOptionsColumn(title: "Weekly window", name: "7d", options: $preferences.sevenDayDisplay)
            }
            .padding(.leading, 2)
            HStack(spacing: 10) {
                Text("Preview")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Image(nsImage: menuBarPreview)
                    .renderingMode(.template)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 5))
            }
            if preferences.fiveHourDisplay.isEmpty && preferences.sevenDayDisplay.isEmpty {
                Text("Nothing selected: the 5-hour ring stays visible so CapTrack can still be opened.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .animation(Self.animation, value: preferences.fiveHourDisplay.isEmpty && preferences.sevenDayDisplay.isEmpty)
    }

    /// The menu bar item as it would look with sample data and the current options.
    private var menuBarPreview: NSImage {
        let now = Date.now
        let segments = StatusItemRenderer.segments(
            fiveHour: .active(RateWindow(usedPercentage: 34, resetsAt: now.addingTimeInterval(2 * 3600 + 5 * 60 + 30))),
            sevenDay: .active(RateWindow(usedPercentage: 61, resetsAt: now.addingTimeInterval(3 * 86_400 + 4 * 3600 + 30))),
            fiveHourOptions: preferences.fiveHourDisplay,
            sevenDayOptions: preferences.sevenDayDisplay,
            hasData: true,
            now: now
        )
        return StatusItemRenderer.image(segments: segments)
    }

    // MARK: Claude Code

    private var claudeCodeSection: some View {
        SettingsSection("Claude Code") {
            SettingsRow("Status") {
                HStack(spacing: 10) {
                    if checkedRecently {
                        Text("Checked just now")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .transition(.opacity.combined(with: .move(edge: .trailing)))
                    }
                    Label {
                        Text(isChecking ? "Checking…" : statusTitle)
                            .foregroundStyle(monitor.status.isConfigured && !isChecking ? .primary : .secondary)
                            .contentTransition(.opacity)
                    } icon: {
                        if isChecking {
                            ProgressView()
                                .controlSize(.small)
                                .transition(.opacity)
                        } else {
                            Image(systemName: statusSymbol)
                                .foregroundStyle(statusColor)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    Button(action: runManualCheck) {
                        Image(systemName: "arrow.clockwise")
                            .rotationEffect(.degrees(refreshSpin))
                    }
                    .buttonStyle(.borderless)
                    .disabled(isChecking)
                    .help("Check the connection again")
                    .accessibilityLabel("Check again")
                }
                .animation(Self.animation, value: isChecking)
                .animation(Self.animation, value: checkedRecently)
            }

            switch monitor.status {
            case .configured:
                SettingsNote("Claude Code hands its status line data to CapTrack. Usage appears after the next response in a Claude Code session.")
            case .notConfigured, .unreadable:
                SettingsNote("CapTrack adds a small bridge script to the status line command in ~/.claude/settings.json. An existing status line keeps working; a backup of the file is created.") {
                    Button("Set Up Automatically", action: configureAutomatically)
                }
            case .claudeCodeNotFound:
                SettingsNote("No ~/.claude directory found. Install Claude Code and sign in with a Pro or Max subscription first.")
            }

            if let integrationMessage {
                SettingsNote(integrationMessage, color: .red)
            }

            SettingsDivider()

            // The whole row toggles the disclosure, not just the chevron.
            Button {
                withAnimation(Self.animation) { showManualSetup.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(showManualSetup ? 90 : 0))
                        .frame(width: 12)
                    Text("Manual setup")
                    Spacer()
                }
                .contentShape(Rectangle())
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isButton)

            if showManualSetup {
                manualSetup
                    .transition(.opacity)
            }
        }
    }

    private var manualSetup: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Add this to ~/.claude/settings.json (replacing any existing statusLine entry):")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(monitor.snippet)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
            HStack {
                Button(copied ? "Copied" : "Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(monitor.snippet, forType: .string)
                    copied = true
                }
                .controlSize(.small)
                Text("The bridge script lives at ~/.local/bin/captrack-statusline.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .padding(.top, 2)
    }

    private var statusTitle: String {
        switch monitor.status {
        case .configured: "Connected"
        case .notConfigured: "Not set up"
        case .claudeCodeNotFound: "Claude Code not found"
        case .unreadable: "Settings unreadable"
        }
    }

    private var statusSymbol: String {
        switch monitor.status {
        case .configured: "checkmark.circle.fill"
        case .notConfigured: "circle.dashed"
        case .claudeCodeNotFound, .unreadable: "exclamationmark.triangle.fill"
        }
    }

    private var statusColor: Color {
        switch monitor.status {
        case .configured: .green
        case .notConfigured: .secondary
        case .claudeCodeNotFound, .unreadable: .orange
        }
    }

    private func configureAutomatically() {
        do {
            try monitor.configureAutomatically()
            integrationMessage = nil
        } catch {
            integrationMessage = error.localizedDescription
        }
    }

    private func refreshStatus() {
        monitor.refresh()
        launchAtLogin = LaunchAtLogin.isEnabled
    }

    /// The check itself takes milliseconds; give it a visible duration so the user sees it happen.
    private func runManualCheck() {
        guard !isChecking else { return }
        checkTask?.cancel()
        checkedRecently = false
        isChecking = true
        withAnimation(.easeInOut(duration: 0.7)) { refreshSpin += 360 }

        checkTask = Task {
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            refreshStatus()
            isChecking = false
            checkedRecently = true
            try? await Task.sleep(for: .milliseconds(2500))
            guard !Task.isCancelled else { return }
            checkedRecently = false
        }
    }

    // MARK: Updates

    private var updatesSection: some View {
        SettingsSection("Updates") {
            SettingsRow("Version") {
                Text(AppInfo.version).foregroundStyle(.secondary)
            }
            SettingsDivider()
            SettingsRow("Check for updates automatically") {
                Toggle("Check for updates automatically", isOn: $preferences.automaticUpdateChecks)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            SettingsDivider()
            HStack(spacing: 10) {
                Button("Check Now") {
                    Task { await updateChecker.check() }
                }
                .disabled(updateChecker.state == .checking)
                updateStatus
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }

    @ViewBuilder
    private var updateStatus: some View {
        switch updateChecker.state {
        case .idle:
            EmptyView()
        case .checking:
            ProgressView().controlSize(.small)
            Text("Checking…").font(.caption).foregroundStyle(.secondary)
        case .upToDate:
            Text("You're up to date.").font(.caption).foregroundStyle(.secondary)
        case .available(let release):
            Text("Version \(release.version) is available.").font(.caption)
            Button("Download") {
                NSWorkspace.shared.open(release.downloadURL ?? release.pageURL)
            }
            .controlSize(.small)
        case .failed(let message):
            Text(message).font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: About

    private var aboutSection: some View {
        SettingsSection(nil) {
            SettingsRow("Source code") {
                Link("github.com/\(AppInfo.repository)", destination: AppInfo.repositoryURL)
            }
            SettingsNote("Open source under the MIT license. No third-party code, no accounts, no telemetry. The only network request is the update check against GitHub.")
        }
    }
}

// MARK: - Building blocks that mimic the grouped settings look

private struct SettingsSection<Content: View>: View {
    let title: String?
    @ViewBuilder let content: Content

    init(_ title: String?, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(.headline)
                    .padding(.leading, 2)
            }
            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .quaternarySystemFill), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(nsColor: .separatorColor).opacity(0.6)))
        }
    }
}

private struct SettingsRow<Control: View>: View {
    let label: String
    @ViewBuilder let control: Control

    init(_ label: String, @ViewBuilder control: () -> Control) {
        self.label = label
        self.control = control()
    }

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            control
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

private struct SettingsNote<Accessory: View>: View {
    let text: String
    var color: Color = .secondary
    @ViewBuilder let accessory: Accessory

    init(_ text: String, color: Color = .secondary, @ViewBuilder accessory: () -> Accessory = { EmptyView() }) {
        self.text = text
        self.color = color
        self.accessory = accessory()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text)
                .font(.caption)
                .foregroundStyle(color)
                .fixedSize(horizontal: false, vertical: true)
            accessory
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }
}

private struct DisplayOptionsColumn: View {
    let title: String
    let name: String
    @Binding var options: WindowDisplayOptions

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .padding(.bottom, 2)
            Toggle("Name (\(name))", isOn: $options.label)
            Toggle("Ring", isOn: $options.ring)
            Toggle("Percentage", isOn: $options.percentage)
            Toggle("Reset time", isOn: $options.resetTime)
        }
        .toggleStyle(.checkbox)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SettingsDivider: View {
    var body: some View {
        Divider().padding(.leading, 12)
    }
}
