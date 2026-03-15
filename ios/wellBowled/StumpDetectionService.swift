import CoreGraphics
import Foundation
import UIKit
import os

private let log = Logger(subsystem: "com.wellbowled", category: "StumpDetection")

/// Detects stump positions using Gemini vision (single-frame analysis).
/// Sends one camera frame to Gemini with a structured prompt asking for stump
/// bounding box centres. Only called once during calibration — latency is acceptable.
/// Falls back to manual tap if Gemini detection fails.
final class StumpDetectionService {

    // MARK: - Types

    /// Gemini-detected stump position.
    struct DetectionResult: Codable, Equatable {
        let normalizedCenter: CGPoint
        let confidence: Double
        let label: String  // "bowler_end" or "striker_end"
    }

    enum CalibrationState: Equatable {
        case idle
        case detecting
        case locked(StumpCalibration)
        case failed(String)
    }

    // MARK: - Gemini Prompt

    static let stumpDetectionPrompt = """
    You are analyzing a single camera frame from a cricket practice session.
    The camera is on a tripod, viewing down a cricket pitch with stumps at each end.

    Find BOTH sets of stumps in this image. Return STRICT JSON only:
    {
      "stumps": [
        {
          "label": "bowler_end",
          "center_x": 0.52,
          "center_y": 0.18,
          "confidence": 0.92
        },
        {
          "label": "striker_end",
          "center_x": 0.48,
          "center_y": 0.83,
          "confidence": 0.88
        }
      ]
    }

    Rules:
    - center_x and center_y are normalized (0.0 to 1.0) relative to image dimensions.
    - (0,0) is top-left, (1,1) is bottom-right.
    - "bowler_end" is the set of stumps closer to the bowler (typically further from camera / smaller in frame).
    - "striker_end" is the set closer to the batsman (typically nearer to camera / larger in frame).
    - confidence: 0.0-1.0 how certain you are this is actually cricket stumps.
    - If you can only find ONE set of stumps, return just that one.
    - If you cannot find any stumps, return { "stumps": [] }.
    - Do NOT guess. Only return positions you can actually see in the image.
    """

    // MARK: - State

    private(set) var state: CalibrationState = .idle

    // MARK: - Public

    /// Reset detection state for a new calibration attempt.
    func reset() {
        state = .idle
    }

    /// Detect stumps in a camera frame using Gemini vision.
    /// - Parameters:
    ///   - image: Camera snapshot (UIImage)
    ///   - frameWidth: Pixel width of the capture
    ///   - frameHeight: Pixel height of the capture
    ///   - fps: Recording FPS for the calibration
    /// - Returns: StumpCalibration if both sets detected, nil otherwise.
    func detectStumps(
        image: UIImage,
        frameWidth: Int,
        frameHeight: Int,
        fps: Int
    ) async throws -> StumpCalibration? {
        state = .detecting
        log.info("Sending frame to Gemini for stump detection (\(frameWidth)x\(frameHeight))")

        guard let jpegData = image.jpegData(compressionQuality: 0.8) else {
            state = .failed("Could not encode frame as JPEG")
            throw StumpDetectionError.imageEncodingFailed
        }

        let base64Image = jpegData.base64EncodedString()
        let detections = try await callGemini(base64Image: base64Image)

        guard let bowler = detections.first(where: { $0.label == "bowler_end" }),
              let striker = detections.first(where: { $0.label == "striker_end" }) else {
            let found = detections.map(\.label).joined(separator: ", ")
            let msg = detections.isEmpty ? "No stumps detected" : "Only found: \(found)"
            state = .failed(msg)
            log.warning("Stump detection incomplete: \(msg, privacy: .public)")
            return nil
        }

        let calibration = StumpCalibration(
            bowlerStumpCenter: bowler.normalizedCenter,
            strikerStumpCenter: striker.normalizedCenter,
            frameWidth: frameWidth,
            frameHeight: frameHeight,
            recordingFPS: fps,
            calibratedAt: Date(),
            isManualPlacement: false
        )

        guard calibration.isValid else {
            state = .failed("Detected positions too close together")
            return nil
        }

        state = .locked(calibration)
        log.info(
            "Stumps detected — bowler:(\(String(format: "%.3f", bowler.normalizedCenter.x))," +
            "\(String(format: "%.3f", bowler.normalizedCenter.y))) " +
            "striker:(\(String(format: "%.3f", striker.normalizedCenter.x))," +
            "\(String(format: "%.3f", striker.normalizedCenter.y))) " +
            "conf: \(String(format: "%.2f/%.2f", bowler.confidence, striker.confidence))"
        )
        return calibration
    }

