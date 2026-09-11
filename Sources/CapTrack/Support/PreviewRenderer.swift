import AppKit
import QuartzCore
import SwiftUI

/// Renders the popover with sample data into PNG files for the README (`make preview`).
enum PreviewRenderer {
    static func outputPath(from arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: "--render-preview"), index + 1 < arguments.count else {
            return nil
        }
        return arguments[index + 1]
    }

    static func render(to directory: String) {
        let now = Date.now
        let snapshot = UsageSnapshot(
            hasRateLimits: true,
            fiveHour: RateWindow(usedPercentage: 34, resetsAt: now.addingTimeInterval(2 * 3600 + 5 * 60 + 45)),
            sevenDay: RateWindow(usedPercentage: 61, resetsAt: now.addingTimeInterval(3 * 86_400 + 4 * 3600 + 45)),
            receivedAt: now.addingTimeInterval(-120)
        )
        let store = UsageStore.fixed(snapshot)

        let preferences = Preferences(defaults: UserDefaults(suiteName: "io.github.danielstgt.captrack.preview")!)
        let sampleHome = FileManager.default.temporaryDirectory.appending(path: "captrack-preview")
        try? FileManager.default.createDirectory(at: sampleHome.appending(path: ".claude"), withIntermediateDirectories: true)
        let monitor = IntegrationMonitor(integration: ClaudeCodeIntegration(home: sampleHome))
        let settings = SettingsView(
            preferences: preferences,
            updateChecker: UpdateChecker(preferences: preferences),
            monitor: monitor
        )

        for scheme in [ColorScheme.light, .dark] {
            let suffix = scheme == .dark ? "dark" : "light"
            writeMenuBar(snapshot: snapshot, now: now, dark: scheme == .dark, to: "\(directory)/menubar-\(suffix).png")
            let popover = UsageView(store: store, monitor: monitor, onOpenSettings: {}, onQuit: {})
                .background(.background)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            write(popover, scheme: scheme, to: "\(directory)/preview-\(suffix).png")
            // Forms are AppKit-backed, which ImageRenderer skips; draw them through a hosting view.
            writeHosted(settings, scheme: scheme, to: "\(directory)/settings-\(suffix).png")
        }
    }

    private static func write(_ view: some View, scheme: ColorScheme, to path: String) {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, scheme))
        renderer.scale = 2
        guard let cgImage = renderer.cgImage else {
            FileHandle.standardError.write(Data("Rendering \(path) failed.\n".utf8))
            exit(1)
        }
        save(NSBitmapImageRep(cgImage: cgImage), to: path)
    }

    private static func writeHosted(_ view: some View, scheme: ColorScheme, to path: String) {
        _ = NSApplication.shared
        let appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        let hosting = NSHostingView(rootView: view)
        hosting.appearance = appearance
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)

        // SwiftUI draws through Core Animation, which only commits for windows that are on
        // screen. Keep the window fully transparent so nothing is visible while rendering.
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = appearance
        window.contentView = hosting
        window.alphaValue = 0
        window.orderFrontRegardless()
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: .now + 0.5)
        CATransaction.flush()
        hosting.displayIfNeeded()
        RunLoop.main.run(until: .now + 0.2)

        // Render the layer tree rather than asking views to draw: SwiftUI content lives in
        // Core Animation layers, which `cacheDisplay` does not always reach.
        let scale: CGFloat = 2
        guard let layer = hosting.layer,
              let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: Int(hosting.bounds.width * scale), pixelsHigh: Int(hosting.bounds.height * scale),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
              ),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            FileHandle.standardError.write(Data("Rendering \(path) failed.\n".utf8))
            exit(1)
        }
        bitmap.size = hosting.bounds.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        let cgContext = context.cgContext
        cgContext.saveGState()
        cgContext.scaleBy(x: scale, y: scale)
        // The view itself is transparent; paint the window background the appearance would give it.
        appearance?.performAsCurrentDrawingAppearance {
            NSColor.windowBackgroundColor.setFill()
            hosting.bounds.fill()
        }
        // The hosting view is flipped; undo that so the image is the right way up.
        cgContext.translateBy(x: 0, y: hosting.bounds.height)
        cgContext.scaleBy(x: 1, y: -1)
        layer.render(in: cgContext)
        cgContext.restoreGState()
        NSGraphicsContext.restoreGraphicsState()
        window.orderOut(nil)
        save(bitmap, to: path)
    }

    /// The exact status item image, tinted the way the menu bar would tint a template image.
    private static func writeMenuBar(snapshot: UsageSnapshot, now: Date, dark: Bool, to path: String) {
        let segments = StatusItemRenderer.segments(
            fiveHour: WindowState(window: snapshot.fiveHour, hasRateLimits: true, now: now),
            sevenDay: WindowState(window: snapshot.sevenDay, hasRateLimits: true, now: now),
            fiveHourOptions: .all,
            sevenDayOptions: .all,
            hasData: true,
            now: now
        )
        let item = StatusItemRenderer.image(segments: segments)
        let padding: CGFloat = 14
        let size = NSSize(width: item.size.width + padding * 2, height: 24)
        let scale: CGFloat = 2

        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { exit(1) }
        bitmap.size = size

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let bounds = NSRect(origin: .zero, size: size)
        (dark ? NSColor(white: 0.16, alpha: 1) : NSColor(white: 0.93, alpha: 1)).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
        let itemRect = NSRect(x: padding, y: (size.height - item.size.height) / 2, width: item.size.width, height: item.size.height)
        tinted(item, with: dark ? .white : .black).draw(in: itemRect, from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()

        save(bitmap, to: path)
    }

    /// Recolours a template image the way the menu bar does: keep the alpha, replace the colour.
    private static func tinted(_ image: NSImage, with color: NSColor) -> NSImage {
        let copy = image.copy() as! NSImage
        copy.isTemplate = false
        return NSImage(size: image.size, flipped: false) { rect in
            copy.draw(in: rect)
            color.setFill()
            rect.fill(using: .sourceAtop)
            return true
        }
    }

    private static func save(_ bitmap: NSBitmapImageRep, to path: String) {
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            FileHandle.standardError.write(Data("Encoding \(path) failed.\n".utf8))
            exit(1)
        }
        do {
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try png.write(to: url)
            print("Wrote \(path)")
        } catch {
            FileHandle.standardError.write(Data("Could not write \(path): \(error)\n".utf8))
            exit(1)
        }
    }
}
