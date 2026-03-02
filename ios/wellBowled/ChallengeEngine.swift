import Foundation

/// Generates rotating challenge targets and formats challenge outcomes.
struct ChallengeEngine {
    private(set) var targets: [String]
    private(set) var cursor: Int = 0

    private static let fallbackTargets: [String] = [
        "Yorker on off stump",
        "Good length on middle stump"
    ]

    init(targets: [String], shuffle: Bool = true) {
        let base = targets.isEmpty ? Self.fallbackTargets : targets
        self.targets = base
        if shuffle, self.targets.count > 1 {
            self.targets.shuffle()
        }
    }

    mutating func reset(shuffle: Bool = true) {
        cursor = 0
        if shuffle, targets.count > 1 {
            targets.shuffle()
        }
    }

    mutating func nextTarget() -> String {
        guard !targets.isEmpty else {
            return Self.fallbackTargets[0]
        }
        let target = targets[cursor % targets.count]
        cursor += 1
        return target
    }

    static func formatResult(target: String, result: ChallengeResult) -> String {
        let status = result.matchesTarget ? "HIT" : "MISS"
        return "Challenge [\(target)] \(status): \(result.explanation)"
    }
}
