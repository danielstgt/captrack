#!/usr/bin/env swift
// Renders the social preview ("Open Graph" image) shown when the repository is shared.
// GitHub: Settings › General › Social preview. Recommended 1280×640, under 1 MB.
//
//   ./Art/generate-og-image.swift                          -> Art/og-image.jpg (2560×1280)
//   ./Art/generate-og-image.swift <logo.svg> <output.jpg|png> [--scale 2]
//
// Pure AppKit / CoreGraphics, no dependencies. Text uses the system font (SF Pro).
// The output format follows the file extension; JPEG keeps a 2x render under 1 MB.
import AppKit

// MARK: - Arguments

var arguments = Array(CommandLine.arguments.dropFirst())
var scale: CGFloat = 2
if let index = arguments.firstIndex(of: "--scale"), index + 1 < arguments.count, let value = Double(arguments[index + 1]) {
    scale = CGFloat(value)
    arguments.removeSubrange(index...index + 1)
}

// Defaults are relative to the repository, i.e. the parent of this script's directory.
let repository = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
    .deletingLastPathComponent().deletingLastPathComponent()
let logoPath: String
let outputURL: URL
switch arguments.count {
case 0:
    logoPath = repository.appending(path: "Assets/logo.svg").path
    outputURL = repository.appending(path: "Art/og-image.jpg")
case 2:
    logoPath = arguments[0]
    outputURL = URL(fileURLWithPath: arguments[1])
default:
    FileHandle.standardError.write(Data("usage: generate-og-image.swift [<logo.svg> <output.jpg|png>] [--scale 2]\n".utf8))
    exit(64)
}
guard let logo = NSImage(contentsOfFile: logoPath) else {
    FileHandle.standardError.write(Data("Could not load \(logoPath)\n".utf8))
    exit(1)
}

// MARK: - Palette (matches the app icon)

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}

let backgroundTop = NSColor(hex: 0x2B2F36)
let backgroundBottom = NSColor(hex: 0x121417)
let teal = NSColor(hex: 0x5AD2D0)
let amber = NSColor(hex: 0xF2B466)
let ink = NSColor(hex: 0xF5F6F8)
let inkMuted = NSColor(hex: 0xB4BAC4)
let inkFaint = NSColor(hex: 0x7C838E)

// MARK: - Canvas

let canvas = NSSize(width: 1280, height: 640)
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(canvas.width * scale), pixelsHigh: Int(canvas.height * scale),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else { exit(1) }
// Set the point size before creating the context so drawing happens in points and
// the context scales to pixels.
bitmap.size = canvas
guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else { exit(1) }

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
context.imageInterpolation = .high
context.shouldAntialias = true
let cg = context.cgContext
let bounds = NSRect(origin: .zero, size: canvas)

// MARK: - Helpers

func attributed(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor,
                kern: CGFloat = 0, monospacedDigits: Bool = false) -> NSAttributedString {
    let font = monospacedDigits
        ? NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
        : NSFont.systemFont(ofSize: size, weight: weight)
    return NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color, .kern: kern])
}

/// Draws text with its baseline-box bottom-left corner at `origin`; returns the drawn width.
@discardableResult
func draw(_ string: NSAttributedString, at origin: NSPoint) -> CGFloat {
    string.draw(at: origin)
    return ceil(string.size().width)
}

func drawRing(center: NSPoint, radius: CGFloat, lineWidth: CGFloat, fraction: CGFloat, color: NSColor) {
    let track = NSBezierPath()
    track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
    track.lineWidth = lineWidth
    NSColor.white.withAlphaComponent(0.22).setStroke()
    track.stroke()

    let arc = NSBezierPath()
    arc.appendArc(withCenter: center, radius: radius, startAngle: 90, endAngle: 90 - 360 * fraction, clockwise: true)
    arc.lineWidth = lineWidth
    arc.lineCapStyle = .round
    color.setStroke()
    arc.stroke()
}

// MARK: - Background

NSGradient(colors: [backgroundBottom, backgroundTop])?.draw(in: bounds, angle: 90)

// Soft colour glows, one per brand colour, and a faint oversized ring as a motif.
for (color, center, radius, alpha) in [
    (teal, NSPoint(x: 1120, y: 560), CGFloat(520), CGFloat(0.16)),
    (amber, NSPoint(x: 180, y: 60), CGFloat(460), CGFloat(0.11)),
] {
    NSGradient(colors: [color.withAlphaComponent(alpha), color.withAlphaComponent(0)])?
        .draw(fromCenter: center, radius: 0, toCenter: center, radius: radius, options: [])
}
let motif = NSBezierPath()
motif.appendArc(withCenter: NSPoint(x: 1235, y: 95), radius: 330, startAngle: 0, endAngle: 360)
motif.lineWidth = 70
NSColor.white.withAlphaComponent(0.035).setStroke()
motif.stroke()

// MARK: - App icon with shadow

let iconRect = NSRect(x: 112, y: (canvas.height - 300) / 2, width: 300, height: 300)
cg.saveGState()
let shadow = NSShadow()
shadow.shadowBlurRadius = 36
shadow.shadowOffset = NSSize(width: 0, height: -16)
shadow.shadowColor = NSColor.black.withAlphaComponent(0.55)
shadow.set()
logo.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1)
cg.restoreGState()

