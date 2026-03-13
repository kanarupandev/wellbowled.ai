import Foundation

struct DeliveryDeepAnalysisResult: Codable {
    let paceEstimate: String
    let summary: String
    let phases: [AnalysisPhase]
    let expertAnalysis: ExpertAnalysis?
}

struct ChipGuidanceResponse: Codable, Equatable {
    let reply: String
    let action: String
    let phaseName: String?
    let focusStart: Double?
    let focusEnd: Double?
    let playbackRate: Double?

    enum CodingKeys: String, CodingKey {
        case reply
        case action
        case phaseName = "phase_name"
        case focusStart = "focus_start"
        case focusEnd = "focus_end"
        case playbackRate = "playback_rate"
    }
}

struct DeliveryDeepAnalysisStatus: Equatable {
    enum Stage: Equatable {
        case idle
        case running
        case ready
        case failed
    }

    var stage: Stage = .idle
    var elapsedSeconds: Int = 0
    var statusMessage: String = ""
    var failureMessage: String?
}

struct DeliveryDeepAnalysisArtifacts {
    var poseFrames: [FramePoseLandmarks] = []
    var poseFailureReason: String?
    var expertAnalysis: ExpertAnalysis?
    var chipReply: String?
}