    /// Create a calibration from manual tap positions (fallback when Gemini can't detect).
    func calibrateFromManualTaps(
        bowlerTap: CGPoint,
        strikerTap: CGPoint,
        frameWidth: Int,
        frameHeight: Int,
        fps: Int
    ) -> StumpCalibration? {
        let calibration = StumpCalibration(
            bowlerStumpCenter: bowlerTap,
            strikerStumpCenter: strikerTap,
            frameWidth: frameWidth,
            frameHeight: frameHeight,
            recordingFPS: fps,
            calibratedAt: Date(),
            isManualPlacement: true
        )
        guard calibration.isValid else { return nil }
        state = .locked(calibration)
        return calibration
    }

    // MARK: - Guide Box Defaults

    /// Default bowler-end guide box (top of frame in portrait).
    static func defaultBowlerGuideRect() -> CGRect {
        let w = Double(WBConfig.calibrationBoxWidthRatio)
        let h = Double(WBConfig.calibrationBoxHeightRatio)
        return CGRect(x: 0.5 - w / 2, y: 0.05, width: w, height: h)
    }

    /// Default striker-end guide box (bottom of frame in portrait).
    static func defaultStrikerGuideRect() -> CGRect {
        let w = Double(WBConfig.calibrationBoxWidthRatio)
        let h = Double(WBConfig.calibrationBoxHeightRatio)
        return CGRect(x: 0.5 - w / 2, y: 0.70, width: w, height: h)
    }

    // MARK: - Gemini API

    private func callGemini(base64Image: String) async throws -> [DetectionResult] {
        let payload: [String: Any] = [
            "contents": [[
                "parts": [
                    ["inlineData": ["mimeType": "image/jpeg", "data": base64Image]],
                    ["text": Self.stumpDetectionPrompt]
                ]
            ]],
            "generationConfig": [
                "temperature": 0.0,
                "responseMimeType": "application/json"
            ]
        ]

        let url = WBConfig.generateContentURL(model: WBConfig.deepAnalysisModel)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15  // calibration should be fast
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            log.error("Stump detection API error: HTTP \(statusCode)")
            throw StumpDetectionError.apiError(statusCode)
        }

        return try parseResponse(data)
    }

    // MARK: - Response Parsing

    /// Parse Gemini response into detection results.
    /// Exposed as static for unit testing without network calls.
    static func parseDetectionResponse(_ responseData: Data) throws -> [DetectionResult] {
        let json = try JSONSerialization.jsonObject(with: responseData) as? [String: Any]

        guard let candidates = json?["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first(where: { $0["text"] != nil })?["text"] as? String else {
            throw StumpDetectionError.parseError
        }

        return try parseStumpsJSON(text)
    }

    /// Parse the inner JSON (the model's text output).
    static func parseStumpsJSON(_ text: String) throws -> [DetectionResult] {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            cleaned = cleaned
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard let jsonData = cleaned.data(using: .utf8),
              let result = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let stumps = result["stumps"] as? [[String: Any]] else {
            throw StumpDetectionError.parseError
        }

        return stumps.compactMap { dict -> DetectionResult? in
            guard let label = dict["label"] as? String,
                  let cx = dict["center_x"] as? Double,
                  let cy = dict["center_y"] as? Double else {
                return nil
            }
            let confidence = dict["confidence"] as? Double ?? 0.5
            guard cx >= 0, cx <= 1, cy >= 0, cy <= 1 else { return nil }

            return DetectionResult(
                normalizedCenter: CGPoint(x: cx, y: cy),
                confidence: confidence,
                label: label
            )
        }
    }

    private func parseResponse(_ data: Data) throws -> [DetectionResult] {
        try Self.parseDetectionResponse(data)
    }
}

// MARK: - Errors

enum StumpDetectionError: LocalizedError {
    case imageEncodingFailed
    case apiError(Int)
    case parseError

    var errorDescription: String? {
        switch self {
        case .imageEncodingFailed: return "Failed to encode camera frame"
        case .apiError(let code): return "Stump detection API error (HTTP \(code))"
        case .parseError: return "Failed to parse stump detection response"
        }
    }
}
