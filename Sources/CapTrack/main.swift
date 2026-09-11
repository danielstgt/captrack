import AppKit

// Hidden developer flag used by `make preview` to render the popover into a PNG
// for the README. Everything else is the regular app lifecycle.
if let outputPath = PreviewRenderer.outputPath(from: CommandLine.arguments) {
    PreviewRenderer.render(to: outputPath)
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
