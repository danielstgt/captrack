import AppKit

/// One building block of the menu bar item: `5h ◔ 34% 2h05m   7d ◑ 61% 3d04h`.
nonisolated enum StatusSegment: Equatable, Sendable {
    /// Window label such as "5h" or "7d", drawn muted.
    case label(String)
    /// Ring filled to the given fraction; nil draws the "no data" ring.
    case ring(Double?)
    /// Percentage, drawn in full strength.
    case value(String)
    /// Countdown to the reset, drawn muted.
    case time(String)
    /// Space between the two windows.
    case gap
}

/// Draws the whole menu bar item as a single template image, so it follows the menu
/// bar appearance and stays crisp on any display.
enum StatusItemRenderer {
    static let height: CGFloat = 18
    /// Vertical centre line shared by rings and text. Half a point above the geometric
    /// centre, which is where macOS places its own menu bar text.
    static let centerY: CGFloat = height / 2 + 0.5
    static let ringDiameter: CGFloat = 13
    static let ringLineWidth: CGFloat = 2
    static let spacing: CGFloat = 4
    static let gapWidth: CGFloat = 10
    static let mutedAlpha: CGFloat = 0.55

    static var font: NSFont {
        .monospacedDigitSystemFont(ofSize: NSFont.menuBarFont(ofSize: 0).pointSize, weight: .regular)
    }

    // MARK: - Segments

    static func segments(
        fiveHour: WindowState,
        sevenDay: WindowState,
        fiveHourOptions: WindowDisplayOptions,
        sevenDayOptions: WindowDisplayOptions,
        hasData: Bool,
        now: Date
    ) -> [StatusSegment] {
        guard hasData else { return [.ring(nil)] }

        func group(_ label: String, _ state: WindowState, _ options: WindowDisplayOptions) -> [StatusSegment] {
            var segments: [StatusSegment] = []
            if options.label { segments.append(.label(label)) }
            if options.ring { segments.append(.ring(state.percentage.map { $0 / 100 })) }
            if options.percentage { segments.append(.value(Formatting.percent(state.percentage))) }
            if options.resetTime, case .active(let window) = state {
                segments.append(.time(Formatting.countdown(to: window.resetsAt, from: now, compact: true)))
            }
            return segments
        }

        let first = group("5h", fiveHour, fiveHourOptions)
        let second = group("7d", sevenDay, sevenDayOptions)
        switch (first.isEmpty, second.isEmpty) {
        case (false, false): return first + [.gap] + second
        case (false, true): return first
        case (true, false): return second
        // Nothing selected: keep the item clickable with the 5-hour ring.
        case (true, true): return [.ring(fiveHour.percentage.map { $0 / 100 })]
        }
    }

    // MARK: - Drawing

    static func image(segments: [StatusSegment]) -> NSImage {
        // Lay out first so the image gets its final width.
        var placed: [(segment: StatusSegment, x: CGFloat, width: CGFloat)] = []
        var x: CGFloat = 0
        for (index, segment) in segments.enumerated() {
            let width: CGFloat
            switch segment {
            case .label(let text), .value(let text), .time(let text):
                width = ceil(attributed(text, muted: false).size().width)
            case .ring:
                width = ringDiameter
            case .gap:
                width = gapWidth
            }
            if index > 0, segment != .gap, segments[index - 1] != .gap { x += spacing }
            placed.append((segment, x, width))
            x += width
        }
        let totalWidth = max(ceil(x), ringDiameter)

        let image = NSImage(size: NSSize(width: totalWidth, height: height), flipped: false) { _ in
            for item in placed {
                switch item.segment {
                case .label(let text), .time(let text):
                    draw(text: text, muted: true, atX: item.x)
                case .value(let text):
                    draw(text: text, muted: false, atX: item.x)
                case .ring(let fraction):
                    let rect = NSRect(x: item.x, y: centerY - ringDiameter / 2, width: ringDiameter, height: ringDiameter)
                    drawRing(in: rect, fraction: fraction)
                case .gap:
                    break
                }
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func attributed(_ text: String, muted: Bool) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: NSColor.black.withAlphaComponent(muted ? mutedAlpha : 1),
        ])
    }

    private static func draw(text: String, muted: Bool, atX x: CGFloat) {
        let string = attributed(text, muted: muted)
        // Centre the cap height (digits, capitals) on the centre line. Centring the line box
        // instead would sit the glyphs too low, because its ascender is far taller than its descender.
        let baseline = centerY - font.capHeight / 2
        string.draw(at: NSPoint(x: x, y: (baseline + font.descender).rounded()))
    }

    static func drawRing(in rect: NSRect, fraction: Double?) {
        let circle = rect.insetBy(dx: ringLineWidth / 2, dy: ringLineWidth / 2)
        let center = NSPoint(x: circle.midX, y: circle.midY)
        let radius = circle.width / 2

        let track = NSBezierPath(ovalIn: circle)
        track.lineWidth = ringLineWidth
        NSColor.black.withAlphaComponent(fraction == nil ? 0.45 : 0.28).setStroke()
        track.stroke()

        if let fraction, fraction > 0 {
            let arc = NSBezierPath()
            // Angles are counter-clockwise from 3 o'clock; start at 12 o'clock and run clockwise.
            arc.appendArc(withCenter: center, radius: radius,
                          startAngle: 90, endAngle: 90 - 360 * min(fraction, 1), clockwise: true)
            arc.lineWidth = ringLineWidth
            arc.lineCapStyle = .round
            NSColor.black.setStroke()
            arc.stroke()
        } else if fraction == nil {
            let dot = NSBezierPath(ovalIn: NSRect(x: center.x - 1.5, y: center.y - 1.5, width: 3, height: 3))
            NSColor.black.withAlphaComponent(0.45).setFill()
            dot.fill()
        }
    }
}
