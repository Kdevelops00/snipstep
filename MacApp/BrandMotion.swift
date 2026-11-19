import SwiftUI

/// Two offset capture brackets form an S: the saved moment and the return to it.
struct BrandMark: View {
    var body: some View {
        Canvas { context, size in
            context.scaleBy(x: min(size.width, size.height) / 100, y: min(size.width, size.height) / 100)
            var upper = Path()
            upper.move(to: CGPoint(x: 72, y: 25)); upper.addLine(to: CGPoint(x: 39, y: 25))
            upper.addQuadCurve(to: CGPoint(x: 28, y: 36), control: CGPoint(x: 28, y: 25))
            upper.addLine(to: CGPoint(x: 28, y: 47)); upper.addLine(to: CGPoint(x: 61, y: 47))
            var lower = Path()
            lower.move(to: CGPoint(x: 28, y: 75)); lower.addLine(to: CGPoint(x: 61, y: 75))
            lower.addQuadCurve(to: CGPoint(x: 72, y: 64), control: CGPoint(x: 72, y: 75))
            lower.addLine(to: CGPoint(x: 72, y: 53)); lower.addLine(to: CGPoint(x: 39, y: 53))
            let stroke = StrokeStyle(lineWidth: 8, lineCap: .square, lineJoin: .round)
            context.stroke(upper, with: .color(.primary), style: stroke)
            context.stroke(lower, with: .color(.blue.opacity(0.8)), style: stroke)
        }.accessibilityHidden(true)
    }
}

struct SoftPress: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(reduceMotion ? nil : .spring(duration: 0.25), value: configuration.isPressed)
    }
}
