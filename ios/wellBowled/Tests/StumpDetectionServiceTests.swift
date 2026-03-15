import CoreGraphics
import XCTest
@testable import wellBowled

final class StumpDetectionServiceTests: XCTestCase {

    // MARK: - Init & Reset

    func testInitialStateIsIdle() {
        let service = StumpDetectionService()
        XCTAssertEqual(service.state, .idle)
    }

    func testResetReturnsToIdle() {
        let service = StumpDetectionService()
        _ = service.calibrateFromManualTaps(
            bowlerTap: CGPoint(x: 0.5, y: 0.15),
            strikerTap: CGPoint(x: 0.5, y: 0.85),
            frameWidth: 1920, frameHeight: 1080, fps: 120
        )
        XCTAssertNotEqual(service.state, .idle)

        service.reset()
        XCTAssertEqual(service.state, .idle)
    }

    // MARK: - Manual Calibration

    func testManualCalibrationProducesValidCalibration() {
        let service = StumpDetectionService()
        let cal = service.calibrateFromManualTaps(
            bowlerTap: CGPoint(x: 0.5, y: 0.15),
            strikerTap: CGPoint(x: 0.5, y: 0.85),
            frameWidth: 1920, frameHeight: 1080, fps: 120
        )

        XCTAssertNotNil(cal)
        XCTAssertTrue(cal!.isValid)
        XCTAssertTrue(cal!.isManualPlacement)
        XCTAssertEqual(cal!.recordingFPS, 120)

        if case .locked(let locked) = service.state {
            XCTAssertEqual(locked, cal)
        } else {
            XCTFail("State should be .locked after manual calibration")
        }
    }

    func testManualCalibrationRejectsOverlappingPoints() {
        let service = StumpDetectionService()
        let cal = service.calibrateFromManualTaps(
            bowlerTap: CGPoint(x: 0.5, y: 0.5),
            strikerTap: CGPoint(x: 0.5, y: 0.5),
            frameWidth: 1920, frameHeight: 1080, fps: 120
        )
        XCTAssertNil(cal)
    }

    func testManualCalibrationRejectsZeroDimensions() {
        let service = StumpDetectionService()
        let cal = service.calibrateFromManualTaps(
            bowlerTap: CGPoint(x: 0.5, y: 0.15),
            strikerTap: CGPoint(x: 0.5, y: 0.85),
            frameWidth: 0, frameHeight: 0, fps: 120
        )
        XCTAssertNil(cal)
    }

    // MARK: - Guide Box Defaults

    func testDefaultBowlerGuideRectIsInUpperRegion() {
        let rect = StumpDetectionService.defaultBowlerGuideRect()
        XCTAssertLessThan(rect.midY, 0.5)
        XCTAssertGreaterThan(rect.width, 0)
        XCTAssertGreaterThan(rect.height, 0)
    }

    func testDefaultStrikerGuideRectIsInLowerRegion() {
        let rect = StumpDetectionService.defaultStrikerGuideRect()
        XCTAssertGreaterThan(rect.midY, 0.5)
        XCTAssertGreaterThan(rect.width, 0)
        XCTAssertGreaterThan(rect.height, 0)
    }

    func testGuideRectsDoNotOverlap() {
        let bowler = StumpDetectionService.defaultBowlerGuideRect()
        let striker = StumpDetectionService.defaultStrikerGuideRect()
        XCTAssertFalse(bowler.intersects(striker))
    }

    func testGuideRectsAreWithinFrame() {
        let bowler = StumpDetectionService.defaultBowlerGuideRect()
        let striker = StumpDetectionService.defaultStrikerGuideRect()
        let frame = CGRect(x: 0, y: 0, width: 1, height: 1)
        XCTAssertTrue(frame.contains(bowler))
        XCTAssertTrue(frame.contains(striker))
    }

    // MARK: - CalibrationState Equatable

    func testCalibrationStateEquatable() {
        XCTAssertEqual(StumpDetectionService.CalibrationState.idle, .idle)
        XCTAssertEqual(StumpDetectionService.CalibrationState.detecting, .detecting)
        XCTAssertEqual(StumpDetectionService.CalibrationState.failed("msg"), .failed("msg"))
        XCTAssertNotEqual(StumpDetectionService.CalibrationState.idle, .failed("msg"))
        XCTAssertNotEqual(StumpDetectionService.CalibrationState.idle, .detecting)
    }

    // MARK: - Gemini Response Parsing

