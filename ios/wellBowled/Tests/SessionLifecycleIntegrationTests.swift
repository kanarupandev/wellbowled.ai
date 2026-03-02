import XCTest
@testable import wellBowled

/// Integration tests for the Session → Delivery → Analysis lifecycle.
/// Tests the data flow without hardware dependencies (camera, Live API).
@MainActor
final class SessionLifecycleIntegrationTests: XCTestCase {

    // MARK: - Full Session Flow

    func testFreePlaySessionLifecycle() {
        var session = Session()

        // 1. Start session
        session.start(mode: .freePlay)
        XCTAssertTrue(session.isActive)
        XCTAssertEqual(session.mode, .freePlay)

        // 2. Detect deliveries
        let d1 = Delivery(timestamp: 5.0, status: .clipping, sequence: 1)
        session.addDelivery(d1)
        XCTAssertEqual(session.deliveryCount, 1)

        let d2 = Delivery(timestamp: 12.0, status: .clipping, sequence: 2)
        session.addDelivery(d2)
        XCTAssertEqual(session.deliveryCount, 2)

        // 3. Simulate analysis completing
        session.deliveries[0].status = .success
        session.deliveries[0].report = "Good length seam delivery"
        session.deliveries[0].speed = "110-115 kph"

        session.deliveries[1].status = .failed
        // Second delivery analysis failed

        // 4. End session
        session.end()
        XCTAssertFalse(session.isActive)
        XCTAssertNotNil(session.endedAt)

        // 5. Verify final state
        XCTAssertEqual(session.deliveries[0].status, .success)
        XCTAssertEqual(session.deliveries[1].status, .failed)
        XCTAssertEqual(session.deliveryCount, 2)
    }

    func testChallengeSessionLifecycle() {
        var session = Session()

        // 1. Start in challenge mode
        session.start(mode: .challenge)
        session.currentChallenge = "Bowl 3 yorkers"

        // 2. Bowl and record results
        session.addDelivery(Delivery(timestamp: 3.0, status: .success, sequence: 1))
        session.recordChallengeResult(hit: true) // yorker hit

        session.addDelivery(Delivery(timestamp: 10.0, status: .success, sequence: 2))
        session.recordChallengeResult(hit: false) // missed

        session.addDelivery(Delivery(timestamp: 17.0, status: .success, sequence: 3))
        session.recordChallengeResult(hit: true) // yorker hit

        // 3. End and verify
        session.end()
        XCTAssertEqual(session.challengeHits, 2)
        XCTAssertEqual(session.challengeTotal, 3)
        XCTAssertEqual(session.challengeScoreText, "2/3 (66%)")
    }

    // MARK: - Delivery Status Transitions

    func testDeliveryStatusTransition() {
        var delivery = Delivery(timestamp: 5.0, sequence: 1)

        // Normal flow: detecting → clipping → analyzing → success
        XCTAssertEqual(delivery.status, .detecting)

        delivery.status = .clipping
        XCTAssertEqual(delivery.status, .clipping)

        delivery.status = .analyzing
        XCTAssertEqual(delivery.status, .analyzing)

        delivery.status = .success
        delivery.report = "Clean delivery"
        delivery.speed = "125 kph"
        XCTAssertEqual(delivery.status, .success)
        XCTAssertNotNil(delivery.report)
        XCTAssertNotNil(delivery.speed)
    }

    func testDeliveryStatusFailurePath() {
        var delivery = Delivery(timestamp: 5.0, status: .analyzing, sequence: 1)

        delivery.status = .failed
        XCTAssertEqual(delivery.status, .failed)
        XCTAssertNil(delivery.report)
    }

    // MARK: - Timestamp Offset Logic

    func testTimestampOffsetForClipExtraction() {
        // Simulate the offset logic from SessionViewModel.runPostSessionAnalysis
        let recordingStartTime = 100.0 // arbitrary CMTime value
        let deliveryTimestamp = 115.3   // delivery detected at this time

        let clipTimestamp = deliveryTimestamp - recordingStartTime
        XCTAssertEqual(clipTimestamp, 15.3, accuracy: 0.001,
                       "Clip timestamp should be offset to recording-relative time")
    }

    func testTimestampOffsetClampsToZero() {
        // Edge case: delivery detected before recording started (shouldn't happen, but defensive)
        let recordingStartTime = 100.0
        let deliveryTimestamp = 99.0

        let clipTimestamp = max(deliveryTimestamp - recordingStartTime, 0)
        XCTAssertEqual(clipTimestamp, 0.0, "Should clamp to 0 if delivery is before recording start")
    }

    // MARK: - Multiple Sessions

    func testConsecutiveSessionsAreIndependent() {
        var session = Session()

        // Session 1
        session.start()
        session.addDelivery(Delivery(timestamp: 5.0, sequence: 1))
        session.addDelivery(Delivery(timestamp: 10.0, sequence: 2))
        session.end()
        XCTAssertEqual(session.deliveryCount, 2)

        // Session 2 — start resets everything
        session.start()
        XCTAssertEqual(session.deliveryCount, 0)
        XCTAssertTrue(session.isActive)
        XCTAssertNil(session.endedAt)

        session.addDelivery(Delivery(timestamp: 3.0, sequence: 1))
        session.end()
        XCTAssertEqual(session.deliveryCount, 1)
    }

    // MARK: - Wire Protocol Encoding

