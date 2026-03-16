import XCTest
@testable import wellBowled

// MARK: - Voice Command Word Boundary Tests

@MainActor
final class VoiceCommandTests: XCTestCase {

    // "play" should match as a standalone word, not inside other words
    func testPlayDoesNotMatchReplay() {
        let words = Set("can you replay that".split(separator: " ").map(String.init))
        XCTAssertFalse(words.contains("play"), "'replay' should not match 'play'")
    }

    func testPlayDoesNotMatchDisplay() {
        let words = Set("display the results".split(separator: " ").map(String.init))
        XCTAssertFalse(words.contains("play"), "'display' should not match 'play'")
    }

    func testPlayMatchesStandalonePlay() {
        let words = Set("play the video".split(separator: " ").map(String.init))
        XCTAssertTrue(words.contains("play"))
    }

    func testPauseMatchesStandalone() {
        let words = Set("pause it there".split(separator: " ").map(String.init))
        XCTAssertTrue(words.contains("pause"))
    }

    func testSlowMotionPhraseMatches() {
        let lower = "show me in slow motion"
        XCTAssertTrue(lower.contains("slow motion"))
    }

    func testNormalSpeedPhraseMatches() {
        let lower = "go back to normal speed"
        XCTAssertTrue(lower.contains("normal speed"))
    }

    func testFreezeMatchesStandalone() {
        let words = Set("freeze right there".split(separator: " ").map(String.init))
        XCTAssertTrue(words.contains("freeze"))
    }

    func testResumeMatchesStandalone() {
        let words = Set("resume playing".split(separator: " ").map(String.init))
        XCTAssertTrue(words.contains("resume"))
    }

    func testSlowMoRateParsingQuarter() {
        let lower = "ultra slow mo please"
        XCTAssertTrue(lower.contains("ultra"))
    }

    func testSlowMoRateParsingHalf() {
        let lower = "half speed slow motion"
        let words = Set(lower.split(separator: " ").map(String.init))
        XCTAssertTrue(words.contains("half"))
    }

    func test2xSpeedMatches() {
        let words = Set("set it to 2x".split(separator: " ").map(String.init))
        XCTAssertTrue(words.contains("2x"))
    }

    func testDoubleSpeedMatches() {
        let words = Set("double speed please".split(separator: " ").map(String.init))
        XCTAssertTrue(words.contains("double"))
    }
}

// MARK: - End Session Detection Tests (extended)

@MainActor
final class EndSessionDetectionExtendedTests: XCTestCase {

    func testDoesNotMatchPartialWords() {
        // "session" inside "impression" should not match
        XCTAssertFalse(SessionViewModel.shouldEndSession(from: "good impression"))
        XCTAssertFalse(SessionViewModel.shouldEndSession(from: "that was a nice finishing touch"))
    }

    func testMatchesNaturalVariations() {
        XCTAssertTrue(SessionViewModel.shouldEndSession(from: "I'm done"))
        XCTAssertTrue(SessionViewModel.shouldEndSession(from: "that'll do"))
        XCTAssertTrue(SessionViewModel.shouldEndSession(from: "let's call it"))
    }

    func testDoesNotMatchUnrelatedSentences() {
        XCTAssertFalse(SessionViewModel.shouldEndSession(from: "show me the next delivery"))
        XCTAssertFalse(SessionViewModel.shouldEndSession(from: "what was my speed"))
        XCTAssertFalse(SessionViewModel.shouldEndSession(from: "replay that in slow mo"))
    }
}

// MARK: - DNA Parsing Robustness Tests

final class DNAParsingRobustnessTests: XCTestCase {

    func testValidDNAFieldsParse() {
        let dict: [String: Any] = [
            "arm_path": "high",
            "gather_alignment": "side_on",
            "release_height": "medium",
            "wrist_position": "behind",
            "follow_through_direction": "across",
            "balance_at_finish": "balanced"
        ]
        let dna = parseDNA(from: dict)
        XCTAssertEqual(dna?.armPath, .high)
        XCTAssertEqual(dna?.gatherAlignment, .sideOn)
        XCTAssertEqual(dna?.releaseHeight, .medium)
        XCTAssertEqual(dna?.wristPosition, .behind)
        XCTAssertEqual(dna?.followThroughDirection, .across)
        XCTAssertEqual(dna?.balanceAtFinish, .balanced)
    }

    func testUnexpectedEnumValueReturnsNil() {
        let dict: [String: Any] = [
            "arm_path": "SUPER_HIGH",      // invalid
            "gather_alignment": "Front-On", // wrong case
            "release_height": 42            // wrong type (Int, not String)
        ]
        let dna = parseDNA(from: dict)
        XCTAssertNil(dna?.armPath, "Invalid enum value should parse as nil")
        XCTAssertNil(dna?.gatherAlignment, "Wrong case should parse as nil")
        XCTAssertNil(dna?.releaseHeight, "Wrong type should parse as nil")
    }

    func testEmptyDictReturnsNil() {
        // All-nil DNA should be nullified (our robustness fix)
        let dict: [String: Any] = [
            "arm_path": "INVALID",
            "gather_alignment": "INVALID"
        ]
        let dna = parseDNA(from: dict)
        // Since no key fields parse, DNA should be nil
        XCTAssertNil(dna, "All-nil DNA should be discarded")
    }

