import SwiftUI

private let peacockBlue = Color(red: 0, green: 0.427, blue: 0.467)

// MARK: - CalibrationOverlayView

/// Phase 1: Two dashed boxes for stump alignment (detecting).
/// Phase 2: Pitch corridor connecting stump bases (locked) — TV umpire DRS style.
struct CalibrationOverlayView: View {

    let mode: OverlayMode
    let calibrationState: StumpDetectionService.CalibrationState
    let bowlerGuideRect: CGRect   // normalized 0-1
    let strikerGuideRect: CGRect  // normalized 0-1
    let onManualTap: ((CGPoint) -> Void)?

    enum OverlayMode {
        case calibrating  // show 2 dashed boxes
        case active       // show pitch corridor
        case hidden
    }

    @State private var corridorOpacity: Double = 0

    var body: some View {
        switch mode {
        case .hidden:
            EmptyView()

        case .calibrating:
            GeometryReader { geo in
                let size = geo.size
                ZStack {
                    dashedBox(rect: bowlerGuideRect, in: size)
                    dashedBox(rect: strikerGuideRect, in: size)
                }
            }
            .allowsHitTesting(false)

        case .active:
            // Pitch corridor connecting stump bases — like TV DRS pitch map
            GeometryReader { geo in
                let size = geo.size
                pitchCorridor(in: size)
                    .opacity(corridorOpacity)
            }
            .allowsHitTesting(false)
            .onAppear {
                withAnimation(.easeIn(duration: 0.6)) {
                    corridorOpacity = 1.0
                }
            }
        }
    }

    // MARK: - Dashed Box (Phase 1)

    private func dashedBox(rect: CGRect, in size: CGSize) -> some View {
        let frame = denormalize(rect, in: size)
        return RoundedRectangle(cornerRadius: 4)
            .stroke(
                Color.white.opacity(0.6),
                style: StrokeStyle(lineWidth: 1.5, dash: [8, 6])
            )
            .frame(width: frame.width, height: frame.height)
            .position(x: frame.midX, y: frame.midY)
    }

    // MARK: - Pitch Corridor (Phase 2 — TV umpire style)

    private func pitchCorridor(in size: CGSize) -> some View {
        let bowler = denormalize(bowlerGuideRect, in: size)
        let striker = denormalize(strikerGuideRect, in: size)

        return ZStack {
            // Filled corridor — subtle perspective trapezoid
            Path { path in
                path.move(to: CGPoint(x: bowler.minX, y: bowler.maxY))
                path.addLine(to: CGPoint(x: bowler.maxX, y: bowler.maxY))
                path.addLine(to: CGPoint(x: striker.maxX, y: striker.minY))
                path.addLine(to: CGPoint(x: striker.minX, y: striker.minY))
                path.closeSubpath()
            }
            .fill(peacockBlue.opacity(0.08))

            // Corridor edges — thin white lines
            Path { path in
                path.move(to: CGPoint(x: bowler.minX, y: bowler.maxY))
                path.addLine(to: CGPoint(x: bowler.maxX, y: bowler.maxY))
                path.addLine(to: CGPoint(x: striker.maxX, y: striker.minY))
                path.addLine(to: CGPoint(x: striker.minX, y: striker.minY))
                path.closeSubpath()
            }
            .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
        }
    }

    // MARK: - Helpers

    private func denormalize(_ rect: CGRect, in size: CGSize) -> CGRect {
        CGRect(
            x: rect.origin.x * size.width,
            y: rect.origin.y * size.height,
            width: rect.width * size.width,
            height: rect.height * size.height
        )
    }
}

// MARK: - Preview

#if DEBUG
struct CalibrationOverlayView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            CalibrationOverlayView(
                mode: .calibrating,
                calibrationState: .detecting,
                bowlerGuideRect: StumpDetectionService.defaultBowlerGuideRect(),
                strikerGuideRect: StumpDetectionService.defaultStrikerGuideRect(),
                onManualTap: nil
            )
        }
        .previewDisplayName("Detecting — 2 boxes")

        ZStack {
            Color.black.ignoresSafeArea()
            CalibrationOverlayView(
                mode: .active,
                calibrationState: .locked(
                    StumpCalibration(
                        bowlerStumpCenter: CGPoint(x: 0.5, y: 0.175),
                        strikerStumpCenter: CGPoint(x: 0.5, y: 0.825),
                        frameWidth: 1920,
                        frameHeight: 1080,
                        recordingFPS: 120,
                        calibratedAt: Date(),
                        isManualPlacement: false
                    )
                ),
                bowlerGuideRect: StumpDetectionService.defaultBowlerGuideRect(),
                strikerGuideRect: StumpDetectionService.defaultStrikerGuideRect(),
                onManualTap: nil
            )
        }
        .previewDisplayName("Locked — corridor")
    }
}
#endif
