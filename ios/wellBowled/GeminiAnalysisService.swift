import Foundation
import os

private let log = Logger(subsystem: "com.wellbowled", category: "Analysis")

/// Analyzes delivery clips using Gemini generateContent REST API.
/// Implements DeliveryAnalyzing protocol for post-session analysis.
final class GeminiAnalysisService: DeliveryAnalyzing {

    // MARK: - Analysis Prompt

    private static let analysisPrompt = """
    You are analyzing a 5-second cricket bowling clip. The clip shows one bowling delivery.

    Analyze the delivery and respond with JSON only:
    {
      "pace_estimate": "medium pace",
      "length": "good_length",
      "line": "off",
      "type": "seam",
      "observation": "Good seam position at release, hitting a nice length",
      "confidence": 0.7
    }

    Field values:
    - pace_estimate: one of "quick", "medium pace", "slow", "spin"
    - length: one of "yorker", "full", "good_length", "short", "bouncer", "unknown"
    - line: one of "off", "middle", "leg", "wide", "unknown"
    - type: one of "seam", "spin", "unknown"
    - observation: one short sentence about the most notable aspect
    - confidence: 0.0-1.0 how confident you are in this assessment

    Be honest. If the camera angle or video quality makes assessment difficult, say so and lower confidence.
    """

    // MARK: - DNA Extraction Prompt

    private static let dnaExtractionPrompt = """
    You are analyzing a 5-second cricket bowling clip. Extract the bowler's action signature.

    Respond with JSON only matching this schema:
    {
      "run_up_stride": "short" | "medium" | "long",
      "run_up_speed": "slow" | "moderate" | "fast" | "explosive",
      "approach_angle": "straight" | "angled" | "wide",
      "gather_alignment": "front_on" | "semi" | "side_on",
      "back_foot_contact": "braced" | "sliding" | "jumping",
      "trunk_lean": "upright" | "slight" | "pronounced",
      "delivery_stride_length": "short" | "normal" | "over_striding",
      "front_arm_action": "pull" | "sweep" | "delayed",
      "head_stability": "stable" | "tilted" | "falling",
      "arm_path": "high" | "round_arm" | "sling",
      "release_height": "high" | "medium" | "low",
      "wrist_position": "behind" | "cocked" | "side_arm",
      "seam_orientation": "upright" | "scrambled" | "angled",
      "revolutions": "low" | "medium" | "high",
      "follow_through_direction": "across" | "straight" | "wide",
      "balance_at_finish": "balanced" | "falling" | "stumbling"
    }

    Use null for any field you cannot confidently determine from the video.
    Focus on what you can actually see. Be honest about limitations.
    """

    // MARK: - DNA Extraction

    /// Extracts BowlingDNA from a clip using Gemini vision + MediaPipe-derived wrist data.
    func extractBowlingDNA(
        clipURL: URL,
        wristOmega: Double?,
        releaseWristY: Double?
    ) async throws -> BowlingDNA {
        let videoData = try Data(contentsOf: clipURL)
        let base64Video = videoData.base64EncodedString()

        let payload: [String: Any] = [
            "contents": [[
                "parts": [
                    ["inlineData": ["mimeType": "video/mp4", "data": base64Video]],
                    ["text": Self.dnaExtractionPrompt]
                ]
            ]],
            "generationConfig": [
                "temperature": 0.2,
                "responseMimeType": "application/json"
            ]
        ]

        let url = WBConfig.generateContentURL(model: WBConfig.analysisModel)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        log.debug("Extracting BowlingDNA from: \(clipURL.lastPathComponent)")
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            log.error("DNA extraction API error: HTTP \(statusCode)")
            throw AnalysisError.apiError(statusCode)
        }

        var dna = try parseDNAResponse(data)

        // Fill in MediaPipe-derived fields
        if let omega = wristOmega {
            dna.wristOmegaNormalized = Self.normalizeOmega(omega)
        }
        if let y = releaseWristY {
            dna.releaseWristYNormalized = min(max(y, 0), 1)
        }

