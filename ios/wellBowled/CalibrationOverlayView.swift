import SwiftUI

// MARK: - CalibrationOverlayView

/// Two dashed guide boxes for stump alignment. Nothing else.
struct CalibrationOverlayView: View {

    let mode: OverlayMode
    let calibrationState: StumpDetectionService.CalibrationState
    let bowlerGuideRect: CGRect   // normalized 0-1
    let strikerGuideRect: CGRect  // normalized 0-1
    let onManualTap: ((CGPoint) -> Void)?

    enum OverlayMode {
        case calibrating
        case active
        case hidden
    }

    var body: some View {
        switch mode {
        case .hidden, .active:
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
        }
    }

    private func dashedBox(rect: CGRect, in size: CGSize) -> some View {
        let frame = CGRect(
            x: rect.origin.x * size.width,
            y: rect.origin.y * size.height,
            width: rect.width * size.width,
            height: rect.height * size.height
        )
        return RoundedRectangle(cornerRadius: 4)
            .stroke(
                Color.white.opacity(0.6),
                style: StrokeStyle(lineWidth: 1.5, dash: [8, 6])
            )
            .frame(width: frame.width, height: frame.height)
            .position(x: frame.midX, y: frame.midY)
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
    }
}
#endif