    func testParseValidTwoStumpResponse() throws {
        let json = """
        {
          "stumps": [
            {"label": "bowler_end", "center_x": 0.52, "center_y": 0.18, "confidence": 0.92},
            {"label": "striker_end", "center_x": 0.48, "center_y": 0.83, "confidence": 0.88}
          ]
        }
        """
        let results = try StumpDetectionService.parseStumpsJSON(json)
        XCTAssertEqual(results.count, 2)

        let bowler = results.first { $0.label == "bowler_end" }
        XCTAssertNotNil(bowler)
        XCTAssertEqual(bowler!.normalizedCenter.x, 0.52, accuracy: 0.001)
        XCTAssertEqual(bowler!.normalizedCenter.y, 0.18, accuracy: 0.001)
        XCTAssertEqual(bowler!.confidence, 0.92, accuracy: 0.01)

        let striker = results.first { $0.label == "striker_end" }
        XCTAssertNotNil(striker)
        XCTAssertEqual(striker!.normalizedCenter.x, 0.48, accuracy: 0.001)
        XCTAssertEqual(striker!.normalizedCenter.y, 0.83, accuracy: 0.001)
    }

    func testParseEmptyStumpsArray() throws {
        let json = """
        { "stumps": [] }
        """
        let results = try StumpDetectionService.parseStumpsJSON(json)
        XCTAssertTrue(results.isEmpty)
    }

    func testParseSingleStump() throws {
        let json = """
        {
          "stumps": [
            {"label": "striker_end", "center_x": 0.5, "center_y": 0.85, "confidence": 0.7}
          ]
        }
        """
        let results = try StumpDetectionService.parseStumpsJSON(json)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].label, "striker_end")
    }

    func testParseRejectsOutOfBoundsCoordinates() throws {
        let json = """
        {
          "stumps": [
            {"label": "bowler_end", "center_x": 1.5, "center_y": 0.2, "confidence": 0.9},
            {"label": "striker_end", "center_x": 0.5, "center_y": 0.8, "confidence": 0.9}
          ]
        }
        """
        let results = try StumpDetectionService.parseStumpsJSON(json)
        XCTAssertEqual(results.count, 1, "Out-of-bounds stump should be filtered out")
        XCTAssertEqual(results[0].label, "striker_end")
    }

    func testParseHandlesMarkdownCodeFence() throws {
        let json = """
        ```json
        {
          "stumps": [
            {"label": "bowler_end", "center_x": 0.5, "center_y": 0.15, "confidence": 0.85},
            {"label": "striker_end", "center_x": 0.5, "center_y": 0.80, "confidence": 0.80}
          ]
        }
        ```
        """
        let results = try StumpDetectionService.parseStumpsJSON(json)
        XCTAssertEqual(results.count, 2)
    }

    func testParseMissingConfidenceDefaultsToHalf() throws {
        let json = """
        {
          "stumps": [
            {"label": "bowler_end", "center_x": 0.5, "center_y": 0.2}
          ]
        }
        """
        let results = try StumpDetectionService.parseStumpsJSON(json)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].confidence, 0.5, accuracy: 0.01)
    }

    func testParseInvalidJSONThrows() {
        XCTAssertThrowsError(try StumpDetectionService.parseStumpsJSON("not json"))
    }

    func testParseMissingStumpsKeyThrows() {
        let json = """
        { "detections": [] }
        """
        XCTAssertThrowsError(try StumpDetectionService.parseStumpsJSON(json))
    }

    // MARK: - Full Gemini Response Parse (with candidates wrapper)

    func testParseFullGeminiResponse() throws {
        let geminiResponse: [String: Any] = [
            "candidates": [[
                "content": [
                    "parts": [[
                        "text": """
                        {"stumps":[{"label":"bowler_end","center_x":0.51,"center_y":0.16,"confidence":0.90},{"label":"striker_end","center_x":0.49,"center_y":0.84,"confidence":0.87}]}
                        """
                    ]]
                ]
            ]]
        ]
        let data = try JSONSerialization.data(withJSONObject: geminiResponse)
        let results = try StumpDetectionService.parseDetectionResponse(data)
        XCTAssertEqual(results.count, 2)
    }

    // MARK: - Manual Calibration Speed Computation

    func testManualCalibrationSpeedComputation() {
        let service = StumpDetectionService()
        let cal = service.calibrateFromManualTaps(
            bowlerTap: CGPoint(x: 0.5, y: 0.15),
            strikerTap: CGPoint(x: 0.5, y: 0.85),
            frameWidth: 1920, frameHeight: 1080, fps: 120
        )!

        let transit = 20.12 / (130.0 / 3.6)
        let speed = cal.speedKph(transitTimeSeconds: transit)
        XCTAssertNotNil(speed)
        XCTAssertEqual(speed!, 130.0, accuracy: 0.1)
    }

    // MARK: - Prompt Integrity

    func testStumpDetectionPromptContainsRequiredFields() {
        let prompt = StumpDetectionService.stumpDetectionPrompt
        XCTAssertTrue(prompt.contains("bowler_end"))
        XCTAssertTrue(prompt.contains("striker_end"))
        XCTAssertTrue(prompt.contains("center_x"))
        XCTAssertTrue(prompt.contains("center_y"))
        XCTAssertTrue(prompt.contains("confidence"))
        XCTAssertTrue(prompt.contains("STRICT JSON"))
    }
}
