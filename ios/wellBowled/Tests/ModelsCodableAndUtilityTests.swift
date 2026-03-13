import CoreGraphics
import XCTest
@testable import wellBowled

@MainActor
final class ModelsCodableAndUtilityTests: XCTestCase {

    func testDeliveryCodableRoundTripWithAllOptionalFields() throws {
        let match = BowlingDNAMatch(
            bowlerName: "Glenn McGrath",
            country: "AUS",
            era: "1990s-2000s",
            style: "Fast-Medium",
            similarityPercent: 88.4,
            closestPhase: "Release",
            biggestDifference: "Run-up speed",
            signatureTraits: ["High arm", "Seam control", "Balance"]
        )

        let original = Delivery(
            timestamp: 12.3,
            report: "Good length",
            speed: "125 kph",
            tips: ["Keep chest tall"],
            phases: [
                AnalysisPhase(name: "Run-up", status: "GOOD", observation: "Smooth", tip: "Keep rhythm", clipTimestamp: 0.8),
                AnalysisPhase(name: "Release", status: "NEEDS WORK", observation: "Late wrist", tip: "Snap earlier", clipTimestamp: 2.1)
            ],
            releaseTimestamp: 2.1,
            status: .success,
            videoURL: URL(string: "file:///tmp/delivery.mov"),
            thumbnail: nil,
            sequence: 7,
            videoID: "vid_123",
            cloudVideoURL: URL(string: "https://example.com/video.mp4"),
            cloudThumbnailURL: URL(string: "https://example.com/thumb.jpg"),
            overlayVideoURL: URL(string: "https://example.com/overlay.mp4"),
            localOverlayPath: "overlays/o7.mp4",
            landmarksURL: URL(string: "https://example.com/landmarks.json"),
            isFavorite: true,
            localThumbnailPath: "thumbs/t7.jpg",
            localVideoPath: "videos/v7.mov",
            wristOmega: 1420.5,
            releaseWristY: 0.42,
            dna: FamousBowlerDatabase.anderson.dna,
            dnaMatches: [match]
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Delivery.self, from: encoded)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.timestamp, original.timestamp, accuracy: 0.0001)
        XCTAssertEqual(decoded.report, original.report)
        XCTAssertEqual(decoded.speed, original.speed)
        XCTAssertEqual(decoded.tips, original.tips)
        XCTAssertEqual(decoded.releaseTimestamp ?? -1, original.releaseTimestamp ?? -1, accuracy: 0.0001)
        XCTAssertEqual(decoded.status, original.status)
        XCTAssertEqual(decoded.sequence, original.sequence)
        XCTAssertEqual(decoded.videoID, original.videoID)
        XCTAssertEqual(decoded.cloudVideoURL, original.cloudVideoURL)
        XCTAssertEqual(decoded.cloudThumbnailURL, original.cloudThumbnailURL)
        XCTAssertEqual(decoded.overlayVideoURL, original.overlayVideoURL)
        XCTAssertEqual(decoded.localOverlayPath, original.localOverlayPath)
        XCTAssertEqual(decoded.landmarksURL, original.landmarksURL)
        XCTAssertEqual(decoded.isFavorite, original.isFavorite)
        XCTAssertEqual(decoded.localThumbnailPath, original.localThumbnailPath)
        XCTAssertEqual(decoded.localVideoPath, original.localVideoPath)
        XCTAssertEqual(decoded.wristOmega ?? -1, original.wristOmega ?? -1, accuracy: 0.0001)
        XCTAssertEqual(decoded.releaseWristY ?? -1, original.releaseWristY ?? -1, accuracy: 0.0001)
        XCTAssertEqual(decoded.dna, original.dna)
        XCTAssertEqual(decoded.dnaMatches, original.dnaMatches)
        XCTAssertNil(decoded.thumbnail)
    }

    func testDeliveryEquatableConsidersOverlayAndDNAFields() {
        let id = UUID()
        var lhs = Delivery(id: id, timestamp: 1.0, sequence: 1, localOverlayPath: "a.mp4", wristOmega: 1200, releaseWristY: 0.3, dna: FamousBowlerDatabase.bumrah.dna)
        var rhs = Delivery(id: id, timestamp: 1.0, sequence: 1, localOverlayPath: "a.mp4", wristOmega: 1200, releaseWristY: 0.3, dna: FamousBowlerDatabase.bumrah.dna)
        XCTAssertEqual(lhs, rhs)

        rhs.localOverlayPath = "b.mp4"
        XCTAssertNotEqual(lhs, rhs)

        rhs.localOverlayPath = "a.mp4"
        rhs.wristOmega = 1100
        XCTAssertNotEqual(lhs, rhs)

        rhs.wristOmega = 1200
        rhs.releaseWristY = 0.7
        XCTAssertNotEqual(lhs, rhs)

        rhs.releaseWristY = 0.3
        rhs.dna = FamousBowlerDatabase.starc.dna
        XCTAssertNotEqual(lhs, rhs)

        lhs.dna = nil
        rhs.dna = nil
        XCTAssertEqual(lhs, rhs)
    }

    func testAnalysisPhaseDecodingDefaultsOptionalFields() throws {
        let json = """
        {"name":"Release","status":"needs work","clip_ts":2.3}
        """
        let decoded = try JSONDecoder().decode(AnalysisPhase.self, from: Data(json.utf8))

        XCTAssertEqual(decoded.name, "Release")
        XCTAssertEqual(decoded.status, "needs work")
        XCTAssertEqual(decoded.observation, "")
        XCTAssertEqual(decoded.tip, "")
        XCTAssertEqual(decoded.clipTimestamp ?? -1, 2.3, accuracy: 0.0001)
        XCTAssertFalse(decoded.isGood, "'needs work' should not be treated as good")

        let goodJSON = """
        {"name":"Release","status":"mostly good"}
        """
        let goodDecoded = try JSONDecoder().decode(AnalysisPhase.self, from: Data(goodJSON.utf8))
        XCTAssertTrue(goodDecoded.isGood, "status containing 'good' should be treated as good")
    }

    func testExpertAnalysisFeedbackDecodesInjuryRiskCodingKey() throws {
        let json = """
        {
          "phases": [
            {
              "phaseName": "Release",
              "start": 1.5,
              "end": 2.2,
              "feedback": {
                "good": ["RIGHT_SHOULDER"],
                "slow": ["RIGHT_ELBOW"],
                "injury_risk": ["RIGHT_WRIST"]
              }
            }
          ]
        }
        """
        let decoded = try JSONDecoder().decode(ExpertAnalysis.self, from: Data(json.utf8))
        let phase = try XCTUnwrap(decoded.phases.first)
        XCTAssertEqual(phase.feedback.good, ["RIGHT_SHOULDER"])
        XCTAssertEqual(phase.feedback.slow, ["RIGHT_ELBOW"])
        XCTAssertEqual(phase.feedback.injuryRisk, ["RIGHT_WRIST"])
    }

    func testSkeletonRendererUtilities() {
        let landmarks = [
            PoseLandmark(name: "A", index: 1, x: 0.25, y: 0.75, z: 0, visibility: 0.9),
            PoseLandmark(name: "B", index: 2, x: 0.5, y: 0.5, z: 0, visibility: 0.1)
        ]

        let visible = SkeletonRenderer.filterVisible(landmarks, threshold: 0.5)
        XCTAssertEqual(visible.count, 1)
        XCTAssertEqual(visible.first?.name, "A")

        let point = SkeletonRenderer.toScreenCoordinates(landmarks[0], size: CGSize(width: 200, height: 100))
        XCTAssertEqual(point.x, 50, accuracy: 0.0001)
        XCTAssertEqual(point.y, 75, accuracy: 0.0001)
    }

    func testStreamingEventStoresMessageAndType() {
        let event = StreamingEvent(message: "Analyzing release phase", type: "process")
        XCTAssertEqual(event.message, "Analyzing release phase")
        XCTAssertEqual(event.type, "process")
    }
}
