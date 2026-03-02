import Foundation

// MARK: - Expert Analysis Builder
// Converts [AnalysisPhase] from Expert response → ExpertAnalysis for skeleton color coding

enum ExpertAnalysisBuilder {

    // Bowling arm joints — highlighted when a phase NEEDS WORK
    static let bowlingArm = ["RIGHT_SHOULDER", "RIGHT_ELBOW", "RIGHT_WRIST"]

    /// Builds ExpertAnalysis from delivery phases.
    /// - GOOD phase → all key joints green
    /// - NEEDS WORK phase → bowling arm joints yellow
    /// Returns nil if no phases have a clipTimestamp.
    static func build(from analysisPhases: [AnalysisPhase]) -> ExpertAnalysis? {
        let sorted = analysisPhases
            .filter { $0.clipTimestamp != nil }
            .sorted { ($0.clipTimestamp ?? 0) < ($1.clipTimestamp ?? 0) }

        guard !sorted.isEmpty else { return nil }

        let allKeyJoints = Array(ExpertAnalysisMapper.keyJoints)

        let expertPhases: [ExpertAnalysis.Phase] = sorted.enumerated().map { i, ap in
            let start = ap.clipTimestamp ?? 0.0
            let end = i + 1 < sorted.count
                ? (sorted[i + 1].clipTimestamp ?? start + 1.0)
                : start + 1.5

            let feedback = ExpertAnalysis.Phase.Feedback(
                good: ap.isGood ? allKeyJoints : [],
                slow: ap.isGood ? [] : bowlingArm,
                injuryRisk: []
            )

            return ExpertAnalysis.Phase(
                phaseName: ap.name,
                start: start,
                end: end,
                feedback: feedback
            )
        }

        return expertPhases.isEmpty ? nil : ExpertAnalysis(phases: expertPhases)
    }
}
