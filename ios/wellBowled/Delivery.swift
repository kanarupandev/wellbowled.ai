import Foundation

// MARK: - Delivery Analysis (from Gemini generateContent)
// Note: primary Delivery struct lives in Models.swift

struct DeliveryAnalysis: Codable, Equatable {
    let paceEstimate: String        // "95-100 kph"
    let length: DeliveryLength
    let line: DeliveryLine
    let type: DeliveryType
    let observation: String         // "Nice seam position at release"
    let confidence: Double
}

// MARK: - Session Summary (from Gemini)

struct SessionSummary: Codable, Equatable {
    let totalDeliveries: Int
    let durationMinutes: Double
    let dominantPace: PaceBand
    let paceDistribution: [PaceBand: Int]
    let keyObservation: String
    let challengeScore: String?     // "4/6 yorkers landed (67%)"
}
