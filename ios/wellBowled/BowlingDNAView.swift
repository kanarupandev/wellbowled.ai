import SwiftUI

private let peacockBlue = Color(red: 0, green: 0.427, blue: 0.467)
private let greyBlue = Color(red: 0.55, green: 0.66, blue: 0.77)

// MARK: - DNA Section for SessionResultsView

struct BowlingDNASection: View {
    let matches: [BowlingDNAMatch]

    var body: some View {
        Section("Action Signature") {
            ForEach(matches) { match in
                BowlingDNAMatchCard(match: match)
            }
        }
    }
}

// MARK: - Match Card

struct BowlingDNAMatchCard: View {
    let match: BowlingDNAMatch

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header: name + similarity ring
            HStack(spacing: 12) {
                // Similarity ring
                ZStack {
                    Circle()
                        .stroke(greyBlue.opacity(0.2), lineWidth: 4)
                        .frame(width: 48, height: 48)
                    Circle()
                        .trim(from: 0, to: match.similarityPercent / 100)
                        .stroke(peacockBlue, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .frame(width: 48, height: 48)
                        .rotationEffect(.degrees(-90))
                    Text("\(Int(match.similarityPercent))%")
                        .font(.caption2.bold().monospacedDigit())
                        .foregroundColor(peacockBlue)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(match.bowlerName)
                        .font(.headline)
                    HStack(spacing: 6) {
                        Text(match.country)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(match.era)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Text(match.style)
                        .font(.caption2)
                        .foregroundColor(greyBlue)
                }

                Spacer()
            }

            // Phase match info
            HStack(spacing: 16) {
                Label(match.closestPhase, systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundColor(peacockBlue)
                Label(match.biggestDifference, systemImage: "arrow.left.arrow.right")
                    .font(.caption)
                    .foregroundColor(.orange)
            }

            // Signature traits
            VStack(alignment: .leading, spacing: 3) {
                ForEach(match.signatureTraits, id: \.self) { trait in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "cricket.ball")
                            .font(.system(size: 8))
                            .foregroundColor(greyBlue)
                            .padding(.top, 3)
                        Text(trait)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
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