    func testLiveSetupMessageEncoding() throws {
        let setup = LiveSetupMessage(
            setup: LiveSetupConfig(
                model: "models/test-model",
                generationConfig: LiveGenerationConfig(
                    responseModalities: ["AUDIO"],
                    speechConfig: LiveSpeechConfig(
                        voiceConfig: LiveVoiceConfig(
                            prebuiltVoiceConfig: PrebuiltVoiceConfig(voiceName: "Achird")
                        )
                    )
                ),
                systemInstruction: LiveSystemInstruction(
                    parts: [LiveTextPart(text: "Test instruction")]
                ),
                outputAudioTranscription: LiveOutputAudioTranscription(),
                contextWindowCompression: LiveContextWindowCompression(
                    triggerTokens: 25600,
                    slidingWindow: LiveSlidingWindow(targetTokens: 12800)
                ),
                tools: [],
                sessionResumption: nil
            )
        )

        let data = try JSONEncoder().encode(setup)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertNotNil(json?["setup"])
        let setupObj: [String: Any]? = json?["setup"] as? [String: Any]
        XCTAssertEqual(setupObj?["model"] as? String, "models/test-model")
        // No sessionResumption when nil
        XCTAssertNil(setupObj?["sessionResumption"])
    }

    func testLiveSetupMessageWithResumptionHandle() throws {
        let setup = LiveSetupMessage(
            setup: LiveSetupConfig(
                model: "models/test-model",
                generationConfig: LiveGenerationConfig(
                    responseModalities: ["AUDIO"],
                    speechConfig: LiveSpeechConfig(
                        voiceConfig: LiveVoiceConfig(
                            prebuiltVoiceConfig: PrebuiltVoiceConfig(voiceName: "Achird")
                        )
                    )
                ),
                systemInstruction: LiveSystemInstruction(
                    parts: [LiveTextPart(text: "Test instruction")]
                ),
                outputAudioTranscription: LiveOutputAudioTranscription(),
                contextWindowCompression: LiveContextWindowCompression(
                    triggerTokens: 25600,
                    slidingWindow: LiveSlidingWindow(targetTokens: 12800)
                ),
                tools: [],
                sessionResumption: LiveSessionResumption(handle: "resume-handle-abc123")
            )
        )

        let data = try JSONEncoder().encode(setup)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        let setupObj: [String: Any]? = json?["setup"] as? [String: Any]
        let resumption: [String: Any]? = setupObj?["sessionResumption"] as? [String: Any]
        XCTAssertNotNil(resumption)
        XCTAssertEqual(resumption?["handle"] as? String, "resume-handle-abc123")
    }

    func testRealtimeInputEncoding() throws {
        let input = LiveRealtimeInput(
            realtimeInput: LiveMediaInput(
                mediaChunks: [LiveMediaChunk(mimeType: "image/jpeg", data: "base64data")]
            )
        )

        let data = try JSONEncoder().encode(input)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertNotNil(json?["realtimeInput"])
        let realtimeInput = json?["realtimeInput"] as? [String: Any]
        let chunks = realtimeInput?["mediaChunks"] as? [[String: Any]]
        XCTAssertEqual(chunks?.first?["mimeType"] as? String, "image/jpeg")
    }

    func testClientContentEncoding() throws {
        let content = LiveClientContent(
            clientContent: LiveClientTurn(
                turns: [LiveTurn(role: "user", parts: [LiveTextPart(text: "Delivery 3 detected")])],
                turnComplete: true
            )
        )

        let data = try JSONEncoder().encode(content)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        let clientContent = json?["clientContent"] as? [String: Any]
        XCTAssertNotNil(clientContent)
        XCTAssertEqual(clientContent?["turnComplete"] as? Bool, true)
    }

    // MARK: - Server Message Decoding

    func testDecodeSetupComplete() throws {
        let json = """
        {"setupComplete":{}}
        """
        let msg = try JSONDecoder().decode(LiveServerMessage.self, from: json.data(using: .utf8)!)
        XCTAssertNotNil(msg.setupComplete)
        XCTAssertNil(msg.serverContent)
    }

    func testDecodeTranscription() throws {
        let json = """
        {"serverContent":{"outputTranscription":{"text":"Hello mate"}}}
        """
        let msg = try JSONDecoder().decode(LiveServerMessage.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(msg.serverContent?.outputTranscription?.text, "Hello mate")
    }

    func testDecodeTurnComplete() throws {
        let json = """
        {"serverContent":{"turnComplete":true}}
        """
        let msg = try JSONDecoder().decode(LiveServerMessage.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(msg.serverContent?.turnComplete, true)
    }

    func testDecodeGoAway() throws {
        let json = """
        {"goAway":{"timeLeft":"30s"}}
        """
        let msg = try JSONDecoder().decode(LiveServerMessage.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(msg.goAway?.timeLeft, "30s")
    }

    func testDecodeSessionResumption() throws {
        let json = """
        {"sessionResumptionUpdate":{"newHandle":"abc123"}}
        """
        let msg = try JSONDecoder().decode(LiveServerMessage.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(msg.sessionResumptionUpdate?.newHandle, "abc123")
    }

    func testDecodeAudioContent() throws {
        let json = """
        {"serverContent":{"modelTurn":{"parts":[{"inlineData":{"mimeType":"audio/pcm;rate=24000","data":"AQID"}}]}}}
        """
        let msg = try JSONDecoder().decode(LiveServerMessage.self, from: json.data(using: .utf8)!)
        let part = msg.serverContent?.modelTurn?.parts.first
        XCTAssertEqual(part?.inlineData?.mimeType, "audio/pcm;rate=24000")
        XCTAssertEqual(part?.inlineData?.data, "AQID")
    }
}
