import XCTest
@testable import wellBowled

final class BowlingDNATests: XCTestCase {

    // MARK: - Vector Encoding

    func testFullDNAEncodesTo20Dimensions() {
        let dna = FamousBowlerDatabase.mcGrath.dna
        let vector = BowlingDNAVectorEncoder.encode(dna)
        XCTAssertEqual(vector.count, 20)
    }

    func testKnownDNAEncodesCorrectly() {
        // McGrath: side-on (1.0 for 3-value), high arm (0.0 for 3-value),
        // straight approach (0.0), medium stride (0.5)
        let dna = FamousBowlerDatabase.mcGrath.dna
        let vector = BowlingDNAVectorEncoder.encode(dna)

        // runUpStride: medium = 0.5
        XCTAssertEqual(vector[0], 0.5, accuracy: 0.01)
        // runUpSpeed: moderate (4-value: slow=0, moderate=0.33, fast=0.67, explosive=1.0)
        XCTAssertEqual(vector[1], 1.0 / 3.0, accuracy: 0.01)
        // approachAngle: straight = 0.0
        XCTAssertEqual(vector[2], 0.0, accuracy: 0.01)
        // gatherAlignment: sideOn = 1.0
        XCTAssertEqual(vector[3], 1.0, accuracy: 0.01)
        // armPath: high = 0.0
        XCTAssertEqual(vector[9], 0.0, accuracy: 0.01)
    }

    func testEmptyDNAEncodesAllSentinels() {
        let dna = BowlingDNA()
        let vector = BowlingDNAVectorEncoder.encode(dna)
        XCTAssertEqual(vector.count, 20)
        for value in vector {
            XCTAssertEqual(value, -1.0, "All empty DNA fields should be sentinel (-1)")
        }
    }

    func testPartialDNAHasMixedSentinels() {
        var dna = BowlingDNA()
        dna.armPath = .sling
        dna.releaseHeight = .low

        let vector = BowlingDNAVectorEncoder.encode(dna)
        // armPath (index 9): sling = 1.0
        XCTAssertEqual(vector[9], 1.0, accuracy: 0.01)
        // releaseHeight (index 10): low = 1.0
        XCTAssertEqual(vector[10], 1.0, accuracy: 0.01)
        // Other fields should be sentinel
        XCTAssertEqual(vector[0], -1.0)
        XCTAssertEqual(vector[3], -1.0)
    }

    // MARK: - Matching

    func testBumrahDNAMatchesBumrahFirst() {
        let userDNA = FamousBowlerDatabase.bumrah.dna
        let matches = BowlingDNAMatcher.match(userDNA: userDNA, topN: 3)

        XCTAssertFalse(matches.isEmpty)
        XCTAssertEqual(matches[0].bowlerName, "Jasprit Bumrah")
        XCTAssertEqual(matches[0].similarityPercent, 100.0, accuracy: 0.1)
    }

    func testMcGrathDNAMatchesMcGrathFirst() {
        let userDNA = FamousBowlerDatabase.mcGrath.dna
        let matches = BowlingDNAMatcher.match(userDNA: userDNA, topN: 3)

        XCTAssertEqual(matches[0].bowlerName, "Glenn McGrath")
        XCTAssertEqual(matches[0].similarityPercent, 100.0, accuracy: 0.1)
    }

    func testTopNReturnsRequestedCount() {
        let userDNA = FamousBowlerDatabase.warne.dna
        let matches = BowlingDNAMatcher.match(userDNA: userDNA, topN: 5)
        XCTAssertEqual(matches.count, 5)
    }

    func testMatchResultsAreSortedBySimilarity() {
        let userDNA = FamousBowlerDatabase.starc.dna
        let matches = BowlingDNAMatcher.match(userDNA: userDNA, topN: 10)

        for i in 0..<(matches.count - 1) {
            XCTAssertGreaterThanOrEqual(
                matches[i].similarityPercent,
                matches[i + 1].similarityPercent
            )
        }
    }

    func testPartialDNADoesNotCrash() {
        var dna = BowlingDNA()
        dna.armPath = .sling
        dna.releaseHeight = .low

        let matches = BowlingDNAMatcher.match(userDNA: dna, topN: 3)
        XCTAssertFalse(matches.isEmpty, "Partial DNA should still produce matches")
    }

    func testEmptyDNAStillProducesMatches() {
        let dna = BowlingDNA()
        let matches = BowlingDNAMatcher.match(userDNA: dna, topN: 3)
        // With all sentinels, no valid dimensions — but should not crash
        XCTAssertEqual(matches.count, 3)
    }

    // MARK: - Match Metadata

    func testMatchContainsPhaseAndDifference() {
        let userDNA = FamousBowlerDatabase.anderson.dna
        let matches = BowlingDNAMatcher.match(userDNA: userDNA, topN: 1)

        XCTAssertFalse(matches[0].closestPhase.isEmpty)
        XCTAssertFalse(matches[0].biggestDifference.isEmpty)
        XCTAssertEqual(matches[0].signatureTraits.count, 3)
    }

    func testMatchContainsCountryAndEra() {
        let matches = BowlingDNAMatcher.match(
            userDNA: FamousBowlerDatabase.akram.dna,
            topN: 1
        )
        XCTAssertEqual(matches[0].country, "PAK")
        XCTAssertFalse(matches[0].era.isEmpty)
        XCTAssertFalse(matches[0].style.isEmpty)
    }

    // MARK: - Normalization

    func testOmegaNormalizationEdgeCases() {
        // Below threshold (800) → 0
        XCTAssertEqual(GeminiAnalysisService.normalizeOmega(500), 0.0, accuracy: 0.01)
        XCTAssertEqual(GeminiAnalysisService.normalizeOmega(800), 0.0, accuracy: 0.01)

        // Middle range
        XCTAssertEqual(GeminiAnalysisService.normalizeOmega(1400), 0.5, accuracy: 0.01)

        // Above cap (2000) → 1
        XCTAssertEqual(GeminiAnalysisService.normalizeOmega(2000), 1.0, accuracy: 0.01)
        XCTAssertEqual(GeminiAnalysisService.normalizeOmega(3000), 1.0, accuracy: 0.01)

        // Negative omega (abs is taken)
        XCTAssertEqual(GeminiAnalysisService.normalizeOmega(-1400), 0.5, accuracy: 0.01)
    }

    // MARK: - Codable Round-Trip

    func testBowlingDNACodableRoundTrip() throws {
        let original = FamousBowlerDatabase.bumrah.dna
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(BowlingDNA.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    func testBowlingDNAMatchCodableRoundTrip() throws {
        let match = BowlingDNAMatch(
            bowlerName: "Test",
            country: "AUS",
            era: "2020",
            style: "Fast",
            similarityPercent: 87.5,
            closestPhase: "Release",
            biggestDifference: "Arm path",
            signatureTraits: ["Trait 1", "Trait 2", "Trait 3"]
        )
        let data = try JSONEncoder().encode(match)
        let decoded = try JSONDecoder().decode(BowlingDNAMatch.self, from: data)
        XCTAssertEqual(match, decoded)
    }
}
