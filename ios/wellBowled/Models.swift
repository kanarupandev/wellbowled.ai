import Foundation
import CoreTransferable
import UniformTypeIdentifiers
import UIKit
import SwiftUI
import os

nonisolated(unsafe) private let modelsLog = Logger(subsystem: "com.wellbowled", category: "Models")

struct MovieFile: Transferable {
    let url: URL
    
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let startTime = CACurrentMediaTime()
            modelsLog.debug("Movie import initiated: \(received.file.lastPathComponent, privacy: .public)")
            
            let fileName = "upload_\(UUID().uuidString).mov"
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let destinationURL = documents.appendingPathComponent(fileName)
            
            do {
                // Strategic Move: Much faster than Copy on the same volume
                // PhotoPicker usually provides a temporary file we can 'claim'
                try FileManager.default.moveItem(at: received.file, to: destinationURL)
                let elapsed = CACurrentMediaTime() - startTime
                modelsLog.debug("Movie import complete via move. Elapsed=\(elapsed, privacy: .public)s")
                return Self(url: destinationURL)
            } catch {
                modelsLog.debug("Movie import move failed. Retrying copy. Error=\(error.localizedDescription, privacy: .public)")
                try? FileManager.default.copyItem(at: received.file, to: destinationURL)
                let elapsed = CACurrentMediaTime() - startTime
                modelsLog.debug("Movie import complete via copy fallback. Elapsed=\(elapsed, privacy: .public)s")
                return Self(url: destinationURL)
            }
        }
    }
}

enum DeliveryStatus: String, Codable {
    case detecting = "LOCAL VISION SCAN"  // Native On-Device Vision
    case clipping = "TRIMMING CLIP"        // Local trimming of the 5s action
    case queued = "QUEUED FOR AI"         // Waiting in the prefetcher queue
    case uploading = "AI SYNC"            // Sending to Gemini
    case processing = "REASONING (AI)"    // Gemini scanning the frames
    case analyzing = "TECHNICAL AUDIT"     // AI calculating speed/form
    case success = "QUALIFIED"
    case failed = "REJECTED"
}

struct Delivery: Identifiable, Equatable, Codable {
    let id: UUID
    let timestamp: Double
    var report: String?
    var speed: String?
    var tips: [String]
    var phases: [AnalysisPhase]? // Detailed phase breakdown from Expert
    var releaseTimestamp: Double?
    var status: DeliveryStatus
    var videoURL: URL?
    var thumbnail: UIImage?
    var sequence: Int

    // Cloud/Analysis Handshakes
    var videoID: String?
    var cloudVideoURL: URL?
    var cloudThumbnailURL: URL?
    var overlayVideoURL: URL? // MediaPipe biomechanics overlay (cloud)
    var localOverlayPath: String? // Filename in Documents/overlays/ (persisted)
    var landmarksURL: URL? // Backend-generated pose landmarks JSON (signed GCS URL)
    var isFavorite: Bool
    var localThumbnailPath: String? // Filename in Documents/thumbnails/
    var localVideoPath: String?     // Filename in Documents/

    // BowlingDNA — populated by MediaPipe + Gemini post-session
    var wristOmega: Double?         // Angular velocity at release (rad/s)
    var releaseWristY: Double?      // Normalized wrist Y at spike frame (0=top, 1=bottom)
    var dna: BowlingDNA?
    var dnaMatches: [BowlingDNAMatch]?

    enum CodingKeys: String, CodingKey {
        case id, timestamp, report, speed, tips, phases, releaseTimestamp, status, videoURL, sequence, videoID, cloudVideoURL, cloudThumbnailURL, overlayVideoURL, localOverlayPath, landmarksURL, isFavorite, localThumbnailPath, localVideoPath
        case wristOmega, releaseWristY, dna, dnaMatches
    }
    
