import AppKit

// Compose stills from the demo fixture and native view renders.
enum DemoCanvas {
    static let width = 1920
    static func image(height: Int, _ draw: () -> Void) -> NSImage {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        draw()
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: NSSize(width: width, height: height)); image.addRepresentation(bitmap)
        return image
    }
    static func save(_ image: NSImage, to url: URL) throws {
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        try bitmap.representation(using: .png, properties: [:])!.write(to: url)
    }
    static func text(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat = 1100, size: CGFloat = 20, color: NSColor = .white, weight: NSFont.Weight = .regular) {
        (text as NSString).draw(in: NSRect(x: x, y: y, width: width, height: size * 2.8), withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color])
    }
    static func box(_ rect: NSRect, color: NSColor, radius: CGFloat = 16) {
        color.setFill(); NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
    }
    static func background(height: Int) {
        NSGradient(starting: NSColor(red: 0.035, green: 0.05, blue: 0.09, alpha: 1), ending: NSColor(red: 0.09, green: 0.15, blue: 0.22, alpha: 1))!.draw(in: NSRect(x: 0, y: 0, width: width, height: height), angle: 30)
    }
}
