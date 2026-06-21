import SwiftUI

enum StickifyTheme {
    static let skyBlue = Color(hex: 0x7FD7FF)
    static let classicBlue = Color(hex: 0x0056B8)
    static let energeticRed = Color(hex: 0xE52B1E)
    static let orderGrey = Color(hex: 0xEBEBEB)
    static let carbonBlack = Color(hex: 0x2D2926)
    static let paper = Color(hex: 0xFFFEFA)

    static let softShadow = Color.black.opacity(0.16)
    static let blueGlow = classicBlue.opacity(0.34)
}

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255,
            opacity: alpha
        )
    }
}

struct ScanBracket: View {
    var corner: UIRectCorner

    var body: some View {
        Path { path in
            let size: CGFloat = 42
            switch corner {
            case .topLeft:
                path.move(to: CGPoint(x: 0, y: size))
                path.addLine(to: CGPoint(x: 0, y: 10))
                path.addQuadCurve(to: CGPoint(x: 10, y: 0), control: .zero)
                path.addLine(to: CGPoint(x: size, y: 0))
            case .topRight:
                path.move(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: size - 10, y: 0))
                path.addQuadCurve(to: CGPoint(x: size, y: 10), control: CGPoint(x: size, y: 0))
                path.addLine(to: CGPoint(x: size, y: size))
            case .bottomLeft:
                path.move(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: 0, y: size - 10))
                path.addQuadCurve(to: CGPoint(x: 10, y: size), control: CGPoint(x: 0, y: size))
                path.addLine(to: CGPoint(x: size, y: size))
            default:
                path.move(to: CGPoint(x: 0, y: size))
                path.addLine(to: CGPoint(x: size - 10, y: size))
                path.addQuadCurve(to: CGPoint(x: size, y: size - 10), control: CGPoint(x: size, y: size))
                path.addLine(to: CGPoint(x: size, y: 0))
            }
        }
        .stroke(StickifyTheme.classicBlue, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
        .frame(width: 42, height: 42)
        .shadow(color: .white.opacity(0.8), radius: 2)
    }
}