    init(id: UUID = UUID(),
         timestamp: Double,
         report: String? = nil,
         speed: String? = nil,
         tips: [String] = [],
         phases: [AnalysisPhase]? = nil,
         releaseTimestamp: Double? = nil,
         status: DeliveryStatus = .detecting,
         videoURL: URL? = nil,
         thumbnail: UIImage? = nil,
         sequence: Int,
         videoID: String? = nil,
         cloudVideoURL: URL? = nil,
         cloudThumbnailURL: URL? = nil,
         overlayVideoURL: URL? = nil,
         localOverlayPath: String? = nil,
         landmarksURL: URL? = nil,
         isFavorite: Bool = false,
         localThumbnailPath: String? = nil,
         localVideoPath: String? = nil,
         wristOmega: Double? = nil,
         releaseWristY: Double? = nil,
         dna: BowlingDNA? = nil,
         dnaMatches: [BowlingDNAMatch]? = nil) {
        self.id = id
        self.timestamp = timestamp
        self.report = report
        self.speed = speed
        self.tips = tips
        self.phases = phases
        self.releaseTimestamp = releaseTimestamp
        self.status = status
        self.videoURL = videoURL
        self.thumbnail = thumbnail
        self.sequence = sequence
        self.videoID = videoID
        self.cloudVideoURL = cloudVideoURL
        self.cloudThumbnailURL = cloudThumbnailURL
        self.overlayVideoURL = overlayVideoURL
        self.localOverlayPath = localOverlayPath
        self.landmarksURL = landmarksURL
        self.isFavorite = isFavorite
        self.localThumbnailPath = localThumbnailPath
        self.localVideoPath = localVideoPath
        self.wristOmega = wristOmega
        self.releaseWristY = releaseWristY
        self.dna = dna
        self.dnaMatches = dnaMatches
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        timestamp = try container.decode(Double.self, forKey: .timestamp)
        report = try container.decodeIfPresent(String.self, forKey: .report)
        speed = try container.decodeIfPresent(String.self, forKey: .speed)
        tips = try container.decode([String].self, forKey: .tips)
        phases = try container.decodeIfPresent([AnalysisPhase].self, forKey: .phases)
        releaseTimestamp = try container.decodeIfPresent(Double.self, forKey: .releaseTimestamp)
        status = try container.decode(DeliveryStatus.self, forKey: .status)
        videoURL = try container.decodeIfPresent(URL.self, forKey: .videoURL)
        sequence = try container.decode(Int.self, forKey: .sequence)
        videoID = try container.decodeIfPresent(String.self, forKey: .videoID)
        cloudVideoURL = try container.decodeIfPresent(URL.self, forKey: .cloudVideoURL)
        cloudThumbnailURL = try container.decodeIfPresent(URL.self, forKey: .cloudThumbnailURL)
        overlayVideoURL = try container.decodeIfPresent(URL.self, forKey: .overlayVideoURL)
        localOverlayPath = try container.decodeIfPresent(String.self, forKey: .localOverlayPath)
        landmarksURL = try container.decodeIfPresent(URL.self, forKey: .landmarksURL)
        isFavorite = try container.decode(Bool.self, forKey: .isFavorite)
        localThumbnailPath = try container.decodeIfPresent(String.self, forKey: .localThumbnailPath)
        localVideoPath = try container.decodeIfPresent(String.self, forKey: .localVideoPath)
        wristOmega = try container.decodeIfPresent(Double.self, forKey: .wristOmega)
        releaseWristY = try container.decodeIfPresent(Double.self, forKey: .releaseWristY)
        dna = try container.decodeIfPresent(BowlingDNA.self, forKey: .dna)
        dnaMatches = try container.decodeIfPresent([BowlingDNAMatch].self, forKey: .dnaMatches)
        thumbnail = nil // UIImage must be loaded from Disk via localThumbnailPath
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(report, forKey: .report)
        try container.encode(speed, forKey: .speed)
        try container.encode(tips, forKey: .tips)
        try container.encode(phases, forKey: .phases)
        try container.encode(releaseTimestamp, forKey: .releaseTimestamp)
        try container.encode(status, forKey: .status)
        try container.encode(videoURL, forKey: .videoURL)
        try container.encode(sequence, forKey: .sequence)
        try container.encode(videoID, forKey: .videoID)
        try container.encode(cloudVideoURL, forKey: .cloudVideoURL)
        try container.encode(cloudThumbnailURL, forKey: .cloudThumbnailURL)
        try container.encode(overlayVideoURL, forKey: .overlayVideoURL)
        try container.encode(localOverlayPath, forKey: .localOverlayPath)
        try container.encode(landmarksURL, forKey: .landmarksURL)
        try container.encode(isFavorite, forKey: .isFavorite)
        try container.encode(localThumbnailPath, forKey: .localThumbnailPath)
        try container.encode(localVideoPath, forKey: .localVideoPath)
        try container.encodeIfPresent(wristOmega, forKey: .wristOmega)
        try container.encodeIfPresent(releaseWristY, forKey: .releaseWristY)
        try container.encodeIfPresent(dna, forKey: .dna)
        try container.encodeIfPresent(dnaMatches, forKey: .dnaMatches)
    }
    
