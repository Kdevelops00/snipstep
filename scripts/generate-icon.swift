// Original geometric artwork; no third-party images or SF Symbols are embedded.
import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("MacApp/Assets.xcassets/SnipstepGlassIcon.appiconset")
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
var entries: [[String: String]] = []
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                                      samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                      bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let context = NSGraphicsContext.current!.cgContext
        context.scaleBy(x: CGFloat(pixels) / 1_024, y: CGFloat(pixels) / 1_024)
        let background = NSBezierPath(roundedRect: NSRect(x: 50, y: 50, width: 924, height: 924), xRadius: 205, yRadius: 205)
        NSGradient(starting: NSColor(srgbRed: 0.10, green: 0.17, blue: 0.35, alpha: 1), ending: NSColor(srgbRed: 0.33, green: 0.52, blue: 0.86, alpha: 1))!.draw(in: background, angle: 90)
        NSColor.white.withAlphaComponent(0.22).setStroke(); background.lineWidth = 3; background.stroke()
        let upper = NSBezierPath()
        upper.move(to: NSPoint(x: 725, y: 755)); upper.line(to: NSPoint(x: 402, y: 755))
        upper.curve(to: NSPoint(x: 294, y: 647), controlPoint1: NSPoint(x: 332, y: 755), controlPoint2: NSPoint(x: 294, y: 717))
        upper.line(to: NSPoint(x: 294, y: 540)); upper.line(to: NSPoint(x: 617, y: 540))
        NSColor(white: 1, alpha: 0.94).setStroke()
        upper.lineWidth = 78; upper.lineCapStyle = .butt; upper.lineJoinStyle = .round; upper.stroke()
        let lower = NSBezierPath()
        lower.move(to: NSPoint(x: 294, y: 269)); lower.line(to: NSPoint(x: 617, y: 269))
        lower.curve(to: NSPoint(x: 725, y: 377), controlPoint1: NSPoint(x: 687, y: 269), controlPoint2: NSPoint(x: 725, y: 307))
        lower.line(to: NSPoint(x: 725, y: 484)); lower.line(to: NSPoint(x: 402, y: 484))
        NSColor(srgbRed: 0.70, green: 0.86, blue: 1, alpha: 1).setStroke()
        lower.lineWidth = 78; lower.lineCapStyle = .butt; lower.lineJoinStyle = .round; lower.stroke()
        NSGraphicsContext.restoreGraphicsState()
        let filename = "icon-\(size)@\(scale)x.png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: root.appendingPathComponent(filename))
        entries.append(["filename": filename, "idiom": "mac", "scale": "\(scale)x", "size": "\(size)x\(size)"])
    }
}
let catalog: [String: Any] = ["images": entries, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: catalog, options: [.prettyPrinted, .sortedKeys]).write(to: root.appendingPathComponent("Contents.json"))
try JSONSerialization.data(withJSONObject: ["info": ["author": "xcode", "version": 1]], options: [.prettyPrinted])
    .write(to: root.deletingLastPathComponent().appendingPathComponent("Contents.json"))

// Keep the gallery extension's icon in sync with the containing app.
let widgetRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Widgets/Assets.xcassets/SnipstepWidgetIcon.appiconset")
try FileManager.default.createDirectory(at: widgetRoot, withIntermediateDirectories: true)
for file in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) where file.pathExtension == "png" || file.lastPathComponent == "Contents.json" {
    let destination = widgetRoot.appendingPathComponent(file.lastPathComponent)
    if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
    try FileManager.default.copyItem(at: file, to: destination)
}
