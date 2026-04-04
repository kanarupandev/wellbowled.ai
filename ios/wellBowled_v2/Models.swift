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
    /// Default training distance used in the app, editable per clip.
    static let defaultDistanceMeters: Double = 18.90
    static let defaultGoalSpeedKMH: Double = 120.0

    static func kmh(releaseFrame: Int, arrivalFrame: Int, fps: Double, distanceMeters: Double) -> Double? {
        guard arrivalFrame > releaseFrame, fps > 0, distanceMeters > 0 else { return nil }
        let seconds = Double(arrivalFrame - releaseFrame) / fps
        return (distanceMeters / seconds) * 3.6
    }

    static func mph(kmh: Double) -> Double { kmh / 1.609 }

    static func kmhFrameVariance(releaseFrame: Int, arrivalFrame: Int, fps: Double, distanceMeters: Double) -> Double? {
        guard let selected = kmh(releaseFrame: releaseFrame, arrivalFrame: arrivalFrame, fps: fps, distanceMeters: distanceMeters) else {
            return nil
        }
        let previous = kmh(releaseFrame: releaseFrame, arrivalFrame: arrivalFrame - 1, fps: fps, distanceMeters: distanceMeters)
        let next = kmh(releaseFrame: releaseFrame, arrivalFrame: arrivalFrame + 1, fps: fps, distanceMeters: distanceMeters)
        return [previous, next]
            .compactMap { $0.map { abs($0 - selected) } }
            .max()
    }

    static func clampedIndex(_ index: Int, total: Int) -> Int {
        max(0, min(index, total - 1))
    }

    static func timeSeconds(frame: Int, fps: Double) -> Double {
        Double(frame) / fps
    }

    static func flightTimeSeconds(releaseFrame: Int, arrivalFrame: Int, fps: Double) -> Double? {
        guard arrivalFrame > releaseFrame, fps > 0 else { return nil }
        return Double(arrivalFrame - releaseFrame) / fps
    }

    static func formattedFlightTime(releaseFrame: Int, arrivalFrame: Int, fps: Double) -> String? {
        guard let seconds = flightTimeSeconds(releaseFrame: releaseFrame, arrivalFrame: arrivalFrame, fps: fps) else {
            return nil
        }
        return String(format: "%.2fs", seconds)
    }

    static func targetFlightTimeSeconds(goalSpeedKMH: Double, distanceMeters: Double) -> Double? {
        guard goalSpeedKMH > 0, distanceMeters > 0 else { return nil }
        return distanceMeters / (goalSpeedKMH / 3.6)
    }

    static func goalTimeDeltaSeconds(
        releaseFrame: Int,
        arrivalFrame: Int,
        fps: Double,
        distanceMeters: Double,
        goalSpeedKMH: Double
    ) -> Double? {
        guard let actual = flightTimeSeconds(releaseFrame: releaseFrame, arrivalFrame: arrivalFrame, fps: fps),
              let target = targetFlightTimeSeconds(goalSpeedKMH: goalSpeedKMH, distanceMeters: distanceMeters) else {
            return nil
        }
        return actual - target
    }
}

enum ReviewField: Equatable {
    case release
    case arrival
    case distance
}

struct ReviewDraft: Equatable {
    var releaseFrame: Int?
    var arrivalFrame: Int?
    var distanceMeters: Double
    private(set) var selectedField: ReviewField

    init(
        releaseFrame: Int? = nil,
        arrivalFrame: Int? = nil,
        distanceMeters: Double = SpeedCalc.defaultDistanceMeters,
        selectedField: ReviewField? = nil
    ) {
        self.releaseFrame = releaseFrame
        self.arrivalFrame = arrivalFrame
        self.distanceMeters = distanceMeters

        if let selectedField {
            self.selectedField = selectedField
        } else if releaseFrame == nil {
            self.selectedField = .release
        } else if arrivalFrame == nil {
            self.selectedField = .arrival
        } else {
            self.selectedField = .distance
        }
    }

    var activeField: ReviewField {
        switch selectedField {
        case .release:
            return .release
        case .arrival:
            return releaseFrame == nil ? .release : .arrival
        case .distance:
            if releaseFrame == nil { return .release }
            if arrivalFrame == nil { return .arrival }
            return .distance
        }
    }

    var isComplete: Bool {
        releaseFrame != nil && arrivalFrame != nil
    }

    mutating func select(_ field: ReviewField) {
        selectedField = field
    }

    @discardableResult
    mutating func setRelease(_ frame: Int) -> Bool {
        let invalidatedArrival = arrivalFrame.map { $0 <= frame } ?? false
        releaseFrame = frame
        if invalidatedArrival {
            arrivalFrame = nil
        }
        selectedField = arrivalFrame == nil ? .arrival : .release
        return invalidatedArrival
    }

    @discardableResult
    mutating func setArrival(_ frame: Int) -> Bool {
        guard let releaseFrame, frame > releaseFrame else {
            selectedField = .arrival
            return false
        }
        arrivalFrame = frame
        selectedField = .distance
        return true
    }

    mutating func clearRelease() {
        releaseFrame = nil
        arrivalFrame = nil
        selectedField = .release
    }

    mutating func clearArrival() {
        arrivalFrame = nil
        selectedField = .arrival
    }

    mutating func setDistance(_ meters: Double) {
        guard meters > 0 else { return }
        distanceMeters = meters
        selectedField = .distance
    }
}

struct DistanceInput: Equatable {
    private(set) var digits: String

    init(digits: String = "") {
        self.digits = String(digits.filter(\.isNumber).prefix(4))
    }

    var digitCount: Int { digits.count }

    var text: String {
        let padded = Self.paddedDigits(from: digits)
        return "\(padded.prefix(2)).\(padded.suffix(2))"
    }

    var value: Double {
        (Double(Self.paddedDigits(from: digits)) ?? 0) / 100
    }

    mutating func replace(with distanceMeters: Double) {
        digits = String(format: "%04d", max(0, min(Int((distanceMeters * 100).rounded()), 9999)))
    }

    @discardableResult
    mutating func append(_ digit: String) -> Bool {
        guard digit.count == 1, digit.first?.isNumber == true, digits.count < 4 else { return false }
        digits.append(digit)
        return true
    }

    mutating func backspace() {
        guard !digits.isEmpty else { return }
        digits.removeLast()
    }

    mutating func clear() {
        digits = ""
    }

    private static func paddedDigits(from digits: String) -> String {
        let sanitized = String(digits.filter(\.isNumber).prefix(4))
        return String(repeating: "0", count: max(0, 4 - sanitized.count)) + sanitized
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

    var flightTimeSeconds: Double? {
        guard let r = releaseFrame, let a = arrivalFrame else { return nil }
        return SpeedCalc.flightTimeSeconds(releaseFrame: r, arrivalFrame: a, fps: fps)
    }

    var formattedFlightTime: String? {
        guard let r = releaseFrame, let a = arrivalFrame else { return nil }
        return SpeedCalc.formattedFlightTime(releaseFrame: r, arrivalFrame: a, fps: fps)
    }

    var speedErrorKMH: Double? {
        guard let r = releaseFrame, let a = arrivalFrame else { return nil }
        return SpeedCalc.kmhFrameVariance(releaseFrame: r, arrivalFrame: a, fps: fps, distanceMeters: distanceMeters)
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