    static func == (lhs: Delivery, rhs: Delivery) -> Bool {
        return lhs.id == rhs.id &&
               lhs.status == rhs.status &&
               lhs.videoURL == rhs.videoURL &&
               lhs.timestamp == rhs.timestamp &&
               lhs.releaseTimestamp == rhs.releaseTimestamp &&
               lhs.report == rhs.report &&
               lhs.speed == rhs.speed &&
               lhs.tips == rhs.tips &&
               lhs.phases == rhs.phases &&
               lhs.isFavorite == rhs.isFavorite &&
               lhs.sequence == rhs.sequence &&
               lhs.localOverlayPath == rhs.localOverlayPath &&
               lhs.wristOmega == rhs.wristOmega &&
               lhs.releaseWristY == rhs.releaseWristY &&
               lhs.dna == rhs.dna
    }
}

struct StreamingEvent: Identifiable {
    let id = UUID()
    let timestamp = Date()
    let message: String
    let type: String // info, process, error
}

// MARK: - Backend Landmarks JSON Models (for real-time skeleton overlay)

struct LandmarksData: Codable {
    let fps: Double
    let w: Int
    let h: Int
    let connections: [[Int]]
    let frames: [FrameLandmarks]
}

struct FrameLandmarks: Codable {
    let t: Double       // timestamp in seconds
    let p: String       // phase name
    let l: [BackendLandmark]
}

struct BackendLandmark: Codable {
    let i: Int          // MediaPipe landmark index
    let n: String       // joint name e.g. "RIGHT_SHOULDER"
    let x: Double       // normalized x (0-1)
    let y: Double       // normalized y (0-1)
    let v: Double       // visibility (0-1)
    let f: String?      // feedback: "good" | "slow" | "injury_risk" | nil
}

extension LandmarksData {
    /// Convert backend compact JSON into the FramePoseLandmarks format used by SkeletonSyncController.
    func toFramePoseLandmarks() -> [FramePoseLandmarks] {
        return frames.enumerated().map { idx, frame in
            let landmarks = frame.l.map { bl in
                PoseLandmark(
                    name: bl.n,
                    index: bl.i,
                    x: Float(bl.x),
                    y: Float(bl.y),
                    z: 0.0,
                    visibility: Float(bl.v)
                )
            }
            return FramePoseLandmarks(frameNumber: idx, timestamp: frame.t, landmarks: landmarks)
        }
    }

    /// Builds phase-wise joint feedback directly from backend landmark labels.
    /// This is the source of truth for overlay colors when Gemini labels joints.
    func toExpertAnalysisFromGeminiFeedback() -> ExpertAnalysis? {
        struct FeedbackBucket {
            var start: Double
            var end: Double
            var good = Set<String>()
            var slow = Set<String>()
            var injury = Set<String>()
        }

        var buckets: [String: FeedbackBucket] = [:]

        for frame in frames {
            let phaseName = frame.p.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "delivery_phase"
                : frame.p.trimmingCharacters(in: .whitespacesAndNewlines)
            var bucket = buckets[phaseName] ?? FeedbackBucket(start: frame.t, end: frame.t)
            bucket.start = min(bucket.start, frame.t)
            bucket.end = max(bucket.end, frame.t)

            for landmark in frame.l {
                guard let label = landmark.f?.lowercased() else { continue }
                switch label {
                case "good":
                    bucket.good.insert(landmark.n)
                case "slow", "attention", "attension", "needs_work":
                    bucket.slow.insert(landmark.n)
                case "injury_risk", "injury risk", "injury-risk", "risk":
                    bucket.injury.insert(landmark.n)
                default:
                    continue
                }
            }

            buckets[phaseName] = bucket
        }

        let mapped = buckets.compactMap { phaseName, bucket -> ExpertAnalysis.Phase? in
            guard !bucket.good.isEmpty || !bucket.slow.isEmpty || !bucket.injury.isEmpty else {
                return nil
            }
            return ExpertAnalysis.Phase(
                phaseName: phaseName,
                start: bucket.start,
                end: max(bucket.end, bucket.start + 0.001),
                feedback: ExpertAnalysis.Phase.Feedback(
                    good: Array(bucket.good).sorted(),
                    slow: Array(bucket.slow).sorted(),
                    injuryRisk: Array(bucket.injury).sorted()
                )
            )
        }
        .sorted(by: { $0.start < $1.start })

        return mapped.isEmpty ? nil : ExpertAnalysis(phases: mapped)
    }
}