        return dna
    }

    /// Normalize wrist angular velocity: clamp((|omega| - 800) / 1200, 0, 1)
    static func normalizeOmega(_ omega: Double) -> Double {
        return min(max((abs(omega) - 800.0) / 1200.0, 0.0), 1.0)
    }

    private func parseDNAResponse(_ data: Data) throws -> BowlingDNA {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        guard let candidates = json?["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first(where: { $0["text"] != nil })?["text"] as? String else {
            throw AnalysisError.parseError
        }

        guard let textData = text.data(using: .utf8),
              let result = try JSONSerialization.jsonObject(with: textData) as? [String: Any] else {
            throw AnalysisError.parseError
        }

        log.debug("DNA result: \(text.prefix(200))")

        return BowlingDNA(
            runUpStride: (result["run_up_stride"] as? String).flatMap(RunUpStrideCategory.init),
            runUpSpeed: (result["run_up_speed"] as? String).flatMap(RunUpSpeed.init),
            approachAngle: (result["approach_angle"] as? String).flatMap(ApproachAngle.init),
            gatherAlignment: (result["gather_alignment"] as? String).flatMap(BodyAlignment.init),
            backFootContact: (result["back_foot_contact"] as? String).flatMap(BackFootContact.init),
            trunkLean: (result["trunk_lean"] as? String).flatMap(TrunkLean.init),
            deliveryStrideLength: (result["delivery_stride_length"] as? String).flatMap(StrideLength.init),
            frontArmAction: (result["front_arm_action"] as? String).flatMap(FrontArmAction.init),
            headStability: (result["head_stability"] as? String).flatMap(HeadStability.init),
            armPath: (result["arm_path"] as? String).flatMap(ArmPath.init),
            releaseHeight: (result["release_height"] as? String).flatMap(ReleaseHeight.init),
            wristPosition: (result["wrist_position"] as? String).flatMap(WristPosition.init),
            seamOrientation: (result["seam_orientation"] as? String).flatMap(SeamOrientation.init),
            revolutions: (result["revolutions"] as? String).flatMap(Revolutions.init),
            followThroughDirection: (result["follow_through_direction"] as? String).flatMap(FollowThroughDir.init),
            balanceAtFinish: (result["balance_at_finish"] as? String).flatMap(BalanceAtFinish.init)
        )
    }

    // MARK: - DeliveryAnalyzing

    func analyzeDelivery(clipURL: URL) async throws -> DeliveryAnalysis {
        let videoData = try Data(contentsOf: clipURL)
        let base64Video = videoData.base64EncodedString()

        let payload: [String: Any] = [
            "contents": [[
                "parts": [
                    ["inlineData": ["mimeType": "video/mp4", "data": base64Video]],
                    ["text": Self.analysisPrompt]
                ]
            ]],
            "generationConfig": [
                "temperature": WBConfig.analysisTemperature,
                "responseMimeType": "application/json"
            ]
        ]

        let url = WBConfig.generateContentURL(model: WBConfig.analysisModel)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        log.debug("Analyzing clip: \(clipURL.lastPathComponent) (\(videoData.count / 1024)KB)")
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            log.error("Analysis API error: HTTP \(statusCode)")
            throw AnalysisError.apiError(statusCode)
        }

        return try parseAnalysisResponse(data)
    }

    func evaluateChallenge(clipURL: URL, target: String) async throws -> ChallengeResult {
        let videoData = try Data(contentsOf: clipURL)
        let base64Video = videoData.base64EncodedString()

        let prompt = """
        You are evaluating a cricket bowling delivery against a target.

        TARGET: "\(target)"

        Did the bowler achieve the target? Respond with JSON:
        {
          "matches_target": true,
          "confidence": 0.7,
          "explanation": "Good yorker on off stump, right on target",
          "detected_length": "yorker",
          "detected_line": "off"
        }
        """

        let payload: [String: Any] = [
            "contents": [[
                "parts": [
                    ["inlineData": ["mimeType": "video/mp4", "data": base64Video]],
                    ["text": prompt]
                ]
            ]],
            "generationConfig": [
                "temperature": WBConfig.analysisTemperature,
                "responseMimeType": "application/json"
            ]
        ]

        let url = WBConfig.generateContentURL(model: WBConfig.analysisModel)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, _) = try await URLSession.shared.data(for: request)
        return try parseChallengeResponse(data)
    }

    func generateSessionSummary(deliveries: [Delivery]) async throws -> SessionSummary {
        // Build summary from local data (no API call needed)
        let dominant = PaceBand.medium // simplified
        return SessionSummary(
            totalDeliveries: deliveries.count,
            durationMinutes: 0,
            dominantPace: dominant,
            paceDistribution: [dominant: deliveries.count],
            keyObservation: "Session complete with \(deliveries.count) deliveries",
            challengeScore: nil
        )
    }

    // MARK: - Response Parsing

    private func parseAnalysisResponse(_ data: Data) throws -> DeliveryAnalysis {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        guard let candidates = json?["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first(where: { $0["text"] != nil })?["text"] as? String else {
            throw AnalysisError.parseError
        }

        guard let textData = text.data(using: .utf8),
              let result = try JSONSerialization.jsonObject(with: textData) as? [String: Any] else {
            throw AnalysisError.parseError
        }

        log.debug("Analysis result: \(text.prefix(100))")

        return DeliveryAnalysis(
            paceEstimate: result["pace_estimate"] as? String ?? "unknown",
            length: DeliveryLength(rawValue: result["length"] as? String ?? "unknown") ?? .unknown,
            line: DeliveryLine(rawValue: result["line"] as? String ?? "unknown") ?? .unknown,
            type: DeliveryType(rawValue: result["type"] as? String ?? "unknown") ?? .unknown,
            observation: result["observation"] as? String ?? "",
            confidence: result["confidence"] as? Double ?? 0.5
        )
    }

    private func parseChallengeResponse(_ data: Data) throws -> ChallengeResult {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        guard let candidates = json?["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first(where: { $0["text"] != nil })?["text"] as? String else {
            throw AnalysisError.parseError
        }

        guard let textData = text.data(using: .utf8),
              let result = try JSONSerialization.jsonObject(with: textData) as? [String: Any] else {
            throw AnalysisError.parseError
        }

        return ChallengeResult(
            matchesTarget: result["matches_target"] as? Bool ?? false,
            confidence: result["confidence"] as? Double ?? 0.5,
            explanation: result["explanation"] as? String ?? "",
            detectedLength: DeliveryLength(rawValue: result["detected_length"] as? String ?? ""),
            detectedLine: DeliveryLine(rawValue: result["detected_line"] as? String ?? "")
        )
    }
}

enum AnalysisError: LocalizedError {
    case apiError(Int)
    case parseError

    var errorDescription: String? {
        switch self {
        case .apiError(let code): return "Gemini API error (HTTP \(code))"
        case .parseError: return "Failed to parse analysis response"
        }
    }
}
