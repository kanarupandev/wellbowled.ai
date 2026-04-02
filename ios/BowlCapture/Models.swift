import SwiftUI
import CoreMedia

// MARK: - Arrival Point

enum ArrivalPoint: String, CaseIterable, Identifiable {
    case stumps = "Stumps"
    case poppingCrease = "Popping Crease"

    var id: String { rawValue }

    var distanceMeters: Double {
        switch self {
        case .stumps: return 20.12       // 22 yards stump-to-stump
        case .poppingCrease: return 17.68 // 58 feet crease-to-crease
        }
    }

    var label: String {
        switch self {
        case .stumps: return "Stumps (20.12m / 66ft)"
        case .poppingCrease: return "Popping Crease (17.68m / 58ft)"
        }
    }
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

// MARK: - Speed Measurement

struct SpeedMeasurement: Identifiable {
    let id = UUID()
    let releaseFrame: Int
    let arrivalFrame: Int
    let fps: Double
    let arrivalPoint: ArrivalPoint
    let measuredAt: Date = Date()

    var frameDiff: Int { arrivalFrame - releaseFrame }
    var timeSeconds: Double { Double(frameDiff) / fps }
    var speedMS: Double { arrivalPoint.distanceMeters / timeSeconds }
    var speedKMH: Double { speedMS * 3.6 }
    var speedMPH: Double { speedMS * 2.237 }
    var category: SpeedCategory { .from(kmh: speedKMH) }
}

// MARK: - Delivery Phase

enum DeliveryPhase: String, CaseIterable, Identifiable {
    case runUp = "Run-up"
    case gather = "Gather"
    case bound = "Bound"
    case release = "Release"
    case followThrough = "Follow"

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .runUp: return .blue
        case .gather: return .purple
        case .bound: return .orange
        case .release: return .red
        case .followThrough: return .green
        }
    }
}

// MARK: - Phase Annotation

struct PhaseAnnotation: Identifiable {
    let id = UUID()
    let phase: DeliveryPhase
    let point: CGPoint       // normalized 0-1
    let frameIndex: Int
}

// MARK: - Distance Measurement

struct DistanceMeasurement: Identifiable {
    let id = UUID()
    let point1: CGPoint      // normalized 0-1
    let point2: CGPoint      // normalized 0-1
    let frameIndex: Int
}

// MARK: - Delivery

struct Delivery: Identifiable {
    let id = UUID()
    let videoURL: URL
    let fps: Double
    let duration: Double
    let totalFrames: Int
    var speed: SpeedMeasurement?
    var annotations: [PhaseAnnotation] = []
    var measurements: [DistanceMeasurement] = []
}

// MARK: - Session

class BowlSession: ObservableObject {
    @Published var arrivalPoint: ArrivalPoint = .stumps
    @Published var rememberForSession: Bool = true
    @Published var deliveries: [Delivery] = []

    // Reference calibration (two tapped points = known distance)
    @Published var referenceDistanceFeet: Double = 58.0
    @Published var referencePoint1: CGPoint?
    @Published var referencePoint2: CGPoint?
    @Published var isCalibrated: Bool = false

    var speeds: [SpeedMeasurement] {
        deliveries.compactMap { $0.speed }
    }

    var averageKMH: Double? {
        let s = speeds
        guard !s.isEmpty else { return nil }
        return s.map(\.speedKMH).reduce(0, +) / Double(s.count)
    }

    var topKMH: Double? {
        speeds.map(\.speedKMH).max()
    }

    /// Convert pixel distance between two normalized points to feet using calibration
    func distanceFeet(from p1: CGPoint, to p2: CGPoint) -> Double? {
        guard isCalibrated, let r1 = referencePoint1, let r2 = referencePoint2 else { return nil }
        let refPixelDist = hypot(r2.x - r1.x, r2.y - r1.y)
        guard refPixelDist > 0.001 else { return nil }
        let measuredPixelDist = hypot(p2.x - p1.x, p2.y - p1.y)
        return (measuredPixelDist / refPixelDist) * referenceDistanceFeet
    }
}