// MARK: - Analysis Phase (from Expert response)
struct AnalysisPhase: Identifiable, Codable, Equatable {
    let id: UUID
    let name: String
    let status: String // "GOOD" or "NEEDS WORK"
    let observation: String
    let tip: String
    let clipTimestamp: Double? // Timestamp in clip where this phase is visible

    var isGood: Bool { status.uppercased().contains("GOOD") }

    enum CodingKeys: String, CodingKey {
        case name, status, observation, tip
        case clipTimestamp = "clip_ts"
    }

    init(id: UUID = UUID(), name: String, status: String, observation: String = "", tip: String = "", clipTimestamp: Double? = nil) {
        self.id = id
        self.name = name
        self.status = status
        self.observation = observation
        self.tip = tip
        self.clipTimestamp = clipTimestamp
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = UUID()
        self.name = try container.decode(String.self, forKey: .name)
        self.status = try container.decode(String.self, forKey: .status)
        self.observation = try container.decodeIfPresent(String.self, forKey: .observation) ?? ""
        self.tip = try container.decodeIfPresent(String.self, forKey: .tip) ?? ""
        self.clipTimestamp = try container.decodeIfPresent(Double.self, forKey: .clipTimestamp)
    }
}

// MARK: - Pose Detection Models

struct PoseLandmark: Codable {
    let name: String
    let index: Int
    let x: Float
    let y: Float
    let z: Float
    let visibility: Float
}

// MARK: - Expert Analysis Models

struct ExpertAnalysis: Codable {
    struct Phase: Codable {
        let phaseName: String
        let start: Double
        let end: Double
        let feedback: Feedback

        struct Feedback: Codable {
            let good: [String]
            let slow: [String]
            let injuryRisk: [String]

            enum CodingKeys: String, CodingKey {
                case good
                case slow
                case injuryRisk = "injury_risk"
            }
        }
    }

    let phases: [Phase]
}

// MARK: - Expert Analysis Mapper

class ExpertAnalysisMapper {
    /// 9 key biomechanical dots: head, shoulders, hips, knees, ankles
    static let keyJoints: Set<String> = [
        "NOSE",
        "LEFT_SHOULDER", "RIGHT_SHOULDER",
        "LEFT_HIP", "RIGHT_HIP",
        "LEFT_KNEE", "RIGHT_KNEE",
        "LEFT_ANKLE", "RIGHT_ANKLE"
    ]

    // Brand colors for biomechanical feedback
    static let goodColor = Color(red: 0.125, green: 0.788, blue: 0.592)       // #20C997
    static let attentionColor = Color(red: 0.957, green: 0.635, blue: 0.380)   // #F4A261
    static let injuryRiskColor = Color(red: 0.902, green: 0.224, blue: 0.275)  // #E63946

    static func getJointColor(jointName: String, expertAnalysis: ExpertAnalysis?, timestamp: Double) -> String {
        guard let analysis = expertAnalysis else {
            return "white"
        }

        // Find which phase we're in
        guard let currentPhase = analysis.phases.first(where: { phase in
            timestamp >= phase.start && timestamp <= phase.end
        }) else {
            return "white"
        }

        // Check joint feedback — NOSE maps to head-related feedback
        let lookupName = jointName == "NOSE" ? "HEAD" : jointName
        let allNames = [lookupName, jointName] // Check both variants

        for name in allNames {
            if currentPhase.feedback.injuryRisk.contains(name) {
                return "red"
            }
        }
        for name in allNames {
            if currentPhase.feedback.slow.contains(name) {
                return "yellow"
            }
        }
        for name in allNames {
            if currentPhase.feedback.good.contains(name) {
                return "green"
            }
        }

        return "white"
    }

    static func getColor(for landmarkName: String, timestamp: Double, expertAnalysis: ExpertAnalysis?) -> Color {
        let colorString = getJointColor(jointName: landmarkName, expertAnalysis: expertAnalysis, timestamp: timestamp)
        switch colorString {
        case "red":
            return injuryRiskColor
        case "yellow":
            return attentionColor
        case "green":
            return goodColor
        default:
            return .white
        }
    }
}

