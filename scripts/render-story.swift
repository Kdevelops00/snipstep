import AppKit

@main struct ProductStory {
    static func main() throws {
        let assets = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let output = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)

        func asset(_ name: String, in bounds: NSRect, topFraction: CGFloat = 1) {
            let url = assets.appendingPathComponent(name + ".png")
            guard let image = NSImage(contentsOf: url), image.size.width > 0, image.size.height > 0 else {
                preconditionFailure("Missing demo asset: \(url.lastPathComponent)")
            }
            let source = NSRect(x: 0, y: image.size.height * (1 - topFraction),
                                width: image.size.width, height: image.size.height * topFraction)
            let scale = min(bounds.width / source.width, bounds.height / source.height)
            let size = NSSize(width: source.width * scale, height: source.height * scale)
            let rect = NSRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2,
                              width: size.width, height: size.height)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current?.imageInterpolation = .high
            NSBezierPath(roundedRect: rect, xRadius: 14, yRadius: 14).addClip()
            image.draw(in: rect, from: source, operation: .sourceOver, fraction: 1)
            NSGraphicsContext.restoreGraphicsState()
        }

        func save(_ name: String, height: Int, draw: () -> Void) throws {
            let image = DemoCanvas.image(height: height) {
                DemoCanvas.background(height: height)
                draw()
            }
            try DemoCanvas.save(image, to: output.appendingPathComponent(name + ".png"))
        }

        try save("capture-to-task", height: 720) {
            DemoCanvas.text("Find something to try", x: 54, y: 567, size: 38, weight: .semibold)
            DemoCanvas.text("Save it as a task", x: 989, y: 567, size: 38, weight: .semibold)
            asset("reference", in: NSRect(x: 54, y: 75, width: 880, height: 475))
            asset("library", in: NSRect(x: 989, y: 75, width: 877, height: 475), topFraction: 0.48)
        }
        try save("saved-screenshot", height: 1160) {
            asset("detail", in: NSRect(x: 50, y: 35, width: 1820, height: 1090), topFraction: 0.89)
        }
        try save("desktop-checklist", height: 560) {
            DemoCanvas.text("On your list", x: 54, y: 408, size: 35, weight: .semibold)
            DemoCanvas.text("Checked off", x: 989, y: 408, size: 35, weight: .semibold)
            let before = NSRect(x: 54, y: 38, width: 877, height: 400)
            let after = NSRect(x: 989, y: 38, width: 877, height: 400)
            for bounds in [before, after] {
                DemoCanvas.box(bounds, color: NSColor(white: 1, alpha: 0.10), radius: 25)
            }
            asset("widget", in: before)
            asset("widget-done", in: after)
        }
    }

}
