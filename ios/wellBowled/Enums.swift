import Foundation

// MARK: - Pace Band (from wrist angular velocity)

enum PaceBand: String, Codable, CaseIterable {
    case quick   // omega > 1500 deg/s
    case medium  // 800-1500 deg/s
    case slow    // < 800 deg/s

    var label: String {
        switch self {
        case .quick:  return "Quick"
        case .medium: return "Medium pace"
        case .slow:   return "Slow"
        }
    }

    static func from(angularVelocity omega: Double) -> PaceBand {
        let abs = abs(omega)
        if abs > 1500 { return .quick }
        if abs > 800  { return .medium }
        return .slow
    }
}

// MARK: - Session Mode

enum SessionMode: String, Codable {
    case freePlay
    case challenge

    var finePrintLabel: String {
        switch self {
        case .freePlay:
            return "Mode: Free"
        case .challenge:
            return "Mode: Challenge"
        }
    }

    static func fromToolArgument(_ raw: String) -> SessionMode? {
        switch raw.lowercased() {
        case "free", "freeplay", "free_play":
            return .freePlay
        case "challenge":
            return .challenge
        default:
            return nil
        }
    }
}

// MARK: - Bowling Arm

enum BowlingArm: String, Codable {
    case right
    case left
    case unknown
}

// MARK: - Delivery Type (from Gemini analysis)

enum DeliveryType: String, Codable {
    case seam
    case spin
    case unknown
}

// MARK: - Length Classification

enum DeliveryLength: String, Codable {
    case yorker
    case full
    case goodLength = "good_length"
    case short
    case bouncer
    case unknown
}

// MARK: - Line Classification

enum DeliveryLine: String, Codable {
    case offStump = "off"
    case middle
    case legStump = "leg"
    case wide
    case unknown
}

// MARK: - Challenge Result

struct ChallengeResult: Codable {
    let matchesTarget: Bool
    let confidence: Double
    let explanation: String
    let detectedLength: DeliveryLength?
    let detectedLine: DeliveryLine?
}