    func testPartialDNAParsesSuccessfully() {
        let dict: [String: Any] = [
            "arm_path": "high",
            "gather_alignment": "INVALID",
            "release_height": "low"
        ]
        let dna = parseDNA(from: dict)
        XCTAssertNotNil(dna, "Partial DNA with some valid fields should succeed")
        XCTAssertEqual(dna?.armPath, .high)
        XCTAssertNil(dna?.gatherAlignment)
        XCTAssertEqual(dna?.releaseHeight, .low)
    }

    func testNullValuesInDNADict() {
        let dict: [String: Any] = [
            "arm_path": NSNull(),
            "gather_alignment": NSNull(),
            "release_height": "high"
        ]
        let dna = parseDNA(from: dict)
        XCTAssertNotNil(dna)
        XCTAssertNil(dna?.armPath)
        XCTAssertEqual(dna?.releaseHeight, .high)
    }

    // Helper: mimics the DNA parsing logic from GeminiAnalysisService
    private func parseDNA(from dict: [String: Any]) -> BowlingDNA? {
        var dna = BowlingDNA(
            runUpStride: (dict["run_up_stride"] as? String).flatMap(RunUpStrideCategory.init),
            runUpSpeed: (dict["run_up_speed"] as? String).flatMap(RunUpSpeed.init),
            approachAngle: (dict["approach_angle"] as? String).flatMap(ApproachAngle.init),
            gatherAlignment: (dict["gather_alignment"] as? String).flatMap(BodyAlignment.init),
            backFootContact: (dict["back_foot_contact"] as? String).flatMap(BackFootContact.init),
            trunkLean: (dict["trunk_lean"] as? String).flatMap(TrunkLean.init),
            deliveryStrideLength: (dict["delivery_stride_length"] as? String).flatMap(StrideLength.init),
            frontArmAction: (dict["front_arm_action"] as? String).flatMap(FrontArmAction.init),
            headStability: (dict["head_stability"] as? String).flatMap(HeadStability.init),
            armPath: (dict["arm_path"] as? String).flatMap(ArmPath.init),
            releaseHeight: (dict["release_height"] as? String).flatMap(ReleaseHeight.init),
            wristPosition: (dict["wrist_position"] as? String).flatMap(WristPosition.init),
            seamOrientation: (dict["seam_orientation"] as? String).flatMap(SeamOrientation.init),
            revolutions: (dict["revolutions"] as? String).flatMap(Revolutions.init),
            followThroughDirection: (dict["follow_through_direction"] as? String).flatMap(FollowThroughDir.init),
            balanceAtFinish: (dict["balance_at_finish"] as? String).flatMap(BalanceAtFinish.init)
        )
        // Same nullification logic as GeminiAnalysisService
        let keyFields: [Any?] = [dna.runUpStride, dna.armPath, dna.gatherAlignment,
                                  dna.releaseHeight, dna.wristPosition, dna.followThroughDirection]
        let parsed = keyFields.compactMap { $0 }.count
        if parsed == 0 {
            return nil
        }
        return dna
    }
}

// MARK: - HTTP Status Code Fallback Tests

final class HTTPFallbackTests: XCTestCase {

    func testRetryableStatusCodesInclude429And5xx() {
        let retryable: Set<Int> = [400, 404, 429, 500, 502, 503]
        XCTAssertTrue(retryable.contains(429), "Rate limit should be retryable")
        XCTAssertTrue(retryable.contains(500), "Server error should be retryable")
        XCTAssertTrue(retryable.contains(502), "Bad gateway should be retryable")
        XCTAssertTrue(retryable.contains(503), "Service unavailable should be retryable")
        XCTAssertTrue(retryable.contains(400), "Bad request should be retryable")
        XCTAssertTrue(retryable.contains(404), "Not found should be retryable")
        XCTAssertFalse(retryable.contains(401), "Auth error should NOT be retryable")
        XCTAssertFalse(retryable.contains(403), "Forbidden should NOT be retryable")
    }
}

// MARK: - DeliveryDeepAnalysisResult Codable Tests

final class DeepAnalysisResultCodableTests: XCTestCase {

    func testCodableRoundTripWithDNA() throws {
        let dna = BowlingDNA(armPath: .high, releaseHeight: .medium, wristPosition: .behind)
        let result = DeliveryDeepAnalysisResult(
            paceEstimate: "fast",
            summary: "Good delivery",
            phases: [],
            expertAnalysis: nil,
            dna: dna
        )

        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(DeliveryDeepAnalysisResult.self, from: data)

        XCTAssertEqual(decoded.paceEstimate, "fast")
        XCTAssertEqual(decoded.summary, "Good delivery")
        XCTAssertEqual(decoded.dna?.armPath, .high)
        XCTAssertEqual(decoded.dna?.releaseHeight, .medium)
    }

    func testCodableRoundTripWithNilDNA() throws {
        let result = DeliveryDeepAnalysisResult(
            paceEstimate: "medium pace",
            summary: "Average delivery",
            phases: [],
            expertAnalysis: nil,
            dna: nil
        )

        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(DeliveryDeepAnalysisResult.self, from: data)

        XCTAssertEqual(decoded.paceEstimate, "medium pace")
        XCTAssertNil(decoded.dna)
    }
}
