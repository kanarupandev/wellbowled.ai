import SwiftUI
import AVKit

private let peacockBlue = Color(red: 0, green: 0.427, blue: 0.467)
private let darkBg = Color(hex: "0D1117")

// MARK: - ClipCompareView

/// Side-by-side comparison of two analyzed delivery clips.
/// Pinned dual video at top (with speed + date overlay on each).
/// Scrollable delta table below — rows sorted by diff magnitude, red intensity = diff size.
struct ClipCompareView: View {

    let clipA: Delivery
    let clipB: Delivery
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            // Pinned dual video
            dualVideoSection
                .frame(height: 260)

            // Scrollable delta table
            deltaTable
        }
        .background(darkBg.ignoresSafeArea())
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button("Close") { dismiss() }
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundColor(peacockBlue)

            Spacer()

            Text("COMPARE")
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .tracking(2)
                .foregroundColor(.white.opacity(0.5))

            Spacer()

            // Balance spacer
            Text("Close").font(.system(size: 14)).opacity(0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Dual Video

    private var dualVideoSection: some View {
        HStack(spacing: 2) {
            clipVideoTile(clipA, label: "A")
            clipVideoTile(clipB, label: "B")
        }
        .padding(.horizontal, 2)
    }

    private func clipVideoTile(_ clip: Delivery, label: String) -> some View {
        ZStack(alignment: .bottomLeading) {
            // Thumbnail or placeholder
            if let thumb = loadThumbnail(clip) {
                Image(uiImage: thumb)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipped()
            } else {
                Rectangle()
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        Text(label)
                            .font(.system(size: 40, weight: .black, design: .monospaced))
                            .foregroundColor(.white.opacity(0.1))
                    )
            }

            // Overlay: speed + date
            VStack(alignment: .leading, spacing: 4) {
                // Speed badge
                if let kph = clip.speedKph {
                    Text("\(Int(kph)) kph")
                        .font(.system(size: 18, weight: .black, design: .monospaced))
                        .foregroundColor(.white)
                        .shadow(color: .black, radius: 4)
                }

                // Date + time
                Text(formatDate(clip.timestamp))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.8))
                    .shadow(color: .black, radius: 3)
            }
            .padding(8)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Delta Table

    private var deltaTable: some View {
        let rows = computeDiffRows()

        return ScrollView(.vertical, showsIndicators: false) {
            if rows.isEmpty {
                VStack(spacing: 12) {
                    Text("No DNA data to compare")
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4))
                    Text("Run deep analysis on both clips first")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.white.opacity(0.25))
                }
                .padding(.top, 40)
            } else {
                // Column headers
                HStack {
                    Text("Parameter")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("A")
                        .frame(width: 72, alignment: .center)
                    Text("B")
                        .frame(width: 72, alignment: .center)
                }
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.35))
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 4)

                LazyVStack(spacing: 0) {
                    ForEach(rows) { row in
                        diffRow(row)
                    }
                }
                .padding(.bottom, 40)
            }
        }
    }

    private func diffRow(_ row: DNADiffCalculator.DiffRow) -> some View {
        HStack {
            Text(row.label)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.85))
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(row.valueA)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .frame(width: 72, alignment: .center)

            Text(row.valueB)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .frame(width: 72, alignment: .center)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(diffBackground(row.diffMagnitude))
    }

    /// Red intensity proportional to diff magnitude.
    /// 0.0 = transparent (white row), 1.0 = darkest red.
    private func diffBackground(_ magnitude: Double) -> Color {
        guard magnitude > 0.001 else { return Color.clear }
        // Scale: 0.0→transparent, 1.0→deep red
        // Use non-linear curve so small diffs are subtle
        let intensity = pow(magnitude, 0.7)
        return Color(red: 0.9, green: 0.15, blue: 0.15).opacity(intensity * 0.35)
    }

    // MARK: - Data

    private func computeDiffRows() -> [DNADiffCalculator.DiffRow] {
        guard let dnaA = clipA.dna, let dnaB = clipB.dna else { return [] }
        return DNADiffCalculator.diff(a: dnaA, b: dnaB)
    }

    // MARK: - Helpers

    private func loadThumbnail(_ clip: Delivery) -> UIImage? {
        if let thumb = clip.thumbnail { return thumb }
        guard let path = clip.localThumbnailPath else { return nil }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let url = docs.appendingPathComponent("thumbnails").appendingPathComponent(path)
        return UIImage(contentsOfFile: url.path)
    }

    private func formatDate(_ timestamp: Double) -> String {
        let date = Date(timeIntervalSince1970: timestamp)
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d, HH:mm"
        return fmt.string(from: date)
    }
}

// MARK: - Preview

#if DEBUG
struct ClipCompareView_Previews: PreviewProvider {
    static var previews: some View {
        let dnaA = BowlingDNA(
            runUpStride: .long, runUpSpeed: .fast, approachAngle: .straight,
            gatherAlignment: .sideOn, backFootContact: .braced, trunkLean: .slight,
            deliveryStrideLength: .normal, frontArmAction: .pull, headStability: .stable,
            armPath: .high, releaseHeight: .high, wristPosition: .behind,
            seamOrientation: .upright, revolutions: .medium,
            followThroughDirection: .straight, balanceAtFinish: .balanced,
            runUpQuality: 0.7, gatherQuality: 0.6, deliveryStrideQuality: 0.5,
            releaseQuality: 0.8, followThroughQuality: 0.6
        )
        let dnaB = BowlingDNA(
            runUpStride: .medium, runUpSpeed: .moderate, approachAngle: .angled,
            gatherAlignment: .semi, backFootContact: .sliding, trunkLean: .pronounced,
            deliveryStrideLength: .overStriding, frontArmAction: .sweep, headStability: .falling,
            armPath: .roundArm, releaseHeight: .medium, wristPosition: .cocked,
            seamOrientation: .scrambled, revolutions: .high,
            followThroughDirection: .across, balanceAtFinish: .falling,
            runUpQuality: 0.4, gatherQuality: 0.5, deliveryStrideQuality: 0.3,
            releaseQuality: 0.5, followThroughQuality: 0.4
        )

        let clipA = Delivery(timestamp: Date().timeIntervalSince1970 - 86400, sequence: 1, speedKph: 127, dna: dnaA)
        let clipB = Delivery(timestamp: Date().timeIntervalSince1970, sequence: 2, speedKph: 112, dna: dnaB)

        ClipCompareView(clipA: clipA, clipB: clipB)
    }
}
#endif
