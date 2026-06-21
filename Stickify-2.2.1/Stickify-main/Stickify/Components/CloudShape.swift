import SwiftUI

struct CloudShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let y = rect.midY + rect.height * 0.12
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.13, y: y))
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.34, y: rect.minY + rect.height * 0.33),
            control1: CGPoint(x: rect.minX + rect.width * 0.13, y: rect.minY + rect.height * 0.5),
            control2: CGPoint(x: rect.minX + rect.width * 0.22, y: rect.minY + rect.height * 0.34)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.58, y: rect.minY + rect.height * 0.23),
            control1: CGPoint(x: rect.minX + rect.width * 0.39, y: rect.minY + rect.height * 0.08),
            control2: CGPoint(x: rect.minX + rect.width * 0.53, y: rect.minY + rect.height * 0.04)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.84, y: y),
            control1: CGPoint(x: rect.minX + rect.width * 0.72, y: rect.minY + rect.height * 0.14),
            control2: CGPoint(x: rect.minX + rect.width * 0.84, y: rect.minY + rect.height * 0.27)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.76, y: rect.maxY - rect.height * 0.18),
            control1: CGPoint(x: rect.maxX, y: y),
            control2: CGPoint(x: rect.maxX, y: rect.maxY - rect.height * 0.18)
        )
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.21, y: rect.maxY - rect.height * 0.18))
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.13, y: y),
            control1: CGPoint(x: rect.minX + rect.width * 0.03, y: rect.maxY - rect.height * 0.18),
            control2: CGPoint(x: rect.minX + rect.width * 0.02, y: y)
        )
        path.closeSubpath()
        return path
    }
}

struct CloudCard<Content: View>: View {
    var dashed = false
    var tint: Color = .white
    @ViewBuilder var content: Content

    var body: some View {
        CloudShape()
            .fill(dashed ? tint.opacity(0.24) : tint.opacity(0.78))
            .overlay {
                CloudShape()
                    .stroke(dashed ? StickifyTheme.classicBlue : .white.opacity(0.46), style: StrokeStyle(lineWidth: 2.5, dash: dashed ? [7, 6] : []))
            }
            .shadow(color: (dashed ? StickifyTheme.classicBlue : tint).opacity(dashed ? 0 : 0.18), radius: 10, x: 0, y: 8)
            .overlay(content)
    }
}


