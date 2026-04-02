import SwiftUI

// MARK: - Speed Category

enum SpeedCategory: String {
    case express = "Express"
    case fast = "Fast"
    case fastMedium = "Fast-Medium"
    case medium = "Medium"
    case mediumSlow = "Medium-Slow"
    case slow = "Slow"

    var color: Color {
        switch self {
        case .express: return .red
        case .fast: return .orange
        case .fastMedium: return .yellow
        case .medium: return .green
        case .mediumSlow: return .cyan
        case .slow: return .blue
        }
    }

    static func from(kmh: Double) -> SpeedCategory {
        switch kmh {
        case 145...: return .express
        case 135..<145: return .fast
        case 125..<135: return .fastMedium
        case 115..<125: return .medium
        case 100..<115: return .mediumSlow
        default: return .slow
        }
    }
}

// MARK: - Delivery

struct Delivery: Identifiable {
    let id = UUID()
    let videoURL: URL
    let fps: Double
    let duration: Double
    let totalFrames: Int
    var releaseFrame: Int?
    var arrivalFrame: Int?

    // Pitch distance: stump-to-stump = 20.12m
    static let pitchMeters: Double = 20.12

    var speedKMH: Double? {
        guard let r = releaseFrame, let a = arrivalFrame, a > r else { return nil }
        let seconds = Double(a - r) / fps
        return (Self.pitchMeters / seconds) * 3.6
    }

    var speedMPH: Double? {
        guard let kmh = speedKMH else { return nil }
        return kmh / 1.609
    }

    var category: SpeedCategory? {
        guard let kmh = speedKMH else { return nil }
        return .from(kmh: kmh)
    }

    var frameDiff: Int? {
        guard let r = releaseFrame, let a = arrivalFrame else { return nil }
        return a - r
    }
}
