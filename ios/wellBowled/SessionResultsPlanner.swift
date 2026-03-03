import Foundation

struct SessionPhaseSuggestion: Equatable, Identifiable {
    let phaseName: String
    let timestamp: Double
    let score: Int

    var id: String {
        "\(phaseName.lowercased())-\(timestamp)"
    }
}

enum SessionResultsPlanner {
    static let telemetryMessages: [String] = [
        "Detecting run-up phase boundaries",
        "Measuring approach rhythm consistency",
        "Validating gather alignment",
        "Tracking back-foot contact stability",
        "Estimating trunk load transfer",
        "Segmenting delivery stride window",
        "Measuring front-arm pull timing",
        "Checking head stability through release",
        "Calculating release kinematics",
        "Reviewing wrist alignment at release",
        "Estimating seam-axis consistency",
        "Scanning follow-through deceleration",
        "Computing kinetic chain efficiency",
        "Tagging high-stress joint events",
        "Building phase-wise strengths",
        "Building phase-wise risk flags",
        "Generating corrective cues",
        "Compiling action signature vector",
        "Matching international bowler profiles",
        "Finalizing annotated coaching report"
    ]

    static func telemetryMessage(elapsedSeconds: Int) -> String {
        if elapsedSeconds >= 40 {
            return "Analyzing..."
        }
        let step = max(elapsedSeconds / 2, 0)
        return telemetryMessages[step % telemetryMessages.count]
    }

    static func topPhaseSuggestions(
        phases: [AnalysisPhase],
        expertAnalysis: ExpertAnalysis?,
        limit: Int = 3
    ) -> [SessionPhaseSuggestion] {
        guard !phases.isEmpty else { return [] }

        let scored = phases.map { phase -> SessionPhaseSuggestion in
            let feedback = matchedFeedback(for: phase, expertAnalysis: expertAnalysis)
            let injuryCount = feedback?.injuryRisk.count ?? 0
            let attentionCount = feedback?.slow.count ?? 0
            let goodCount = feedback?.good.count ?? 0
            let base = phase.isGood ? 1 : 5
            let score = base + (injuryCount * 5) + (attentionCount * 3) + goodCount
            return SessionPhaseSuggestion(
                phaseName: phase.name,
                timestamp: focusTimestamp(for: phase, expertAnalysis: expertAnalysis),
                score: score
            )
        }

        return scored
            .sorted {
                if $0.score != $1.score { return $0.score > $1.score }
                return $0.timestamp < $1.timestamp
            }
            .prefix(max(limit, 0))
            .map { $0 }
    }

    static func focusWindow(for timestamp: Double, clipDuration: Double) -> ClosedRange<Double> {
        let safeDuration = max(clipDuration, 0.5)
        let start = max(timestamp - 0.6, 0)
        let end = min(timestamp + 0.8, safeDuration)
        if end <= start {
            return start...(start + 0.4)
        }
        return start...end
    }

    static func focusTimestamp(for phase: AnalysisPhase, expertAnalysis: ExpertAnalysis?) -> Double {
        if let clipTs = phase.clipTimestamp {
            return max(clipTs, 0)
        }

        if let match = matchedPhase(for: phase, expertAnalysis: expertAnalysis) {
            return max((match.start + match.end) * 0.5, 0)
        }

        return 2.5
    }

    private static func matchedFeedback(
        for phase: AnalysisPhase,
        expertAnalysis: ExpertAnalysis?
    ) -> ExpertAnalysis.Phase.Feedback? {
        matchedPhase(for: phase, expertAnalysis: expertAnalysis)?.feedback
    }

    private static func matchedPhase(
        for phase: AnalysisPhase,
        expertAnalysis: ExpertAnalysis?
    ) -> ExpertAnalysis.Phase? {
        guard let expertAnalysis else { return nil }
        let normalizedPhaseName = normalized(phase.name)
        if let exact = expertAnalysis.phases.first(where: { normalized($0.phaseName) == normalizedPhaseName }) {
            return exact
        }
        return expertAnalysis.phases.first {
            normalized($0.phaseName).contains(normalizedPhaseName) ||
            normalizedPhaseName.contains(normalized($0.phaseName))
        }
    }

    private static func normalized(_ raw: String) -> String {
        raw.lowercased()
            .replacingOccurrences(of: "[^a-z0-9]", with: "", options: .regularExpression)
    }
}
