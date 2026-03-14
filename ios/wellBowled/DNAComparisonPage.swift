import SwiftUI

private let peacockBlue = Color(red: 0, green: 0.427, blue: 0.467)

// MARK: - Full-Page DNA Comparison

struct DNAComparisonPage: View {
    let userDNA: BowlingDNA
    let match: BowlingDNAMatch

    private var ringColor: Color {
        if match.similarityPercent >= 70 { return Color(hex: "34C759") }
        if match.similarityPercent >= 45 { return peacockBlue }
        return Color(hex: "FF8A3D")
    }

    private func countryFlag(_ code: String) -> String {
        switch code {
        case "AUS": return "🇦🇺"
        case "PAK": return "🇵🇰"
        case "IND": return "🇮🇳"
        case "ENG": return "🇬🇧"
        case "SL":  return "🇱🇰"
        case "SA":  return "🇿🇦"
        case "WI":  return "🏴‍☠️"
        default:    return "🏏"
        }
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                heroSection
                    .padding(.bottom, 24)

                phaseComparisons
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)

                traitsSection
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
            }
        }
        .background(Color(hex: "0D1117"))
    }

    // MARK: - Hero

    private var heroSection: some View {
        VStack(spacing: 16) {
            Text("YOUR ACTION ARCHETYPE")
                .font(.system(size: 10, weight: .heavy))
                .tracking(2.5)
                .foregroundColor(peacockBlue.opacity(0.7))
                .padding(.top, 20)

            // Similarity ring — big and central
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 6)
                    .frame(width: 100, height: 100)
                Circle()
                    .trim(from: 0, to: CGFloat(match.similarityPercent / 100.0))
                    .stroke(ringColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .frame(width: 100, height: 100)
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(Int(match.similarityPercent))")
                        .font(.system(size: 36, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                    Text("% MATCH")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1)
                        .foregroundColor(.white.opacity(0.5))
                }
            }

            // Bowler name
            Text(match.bowlerName)
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.white)

            Text("\(countryFlag(match.country)) \(match.country) · \(match.era) · \(match.style)")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.5))

            // Legend
            HStack(spacing: 20) {
                legendDot(color: peacockBlue, label: "You")
                legendDot(color: ringColor, label: match.bowlerName.components(separatedBy: " ").last ?? "Pro")
            }
            .padding(.top, 8)
        }
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
        }
    }

    // MARK: - Phase Comparisons

    private var phaseComparisons: some View {
        VStack(spacing: 16) {
            phaseGroup("RUN-UP", rows: [
                ("Stride", userDNA.runUpStride?.rawValue, match.bowlerDNA.runUpStride?.rawValue),
                ("Speed", userDNA.runUpSpeed?.rawValue, match.bowlerDNA.runUpSpeed?.rawValue),
                ("Approach", userDNA.approachAngle?.rawValue, match.bowlerDNA.approachAngle?.rawValue),
            ])

            phaseGroup("GATHER", rows: [
                ("Alignment", userDNA.gatherAlignment?.rawValue, match.bowlerDNA.gatherAlignment?.rawValue),
                ("Back foot", userDNA.backFootContact?.rawValue, match.bowlerDNA.backFootContact?.rawValue),
                ("Trunk lean", userDNA.trunkLean?.rawValue, match.bowlerDNA.trunkLean?.rawValue),
            ])

            phaseGroup("DELIVERY STRIDE", rows: [
                ("Stride length", userDNA.deliveryStrideLength?.rawValue, match.bowlerDNA.deliveryStrideLength?.rawValue),
                ("Front arm", userDNA.frontArmAction?.rawValue, match.bowlerDNA.frontArmAction?.rawValue),
                ("Head stability", userDNA.headStability?.rawValue, match.bowlerDNA.headStability?.rawValue),
            ])

            phaseGroup("RELEASE  ×2", rows: [
                ("Arm path", userDNA.armPath?.rawValue, match.bowlerDNA.armPath?.rawValue),
                ("Release height", userDNA.releaseHeight?.rawValue, match.bowlerDNA.releaseHeight?.rawValue),
                ("Wrist position", userDNA.wristPosition?.rawValue, match.bowlerDNA.wristPosition?.rawValue),
                ("Wrist speed", formatContinuous(userDNA.wristOmegaNormalized), formatContinuous(match.bowlerDNA.wristOmegaNormalized)),
                ("Release height Y", formatContinuous(userDNA.releaseWristYNormalized), formatContinuous(match.bowlerDNA.releaseWristYNormalized)),
            ])

            phaseGroup("SEAM / SPIN", rows: [
                ("Seam orientation", userDNA.seamOrientation?.rawValue, match.bowlerDNA.seamOrientation?.rawValue),
                ("Revolutions", userDNA.revolutions?.rawValue, match.bowlerDNA.revolutions?.rawValue),
            ])

            phaseGroup("FOLLOW-THROUGH", rows: [
                ("Direction", userDNA.followThroughDirection?.rawValue, match.bowlerDNA.followThroughDirection?.rawValue),
                ("Balance", userDNA.balanceAtFinish?.rawValue, match.bowlerDNA.balanceAtFinish?.rawValue),
            ])
        }
    }

    private func phaseGroup(_ title: String, rows: [(String, String?, String?)]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Phase header
            Text(title)
                .font(.system(size: 10, weight: .heavy))
                .tracking(1.5)
                .foregroundColor(peacockBlue.opacity(0.8))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

            // Column headers
            HStack {
                Text("Parameter")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("You")
                    .frame(width: 80, alignment: .center)
                Text("Pro")
                    .frame(width: 80, alignment: .center)
            }
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(.white.opacity(0.35))
            .padding(.horizontal, 14)
            .padding(.bottom, 6)

            // Rows
            ForEach(Array(rows.enumerated()), id: \.offset) { idx, row in
                comparisonRow(
                    label: row.0,
                    userValue: row.1,
                    proValue: row.2,
                    isEven: idx % 2 == 0
                )
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func comparisonRow(label: String, userValue: String?, proValue: String?, isEven: Bool) -> some View {
        let bothPresent = userValue != nil && proValue != nil
        let isMatch = bothPresent && userValue == proValue
        let isMismatch = bothPresent && userValue != proValue

        return HStack {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(displayValue(userValue))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(isMatch ? Color(hex: "34C759") : (isMismatch ? Color(hex: "FF6B6B") : peacockBlue))
                .frame(width: 80, alignment: .center)

            Text(displayValue(proValue))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(isMatch ? Color(hex: "34C759") : (isMismatch ? Color(hex: "FF6B6B") : ringColor))
                .frame(width: 80, alignment: .center)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            isMatch
                ? Color(hex: "34C759").opacity(0.10)
                : (isMismatch ? Color(hex: "FF6B6B").opacity(0.06) : (isEven ? Color.clear : Color.white.opacity(0.02)))
        )
    }

    private func displayValue(_ value: String?) -> String {
        guard let v = value else { return "—" }
        return v.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private func formatContinuous(_ value: Double?) -> String? {
        guard let v = value else { return nil }
        return String(format: "%.0f%%", v * 100)
    }

    // MARK: - Signature Traits

    private var traitsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(match.bowlerName.uppercased()) — SIGNATURE")
                .font(.system(size: 10, weight: .heavy))
                .tracking(1.5)
                .foregroundColor(ringColor.opacity(0.8))

            ForEach(match.signatureTraits, id: \.self) { trait in
                HStack(alignment: .top, spacing: 10) {
                    Circle()
                        .fill(ringColor.opacity(0.5))
                        .frame(width: 5, height: 5)
                        .padding(.top, 6)
                    Text(trait)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(ringColor.opacity(0.2), lineWidth: 1)
        )
    }
}
