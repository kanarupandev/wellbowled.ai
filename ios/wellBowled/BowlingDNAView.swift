import SwiftUI

private let peacockBlue = Color(red: 0, green: 0.427, blue: 0.467)

// MARK: - Quality Color (10 shades via saturation modulation)

/// Maps execution quality (0.1–1.0) to a 10-shade color gradient.
/// Low quality → desaturated grey-blue, high quality → vivid peacock blue / green.
func qualityColor(for quality: Double) -> Color {
    let clamped = min(max(quality, 0.1), 1.0)
    // Snap to nearest 0.1 for consistent rendering
    let step = (clamped * 10).rounded() / 10

    // Hue: blend from cool grey-blue (210°) to peacock teal (185°) to green (145°)
    // Saturation: 0.15 at low quality → 0.85 at high quality
    // Brightness: fairly stable, slight lift at top end
    let hue: Double
    let saturation = 0.15 + (step - 0.1) * (0.85 - 0.15) / 0.9
    let brightness = 0.55 + step * 0.25

    switch step {
    case ...0.3: hue = 210 / 360  // grey-blue
    case ...0.5: hue = 200 / 360  // steel blue
    case ...0.7: hue = 185 / 360  // teal (peacock territory)
    case ...0.9: hue = 165 / 360  // blue-green
    default:     hue = 145 / 360  // vivid green (elite)
    }

    return Color(hue: hue, saturation: saturation, brightness: brightness)
}

// MARK: - DNA Section for SessionResultsView

struct BowlingDNASection: View {
    let matches: [BowlingDNAMatch]

    var body: some View {
        if let match = matches.first {
            Section("Action Signature") {
                BowlingDNAMatchCard(match: match)
            }
        }
    }
}

// MARK: - Match Card

struct BowlingDNAMatchCard: View {
    let match: BowlingDNAMatch

    private var ringColor: Color {
        if match.similarityPercent >= 70 { return Color(hex: "34C759") }
        if match.similarityPercent >= 45 { return peacockBlue }
        return Color(hex: "FF8A3D")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header: name + similarity ring
            HStack(spacing: 14) {
                // Similarity ring
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.1), lineWidth: 5)
                        .frame(width: 56, height: 56)
                    Circle()
                        .trim(from: 0, to: match.similarityPercent / 100)
                        .stroke(ringColor, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .frame(width: 56, height: 56)
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text("\(Int(match.similarityPercent))")
                            .font(.system(size: 18, weight: .black, design: .rounded))
                            .foregroundColor(ringColor)
                        Text("%")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(ringColor.opacity(0.6))
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(match.bowlerName)
                        .font(.headline)
                    HStack(spacing: 6) {
                        Text(countryFlag(match.country))
                        Text(match.country)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(match.era)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Text(match.style)
                        .font(.caption2)
                        .foregroundColor(peacockBlue)
                }

                Spacer()
            }

            // Phase match info
            HStack(spacing: 16) {
                Label {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Closest")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.secondary)
                        Text(match.closestPhase)
                            .font(.caption.weight(.semibold))
                    }
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 12))
                }

                Label {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Work on")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.secondary)
                        Text(match.biggestDifference)
                            .font(.caption.weight(.semibold))
                    }
                } icon: {
                    Image(systemName: "arrow.left.arrow.right")
                        .foregroundColor(.orange)
                        .font(.system(size: 12))
                }
            }

            // Quality bar (if user DNA has quality data)
            if let avg = match.bowlerDNA.averageQuality {
                HStack(spacing: 4) {
                    Text("Quality")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)
                    qualityBar(quality: avg)
                    Text(String(format: "%.0f%%", avg * 100))
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(qualityColor(for: avg))
                }
            }

            // Signature traits
            VStack(alignment: .leading, spacing: 4) {
                ForEach(match.signatureTraits, id: \.self) { trait in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(peacockBlue.opacity(0.6))
                            .frame(width: 4, height: 4)
                            .padding(.top, 5)
                        Text(trait)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func qualityBar(quality: Double) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 6)
                RoundedRectangle(cornerRadius: 2)
                    .fill(qualityColor(for: quality))
                    .frame(width: geo.size.width * quality, height: 6)
            }
        }
        .frame(height: 6)
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
}

// MARK: - Standalone DNA Detail View

struct BowlingDNADetailView: View {
    let delivery: Delivery

    var body: some View {
        NavigationStack {
            Group {
                if let matches = delivery.dnaMatches, !matches.isEmpty {
                    List {
                        BowlingDNASection(matches: matches)
                    }
                } else {
                    ContentUnavailableView(
                        "No Action Signature",
                        systemImage: "figure.cricket",
                        description: Text("DNA analysis requires a successful delivery clip")
                    )
                }
            }
            .navigationTitle("Bowling DNA #\(delivery.sequence)")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