// MARK: - Title and tagline

let textX: CGFloat = 486
draw(attributed("CapTrack", size: 96, weight: .bold, color: ink, kern: -2.5), at: NSPoint(x: textX - 6, y: 392))
draw(attributed("Claude usage limits, right in your macOS menu bar.", size: 30, weight: .regular, color: inkMuted, kern: -0.2),
     at: NSPoint(x: textX, y: 344))

// MARK: - Menu bar item replica

struct Segment { let kind: Kind; enum Kind { case label(String), ring(CGFloat, NSColor), value(String), time(String), gap } }
let segments: [Segment.Kind] = [
    .label("5h"), .ring(0.34, amber), .value("34%"), .time("2h05m"),
    .gap,
    .label("7d"), .ring(0.61, teal), .value("61%"), .time("3d04h"),
]
let stripSize: CGFloat = 27
let ringDiameter: CGFloat = 26
let spacing: CGFloat = 8
let gapWidth: CGFloat = 22

func stripString(_ text: String, muted: Bool) -> NSAttributedString {
    attributed(text, size: stripSize, weight: muted ? .regular : .semibold,
               color: muted ? inkMuted : ink, monospacedDigits: true)
}
var stripWidth: CGFloat = 0
for (index, kind) in segments.enumerated() {
    switch kind {
    case .label(let text), .time(let text): stripWidth += ceil(stripString(text, muted: true).size().width)
    case .value(let text): stripWidth += ceil(stripString(text, muted: false).size().width)
    case .ring: stripWidth += ringDiameter
    case .gap: stripWidth += gapWidth
    }
    if index > 0, case .gap = kind {} else if index > 0, case .gap = segments[index - 1] {} else if index > 0 { stripWidth += spacing }
}

let pillPadding: CGFloat = 26
let pillHeight: CGFloat = 66
let pillRect = NSRect(x: textX, y: 250, width: stripWidth + pillPadding * 2, height: pillHeight)
let pill = NSBezierPath(roundedRect: pillRect, xRadius: 16, yRadius: 16)
NSColor.white.withAlphaComponent(0.07).setFill()
pill.fill()
pill.lineWidth = 1.5
NSColor.white.withAlphaComponent(0.14).setStroke()
pill.stroke()

var cursor = pillRect.minX + pillPadding
let midY = pillRect.midY
for (index, kind) in segments.enumerated() {
    if index > 0, case .gap = kind {} else if index > 0, case .gap = segments[index - 1] {} else if index > 0 { cursor += spacing }
    switch kind {
    case .label(let text), .time(let text):
        let string = stripString(text, muted: true)
        cursor += draw(string, at: NSPoint(x: cursor, y: midY - string.size().height / 2))
    case .value(let text):
        let string = stripString(text, muted: false)
        cursor += draw(string, at: NSPoint(x: cursor, y: midY - string.size().height / 2))
    case .ring(let fraction, let color):
        drawRing(center: NSPoint(x: cursor + ringDiameter / 2, y: midY), radius: ringDiameter / 2 - 2,
                 lineWidth: 4, fraction: fraction, color: color)
        cursor += ringDiameter
    case .gap:
        cursor += gapWidth
    }
}

// MARK: - Feature chips

var chipX = textX
for feature in ["Open source", "Zero dependencies", "Runs locally", "No API keys"] {
    let string = attributed(feature, size: 18, weight: .medium, color: NSColor(hex: 0xDADDE2))
    let width = ceil(string.size().width) + 32
    let rect = NSRect(x: chipX, y: 170, width: width, height: 40)
    let chip = NSBezierPath(roundedRect: rect, xRadius: 20, yRadius: 20)
    NSColor.white.withAlphaComponent(0.05).setFill()
    chip.fill()
    chip.lineWidth = 1.2
    NSColor.white.withAlphaComponent(0.16).setStroke()
    chip.stroke()
    draw(string, at: NSPoint(x: rect.minX + 16, y: rect.midY - string.size().height / 2))
    chipX += width + 12
}

// MARK: - Footer

draw(attributed("github.com/danielstgt/captrack", size: 20, weight: .medium, color: inkFaint, kern: 0.2),
     at: NSPoint(x: textX, y: 104))

NSGraphicsContext.restoreGraphicsState()

// MARK: - Output

let isJPEG = ["jpg", "jpeg"].contains(outputURL.pathExtension.lowercased())
let data: Data?
if isJPEG {
    // The gradient covers the whole canvas, so nothing is lost without an alpha channel.
    data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.93])
} else {
    data = bitmap.representation(using: .png, properties: [:])
}
guard let data else { exit(1) }
try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
try data.write(to: outputURL)
let kilobytes = Double(data.count) / 1024
print(String(format: "Wrote %@ (%dx%d px, %.0f KB)", outputURL.path, bitmap.pixelsWide, bitmap.pixelsHigh, kilobytes))
if data.count > 1_000_000 {
    print("Warning: GitHub accepts social previews up to 1 MB. Use a .jpg output or --scale 1.")
}
