import Foundation

// MARK: - Session

/// Value type so @Published on SessionViewModel propagates all changes to SwiftUI.
struct Session {
    var deliveries: [Delivery] = []
    var isActive: Bool = false
    var startedAt: Date?
    var endedAt: Date?

    // Mode
    var mode: SessionMode = .freePlay

    // Challenge state
    var currentChallenge: String?
    var challengeHits: Int = 0
    var challengeTotal: Int = 0

    // Summary (populated post-session)
    var summary: SessionSummary?

    // Computed
    var deliveryCount: Int { deliveries.count }
    var lastDelivery: Delivery? { deliveries.last }
    var duration: TimeInterval {
        guard let start = startedAt else { return 0 }
        let end = endedAt ?? Date()
        return end.timeIntervalSince(start)
    }
    var challengeScoreText: String {
        guard challengeTotal > 0 else { return "" }
        let pct = Int(Double(challengeHits) / Double(challengeTotal) * 100)
        return "\(challengeHits)/\(challengeTotal) (\(pct)%)"
    }

    mutating func start(mode: SessionMode = .freePlay) {
        self.deliveries = []
        self.isActive = true
        self.startedAt = Date()
        self.endedAt = nil
        self.mode = mode
        self.currentChallenge = nil
        self.challengeHits = 0
        self.challengeTotal = 0
        self.summary = nil
    }

    mutating func end() {
        self.isActive = false
        self.endedAt = Date()
    }

    mutating func addDelivery(_ delivery: Delivery) {
        deliveries.append(delivery)
    }

    mutating func recordChallengeResult(hit: Bool) {
        challengeTotal += 1
        if hit { challengeHits += 1 }
    }
}
