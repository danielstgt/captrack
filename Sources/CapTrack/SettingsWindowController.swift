import AppKit
import SwiftUI

/// Owns the settings window and keeps its height in step with the SwiftUI content.
///
/// The hosting controller's automatic sizing is switched off because it snaps the window
/// to the final size the moment the content changes. Instead the view reports its ideal
/// size and the window animates there with the same duration as the content animation.
final class SettingsWindowController {
    static let animationDuration: TimeInterval = 0.25

    private(set) var window: NSWindow?
    private var pendingSize: CGSize?

    init(preferences: Preferences, updateChecker: UpdateChecker, monitor: IntegrationMonitor, expandManualSetup: Bool = false) {
        let view = SettingsView(
            preferences: preferences,
            updateChecker: updateChecker,
            monitor: monitor,
            expandManualSetup: expandManualSetup,
            onSizeChange: { [weak self] size in self?.contentSizeChanged(size) }
        )
        let controller = NSHostingController(rootView: view)
        controller.sizingOptions = []

        let window = NSWindow(contentViewController: controller)
        window.title = "CapTrack Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        self.window = window

        controller.view.layoutSubtreeIfNeeded()
        if let pendingSize {
            apply(pendingSize, animated: false)
            self.pendingSize = nil
        }
        window.center()
    }

    func show() {
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func contentSizeChanged(_ size: CGSize) {
        guard let window else {
            pendingSize = size
            return
        }
        apply(size, animated: window.isVisible)
    }

    /// Resizes the window so its content area matches `size`, keeping the top-left corner fixed.
    private func apply(_ size: CGSize, animated: Bool) {
        guard let window else { return }
        let current = window.contentRect(forFrameRect: window.frame).size
        let widthDelta = size.width - current.width
        let heightDelta = size.height - current.height
        guard abs(widthDelta) > 0.5 || abs(heightDelta) > 0.5 else { return }

        var frame = window.frame
        frame.size.width += widthDelta
        frame.size.height += heightDelta
        frame.origin.y -= heightDelta

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Self.animationDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().setFrame(frame, display: true)
            }
        } else {
            window.setFrame(frame, display: true)
        }
    }
}