// MARK: - Skeleton Renderer

struct SkeletonRenderer {
    struct RenderConfig {
        let jointRadius: CGFloat
        let lineWidth: CGFloat
        let minVisibility: Float
        let visibilityThreshold: Float
        let lineOpacity: Double

        init(jointRadius: CGFloat = 1.75, lineWidth: CGFloat = 1.0, minVisibility: Float = 0.5, visibilityThreshold: Float = 0.5, lineOpacity: Double = 0.7) {
            self.jointRadius = jointRadius
            self.lineWidth = lineWidth
            self.minVisibility = minVisibility
            self.visibilityThreshold = visibilityThreshold
            self.lineOpacity = lineOpacity
        }
    }

    static let connections: [[Int]] = [
        // Torso
        [11, 12],  // LEFT_SHOULDER → RIGHT_SHOULDER
        [11, 23],  // LEFT_SHOULDER → LEFT_HIP
        [12, 24],  // RIGHT_SHOULDER → RIGHT_HIP
        [23, 24],  // LEFT_HIP → RIGHT_HIP

        // Left arm
        [11, 13],  // LEFT_SHOULDER → LEFT_ELBOW
        [13, 15],  // LEFT_ELBOW → LEFT_WRIST

        // Right arm
        [12, 14],  // RIGHT_SHOULDER → RIGHT_ELBOW
        [14, 16],  // RIGHT_ELBOW → RIGHT_WRIST

        // Left leg
        [23, 25],  // LEFT_HIP → LEFT_KNEE
        [25, 27],  // LEFT_KNEE → LEFT_ANKLE

        // Right leg
        [24, 26],  // RIGHT_HIP → RIGHT_KNEE
        [26, 28]   // RIGHT_KNEE → RIGHT_ANKLE
    ]

    /// Key joint indices for dot rendering (6 joints only):
    /// LEFT_SHOULDER(11), RIGHT_SHOULDER(12), LEFT_WRIST(15), RIGHT_WRIST(16), LEFT_KNEE(25), RIGHT_KNEE(26)
    /// 9 key biomechanical dots: nose(0), shoulders(11,12), hips(23,24), knees(25,26), ankles(27,28)
    static let keyJointIndices: Set<Int> = [0, 11, 12, 23, 24, 25, 26, 27, 28]

    static func filterVisible(_ landmarks: [PoseLandmark], threshold: Float) -> [PoseLandmark] {
        return landmarks.filter { $0.visibility >= threshold }
    }

    static func filterKeyJoints(_ landmarks: [PoseLandmark], threshold: Float) -> [PoseLandmark] {
        return landmarks.filter { $0.visibility >= threshold && keyJointIndices.contains($0.index) }
    }

    static func toScreenCoordinates(_ landmark: PoseLandmark, size: CGSize) -> CGPoint {
        return CGPoint(
            x: CGFloat(landmark.x) * size.width,
            y: CGFloat(landmark.y) * size.height
        )
    }

    /// Map normalized landmark coordinates into the aspect-fit video rect within the container.
    static func toScreenCoordinates(_ landmark: PoseLandmark, containerSize: CGSize, videoAspectRatio: CGFloat) -> CGPoint {
        let containerAR = containerSize.width / containerSize.height
        let displayRect: CGRect
        if videoAspectRatio > containerAR {
            // Video wider than container — pillarboxed (black bars top/bottom)
            let displayWidth = containerSize.width
            let displayHeight = displayWidth / videoAspectRatio
            let yOffset = (containerSize.height - displayHeight) / 2
            displayRect = CGRect(x: 0, y: yOffset, width: displayWidth, height: displayHeight)
        } else {
            // Video taller than container — letterboxed (black bars left/right)
            let displayHeight = containerSize.height
            let displayWidth = displayHeight * videoAspectRatio
            let xOffset = (containerSize.width - displayWidth) / 2
            displayRect = CGRect(x: xOffset, y: 0, width: displayWidth, height: displayHeight)
        }
        return CGPoint(
            x: displayRect.origin.x + CGFloat(landmark.x) * displayRect.width,
            y: displayRect.origin.y + CGFloat(landmark.y) * displayRect.height
        )
    }
}
