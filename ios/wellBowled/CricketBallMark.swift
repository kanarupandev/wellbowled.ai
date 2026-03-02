import SwiftUI

/// Lightweight vector mark: bowl + check + AI magic dust.
struct CricketBallMark: View {
    var size: CGFloat = 100

    private var peacockBlue: Color { Color(red: 0.0, green: 0.427, blue: 0.467) }
    private var grayBlue: Color { Color(red: 0.55, green: 0.66, blue: 0.77) }
    private var deepBlue: Color { Color(red: 0.07, green: 0.14, blue: 0.19) }

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            peacockBlue,
                            grayBlue,
                            deepBlue
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Circle()
                .stroke(Color.white.opacity(0.35), lineWidth: size * 0.018)

            // Gloss highlight
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.white.opacity(0.26), .clear],
                        center: .topLeading,
                        startRadius: 2,
                        endRadius: size * 0.45
                    )
                )
                .scaleEffect(0.85)

            // Check stroke (custom, not Nike clone)
            CheckStrokeShape()
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.98), Color.white.opacity(0.88)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(
                        lineWidth: size * 0.11,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
                .frame(width: size * 0.56, height: size * 0.4)
                .offset(x: size * 0.015, y: size * 0.06)

            MagicDust(size: size)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.25), radius: size * 0.08, x: 0, y: size * 0.05)
    }
}

private struct CheckStrokeShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.04, y: rect.minY + rect.height * 0.58))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.33, y: rect.minY + rect.height * 0.86),
            control: CGPoint(x: rect.minX + rect.width * 0.22, y: rect.minY + rect.height * 0.79)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.96, y: rect.minY + rect.height * 0.14),
            control: CGPoint(x: rect.minX + rect.width * 0.63, y: rect.minY + rect.height * 0.44)
        )
        return path
    }
}

private struct MagicDust: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            // Soft particles
            Circle()
                .fill(Color.white.opacity(0.95))
                .frame(width: size * 0.08, height: size * 0.08)
                .offset(x: size * 0.33, y: -size * 0.34)
                .blur(radius: size * 0.003)

            Circle()
                .fill(Color(red: 0.78, green: 0.92, blue: 1.0).opacity(0.9))
                .frame(width: size * 0.05, height: size * 0.05)
                .offset(x: size * 0.24, y: -size * 0.26)

            Circle()
                .fill(Color(red: 0.88, green: 0.96, blue: 1.0).opacity(0.88))
                .frame(width: size * 0.035, height: size * 0.035)
                .offset(x: size * 0.38, y: -size * 0.21)

            // Tiny sparkle stars
            SparkShape()
                .fill(Color.white.opacity(0.95))
                .frame(width: size * 0.12, height: size * 0.12)
                .offset(x: size * 0.28, y: -size * 0.4)

            SparkShape()
                .fill(Color(red: 0.82, green: 0.94, blue: 1.0).opacity(0.9))
                .frame(width: size * 0.075, height: size * 0.075)
                .offset(x: size * 0.4, y: -size * 0.3)
                .rotationEffect(.degrees(24))
        }
    }
}

private struct SparkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let cx = rect.midX
        let cy = rect.midY
        p.move(to: CGPoint(x: cx, y: rect.minY))
        p.addLine(to: CGPoint(x: cx + rect.width * 0.12, y: cy - rect.height * 0.12))
        p.addLine(to: CGPoint(x: rect.maxX, y: cy))
        p.addLine(to: CGPoint(x: cx + rect.width * 0.12, y: cy + rect.height * 0.12))
        p.addLine(to: CGPoint(x: cx, y: rect.maxY))
        p.addLine(to: CGPoint(x: cx - rect.width * 0.12, y: cy + rect.height * 0.12))
        p.addLine(to: CGPoint(x: rect.minX, y: cy))
        p.addLine(to: CGPoint(x: cx - rect.width * 0.12, y: cy - rect.height * 0.12))
        p.closeSubpath()
        return p
    }
}

#Preview {
    CricketBallMark(size: 100)
}
