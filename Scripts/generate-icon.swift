#!/usr/bin/env swift
// Rasterises Assets/logo.svg into the PNG sizes `iconutil` expects.
// Usage: swift Scripts/generate-icon.swift <logo.svg> <output.iconset>
import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    FileHandle.standardError.write(Data("usage: generate-icon.swift <logo.svg> <output.iconset>\n".utf8))
    exit(64)
}
guard let logo = NSImage(contentsOfFile: arguments[1]) else {
    FileHandle.standardError.write(Data("Could not load \(arguments[1])\n".utf8))
    exit(1)
}

let outputDirectory = URL(fileURLWithPath: arguments[2])
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { exit(1) }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSGraphicsContext.current?.imageInterpolation = .high
        logo.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels),
                  from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()

        guard let png = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try png.write(to: outputDirectory.appending(path: name))
    }
}
print("Wrote iconset to \(outputDirectory.path)")
