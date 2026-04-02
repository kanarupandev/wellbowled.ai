import SwiftUI
import AVFoundation

extension Double {
    var nonZero: Double? { self > 0 ? self : nil }
}

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

// MARK: - Speed Calculation (pure, testable)

enum SpeedCalc {
    /// Bowling crease to batting stumps (58 ft / 17.68m)
    static let defaultDistanceMeters: Double = 17.68

    static func kmh(releaseFrame: Int, arrivalFrame: Int, fps: Double, distanceMeters: Double) -> Double? {
        guard arrivalFrame > releaseFrame, fps > 0, distanceMeters > 0 else { return nil }
        let seconds = Double(arrivalFrame - releaseFrame) / fps
        return (distanceMeters / seconds) * 3.6
    }

    static func mph(kmh: Double) -> Double { kmh / 1.609 }

    static func clampedIndex(_ index: Int, total: Int) -> Int {
        max(0, min(index, total - 1))
    }

    static func timeSeconds(frame: Int, fps: Double) -> Double {
        Double(frame) / fps
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
    var distanceMeters: Double = SpeedCalc.defaultDistanceMeters

    var speedKMH: Double? {
        guard let r = releaseFrame, let a = arrivalFrame else { return nil }
        return SpeedCalc.kmh(releaseFrame: r, arrivalFrame: a, fps: fps, distanceMeters: distanceMeters)
    }

    var speedMPH: Double? {
        guard let kmh = speedKMH else { return nil }
        return SpeedCalc.mph(kmh: kmh)
    }

    var category: SpeedCategory? {
        guard let kmh = speedKMH else { return nil }
        return .from(kmh: kmh)
    }

    var frameDiff: Int? {
        guard let r = releaseFrame, let a = arrivalFrame else { return nil }
        return a - r
    }

    static func from(url: URL) async -> Delivery? {
        let asset = AVAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first else { return nil }
        let dur = (try? await asset.load(.duration))?.seconds ?? 0
        let fr = Double((try? await track.load(.nominalFrameRate)) ?? 120)
        let frames = Int(dur * fr)
        return Delivery(videoURL: url, fps: fr, duration: dur, totalFrames: frames)
    }
}
