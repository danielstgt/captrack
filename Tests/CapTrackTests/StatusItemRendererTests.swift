import AppKit
import Testing
@testable import CapTrack

struct StatusItemRendererTests {
    let now = Date(timeIntervalSince1970: 1_000_000)
    var fiveHour: WindowState { .active(RateWindow(usedPercentage: 34, resetsAt: now.addingTimeInterval(2 * 3600 + 5 * 60))) }
    var sevenDay: WindowState { .active(RateWindow(usedPercentage: 61, resetsAt: now.addingTimeInterval(3 * 86_400 + 4 * 3600))) }

    private func segments(_ five: WindowDisplayOptions, _ seven: WindowDisplayOptions,
                          fiveHour: WindowState? = nil, sevenDay: WindowState? = nil, hasData: Bool = true) -> [StatusSegment] {
        StatusItemRenderer.segments(
            fiveHour: fiveHour ?? self.fiveHour, sevenDay: sevenDay ?? self.sevenDay,
            fiveHourOptions: five, sevenDayOptions: seven, hasData: hasData, now: now
        )
    }

    @Test func everythingEnabledShowsBothWindows() {
        #expect(segments(.all, .all) == [
            .label("5h"), .ring(0.34), .value("34%"), .time("2h05m"),
            .gap,
            .label("7d"), .ring(0.61), .value("61%"), .time("3d04h"),
        ])
    }

    @Test func optionsSelectParts() {
        #expect(segments(.all, .none) == [.label("5h"), .ring(0.34), .value("34%"), .time("2h05m")])
        #expect(segments(.none, WindowDisplayOptions(label: false, ring: true, percentage: true, resetTime: false))
                == [.ring(0.61), .value("61%")])
        #expect(segments(WindowDisplayOptions(label: true, ring: false, percentage: false, resetTime: true), .none)
                == [.label("5h"), .time("2h05m")])
        // Nothing selected keeps a clickable ring; no data shows the waiting ring.
        #expect(segments(.none, .none) == [.ring(0.34)])
        #expect(segments(.all, .all, fiveHour: .unavailable, sevenDay: .unavailable, hasData: false) == [.ring(nil)])
        // No countdown once a window has reset or is idle.
        #expect(segments(.all, .all, fiveHour: .idle, sevenDay: .reset(at: now))
                == [.label("5h"), .ring(0), .value("0%"), .gap, .label("7d"), .ring(0), .value("0%")])
    }

    @Test func imageGrowsWithContent() {
        let full = StatusItemRenderer.image(segments: segments(.all, .all))
        let single = StatusItemRenderer.image(segments: segments(.all, .none))
        let rings = StatusItemRenderer.image(segments: [.ring(0.5), .gap, .ring(0.5)])
        let waiting = StatusItemRenderer.image(segments: [.ring(nil)])

        #expect(full.isTemplate)
        #expect(full.size.height == StatusItemRenderer.height)
        #expect(full.size.width > single.size.width)
        #expect(single.size.width > rings.size.width)
        #expect(rings.size.width > waiting.size.width)
        #expect(waiting.size.width == StatusItemRenderer.ringDiameter)
        #expect(opaquePixels(in: full) > opaquePixels(in: single))
        #expect(opaquePixels(in: waiting) > 0)
    }

    private func opaquePixels(in image: NSImage) -> Int {
        let width = Int(image.size.width * 2), height = Int(image.size.height * 2)
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        image.draw(in: NSRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()
        var count = 0
        for x in 0..<width {
            for y in 0..<height where (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.2 { count += 1 }
        }
        return count
    }
}
