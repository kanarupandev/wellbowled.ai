import SwiftUI

// MARK: - Colors

private let peacockBlue = Color(red: 0, green: 0.427, blue: 0.467)
private let confirmedGreen = Color(red: 0.125, green: 0.788, blue: 0.592)

// MARK: - CalibrationOverlayView

/// TV broadcast-style ball-tracking corridor overlay connecting two sets of stumps.
/// Renders a HawkEye-inspired perspective corridor between bowler and striker end
/// guide boxes, driven by the current calibration state.
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

    // MARK: - Animation State

    @State private var detectingPulse = false
    @State private var corridorOpacity: Double = 0
    @State private var lockedScale: CGFloat = 1.0

    // MARK: - Derived

    private var isLocked: Bool {
        if case .locked = calibrationState { return true }
        return false
    }

    private var isDetecting: Bool {
        if case .detecting = calibrationState { return true }
        return false
    }

    private var isFailed: Bool {
        if case .failed = calibrationState { return true }
        return false
    }

    // MARK: - Body

    var body: some View {
        switch mode {
        case .hidden:
            EmptyView()

        case .calibrating:
            calibratingOverlay

        case .active:
            activeOverlay
        }
    }

    // MARK: - Calibrating Overlay

    private var calibratingOverlay: some View {
        GeometryReader { geo in
            let size = geo.size

            ZStack {
                // Perspective corridor
                corridorShape(in: size)

                // Pitch center line
                pitchCenterLine(in: size)

                // Guide boxes
                guideBox(rect: bowlerGuideRect, in: size, label: "Bowler End")
                guideBox(rect: strikerGuideRect, in: size, label: "Striker End")

                // Stump markers when locked
                if isLocked {
                    stumpMarkers(rect: bowlerGuideRect, in: size)
                    stumpMarkers(rect: strikerGuideRect, in: size)
                }

                // Status pill
                VStack {
                    Spacer()
                    statusPill
                        .padding(.bottom, 40)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                if isFailed {
                    let normalized = CGPoint(
                        x: location.x / size.width,
                        y: location.y / size.height
                    )
                    onManualTap?(normalized)
                }
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                detectingPulse = true
            }
        }
        .onChange(of: isLocked) { locked in
            if locked {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                    lockedScale = 1.08
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        lockedScale = 1.0
                    }
                }
            }
        }
    }

    // MARK: - Active Overlay (subtle corridor only)

    private var activeOverlay: some View {
        GeometryReader { geo in
            let size = geo.size

            ZStack {
                // Subtle corridor
                CorridorShape(
                    bowlerRect: bowlerGuideRect,
                    strikerRect: strikerGuideRect,
                    viewSize: size
                )
                .fill(
                    LinearGradient(
                        colors: [
                            peacockBlue.opacity(0.05),
                            peacockBlue.opacity(0.10)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .opacity(corridorOpacity)

                // Thin corridor edges
                CorridorShape(
                    bowlerRect: bowlerGuideRect,
                    strikerRect: strikerGuideRect,
                    viewSize: size
                )
                .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                .opacity(corridorOpacity)
            }
        }
        .onAppear {
            withAnimation(.easeIn(duration: 0.8)) {
                corridorOpacity = 1.0
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Corridor Shape

    private func corridorShape(in size: CGSize) -> some View {
        ZStack {
            // Fill
            CorridorShape(
                bowlerRect: bowlerGuideRect,
                strikerRect: strikerGuideRect,
                viewSize: size
            )
            .fill(
                LinearGradient(
                    colors: [
                        peacockBlue.opacity(0.08),
                        peacockBlue.opacity(0.15)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .shadow(color: peacockBlue.opacity(0.3), radius: 12, x: 0, y: 0)

            // Border
            CorridorShape(
                bowlerRect: bowlerGuideRect,
                strikerRect: strikerGuideRect,
                viewSize: size
            )
            .stroke(Color.white.opacity(0.3), lineWidth: 1)
        }
    }

    // MARK: - Guide Box

    private func guideBox(rect: CGRect, in size: CGSize, label: String) -> some View {
        let frame = denormalize(rect, in: size)
        let borderColor: Color = isLocked ? confirmedGreen : Color.white.opacity(0.5)
        let dashPattern: [CGFloat] = isLocked ? [] : [8, 6]
        let pulseOpacity: Double = isDetecting ? (detectingPulse ? 1.0 : 0.5) : 1.0

        return ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.clear)

            RoundedRectangle(cornerRadius: 6)
                .stroke(
                    borderColor,
                    style: StrokeStyle(
                        lineWidth: isLocked ? 2.0 : 1.5,
                        dash: dashPattern
                    )
                )

            // Label
            VStack {
                Text(label.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(isLocked ? confirmedGreen : Color.white.opacity(0.5))
                    .padding(.top, 4)
                Spacer()
            }
        }
        .frame(width: frame.width, height: frame.height)
        .position(x: frame.midX, y: frame.midY)
        .opacity(pulseOpacity)
        .scaleEffect(isLocked ? lockedScale : 1.0)
    }

    // MARK: - Stump Markers

    /// Three thin vertical lines representing the three stumps inside a guide box.
    private func stumpMarkers(rect: CGRect, in size: CGSize) -> some View {
        let frame = denormalize(rect, in: size)
        let stumpSpacing = frame.width * 0.15
        let stumpHeight = frame.height * 0.6

        return HStack(spacing: stumpSpacing) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 1)
                    .fill(confirmedGreen)
                    .frame(width: 1.5, height: stumpHeight)
            }
        }
        .position(x: frame.midX, y: frame.midY + frame.height * 0.05)
        .transition(.opacity.combined(with: .scale(scale: 0.8)))
    }

    // MARK: - Pitch Center Line

    /// Dashed center line running down the corridor (good length visual reference).
    private func pitchCenterLine(in size: CGSize) -> some View {
        let bowlerMidX = bowlerGuideRect.midX * size.width
        let bowlerMidY = bowlerGuideRect.midY * size.height
        let strikerMidX = strikerGuideRect.midX * size.width
        let strikerMidY = strikerGuideRect.midY * size.height

        return Path { path in
            path.move(to: CGPoint(x: bowlerMidX, y: bowlerMidY))
            path.addLine(to: CGPoint(x: strikerMidX, y: strikerMidY))
        }
        .stroke(
            Color.white.opacity(0.15),
            style: StrokeStyle(lineWidth: 1, dash: [6, 8])
        )
    }

    // MARK: - Status Pill

    private var statusPill: some View {
        let text: String
        let pillColor: Color
        let textColor: Color

        switch calibrationState {
        case .idle, .detecting:
            text = "Align stumps in boxes"
            pillColor = Color.white.opacity(0.12)
            textColor = Color.white.opacity(0.8)

        case .locked:
            text = "Locked -- Speed tracking active"
            pillColor = confirmedGreen.opacity(0.2)
            textColor = confirmedGreen

        case .failed:
            text = "Tap stumps manually"
            pillColor = DesignSystem.Colors.warning.opacity(0.2)
            textColor = DesignSystem.Colors.warning
        }

        return Text(text)
            .font(.system(size: 12, weight: .semibold, design: .monospaced))
            .foregroundColor(textColor)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(pillColor)
                    .overlay(
                        Capsule()
                            .stroke(textColor.opacity(0.3), lineWidth: 0.5)
                    )
            )
    }

    // MARK: - Helpers

    /// Convert a normalized (0-1) rect to view coordinates.
    private func denormalize(_ rect: CGRect, in size: CGSize) -> CGRect {
        CGRect(
            x: rect.origin.x * size.width,
            y: rect.origin.y * size.height,
            width: rect.width * size.width,
            height: rect.height * size.height
        )
    }
}

// MARK: - CorridorShape

/// Custom trapezoid connecting the bowler-end guide box (narrower, top) to the
/// striker-end guide box (wider, bottom), simulating perspective down the pitch.
struct CorridorShape: Shape {
    let bowlerRect: CGRect
    let strikerRect: CGRect
    let viewSize: CGSize

    func path(in rect: CGRect) -> Path {
        let topLeft = CGPoint(
            x: bowlerRect.minX * viewSize.width,
            y: bowlerRect.midY * viewSize.height
        )
        let topRight = CGPoint(
            x: bowlerRect.maxX * viewSize.width,
            y: bowlerRect.midY * viewSize.height
        )
        let bottomRight = CGPoint(
            x: strikerRect.maxX * viewSize.width,
            y: strikerRect.midY * viewSize.height
        )
        let bottomLeft = CGPoint(
            x: strikerRect.minX * viewSize.width,
            y: strikerRect.midY * viewSize.height
        )

        var path = Path()
        path.move(to: topLeft)
        path.addLine(to: topRight)
        path.addLine(to: bottomRight)
        path.addLine(to: bottomLeft)
        path.closeSubpath()
        return path
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
        .previewDisplayName("Detecting")

        ZStack {
            Color.black.ignoresSafeArea()

            CalibrationOverlayView(
                mode: .calibrating,
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
        .previewDisplayName("Locked")

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
        .previewDisplayName("Active (Subtle)")

        ZStack {
            Color.black.ignoresSafeArea()

            CalibrationOverlayView(
                mode: .calibrating,
                calibrationState: .failed("No stumps detected"),
                bowlerGuideRect: StumpDetectionService.defaultBowlerGuideRect(),
                strikerGuideRect: StumpDetectionService.defaultStrikerGuideRect(),
                onManualTap: { point in
                    print("Manual tap at: \(point)")
                }
            )
        }
        .previewDisplayName("Failed")
    }
}
#endif
