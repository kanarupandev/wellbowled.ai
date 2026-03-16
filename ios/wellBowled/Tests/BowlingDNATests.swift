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
        let matches = BowlingDNAMatcher.match(userDNA: userDNA, topN: 1)

        XCTAssertFalse(matches.isEmpty)
        XCTAssertEqual(matches[0].bowlerName, "Jasprit Bumrah")
        XCTAssertEqual(matches[0].similarityPercent, 100.0, accuracy: 0.1)
    }

    func testMcGrathDNAMatchesMcGrathFirst() {
        let userDNA = FamousBowlerDatabase.mcGrath.dna
        let matches = BowlingDNAMatcher.match(userDNA: userDNA, topN: 1)

        XCTAssertEqual(matches[0].bowlerName, "Glenn McGrath")
        XCTAssertEqual(matches[0].similarityPercent, 100.0, accuracy: 0.1)
    }

    func testVaasDNAMatchesVaasFirst() {
        let userDNA = FamousBowlerDatabase.vaas.dna
        let matches = BowlingDNAMatcher.match(userDNA: userDNA, topN: 1)

        XCTAssertEqual(matches[0].bowlerName, "Chaminda Vaas")
        XCTAssertEqual(matches[0].similarityPercent, 100.0, accuracy: 0.1)
    }

    func testSteynDNAMatchesSteynFirst() {
        let userDNA = FamousBowlerDatabase.steyn.dna
        let matches = BowlingDNAMatcher.match(userDNA: userDNA, topN: 1)

        XCTAssertEqual(matches[0].bowlerName, "Dale Steyn")
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

        let matches = BowlingDNAMatcher.match(userDNA: dna, topN: 1)
        XCTAssertFalse(matches.isEmpty, "Partial DNA should still produce matches")
    }

    func testEmptyDNAStillProducesMatches() {
        let dna = BowlingDNA()
        let matches = BowlingDNAMatcher.match(userDNA: dna, topN: 1)
        // With all sentinels, no valid dimensions — but should not crash
        XCTAssertEqual(matches.count, 1)
    }

    // MARK: - Honest Similarity (no inflated percentages)

    func testDifferentBowlerTypesHaveLowSimilarity() {
        // Warne (leg-spinner) vs Shoaib Akhtar (express pace) should be well below 70%
        let spinnerDNA = FamousBowlerDatabase.warne.dna
        let matches = BowlingDNAMatcher.match(userDNA: spinnerDNA, topN: 12)

        // Find the Shoaib Akhtar match
        let shoaibMatch = matches.first { $0.bowlerName == "Shoaib Akhtar" }
        XCTAssertNotNil(shoaibMatch)
        XCTAssertLessThan(shoaibMatch!.similarityPercent, 70.0,
            "A leg-spinner should NOT match 70%+ with an express fast bowler")
    }

    func testBestMatchDefaultsToTopOne() {
        // Default topN is 1
        let matches = BowlingDNAMatcher.match(userDNA: FamousBowlerDatabase.bumrah.dna)
        XCTAssertEqual(matches.count, 1)
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
            signatureTraits: ["Trait 1", "Trait 2", "Trait 3"],
            bowlerDNA: FamousBowlerDatabase.mcGrath.dna
        )
        let data = try JSONEncoder().encode(match)
        let decoded = try JSONDecoder().decode(BowlingDNAMatch.self, from: data)
        XCTAssertEqual(match, decoded)
    }

    // MARK: - Quality Snapping

    func testSnapQualityRoundsToNearestTenth() {
        XCTAssertEqual(BowlingDNA.snapQuality(0.34), 0.3, accuracy: 0.001)
        XCTAssertEqual(BowlingDNA.snapQuality(0.35), 0.4, accuracy: 0.001)
        XCTAssertEqual(BowlingDNA.snapQuality(0.78), 0.8, accuracy: 0.001)
        XCTAssertEqual(BowlingDNA.snapQuality(0.95), 1.0, accuracy: 0.001)
        XCTAssertEqual(BowlingDNA.snapQuality(0.0), 0.0, accuracy: 0.001)
        XCTAssertEqual(BowlingDNA.snapQuality(1.0), 1.0, accuracy: 0.001)
    }

    // MARK: - Average Quality

    func testAverageQualityAllPresent() {
        var dna = BowlingDNA()
        dna.runUpQuality = 0.8
        dna.gatherQuality = 0.6
        dna.deliveryStrideQuality = 0.7
        dna.releaseQuality = 0.5
        dna.followThroughQuality = 0.4
        XCTAssertEqual(dna.averageQuality!, 0.6, accuracy: 0.001)
    }

    func testAverageQualityPartial() {
        var dna = BowlingDNA()
        dna.releaseQuality = 0.8
        dna.followThroughQuality = 0.6
        XCTAssertEqual(dna.averageQuality!, 0.7, accuracy: 0.001)
    }

    func testAverageQualityNilWhenNoFields() {
        let dna = BowlingDNA()
        XCTAssertNil(dna.averageQuality)
    }

    // MARK: - Quality Dampener

    func testDampenerReducesSimilarityForLowerQualityUser() {
        // User avg 0.4, bowler avg 0.9 → ratio ~0.44
        var userDNA = FamousBowlerDatabase.mcGrath.dna
        userDNA.runUpQuality = 0.4
        userDNA.gatherQuality = 0.4
        userDNA.deliveryStrideQuality = 0.4
        userDNA.releaseQuality = 0.4
        userDNA.followThroughQuality = 0.4

        let bowlerDNA = FamousBowlerDatabase.mcGrath.dna

        let dampened = BowlingDNAMatcher.qualityDampened(
            baseSimilarity: 100.0,
            userDNA: userDNA,
            bowlerDNA: bowlerDNA
        )

        // Should be ~44% (0.4/0.9 * 100)
        XCTAssertLessThan(dampened, 50.0, "Low quality user should get dampened well below base")
        XCTAssertGreaterThan(dampened, 40.0, "Should not over-dampen")
    }

    func testDampenerDoesNotBoostAboveBase() {
        // User avg 1.0, bowler avg 0.9 → ratio capped at 1.0
        var userDNA = FamousBowlerDatabase.mcGrath.dna
        userDNA.runUpQuality = 1.0
        userDNA.gatherQuality = 1.0
        userDNA.deliveryStrideQuality = 1.0
        userDNA.releaseQuality = 1.0
        userDNA.followThroughQuality = 1.0

        let bowlerDNA = FamousBowlerDatabase.mcGrath.dna

        let dampened = BowlingDNAMatcher.qualityDampened(
            baseSimilarity: 85.0,
            userDNA: userDNA,
            bowlerDNA: bowlerDNA
        )

        XCTAssertEqual(dampened, 85.0, accuracy: 0.01, "Should not boost above base similarity")
    }

    func testDampenerPassesThroughWhenNoQuality() {
        // No quality fields → returns base unchanged
        let userDNA = BowlingDNA(armPath: .high)
        let bowlerDNA = BowlingDNA(armPath: .high)

        let dampened = BowlingDNAMatcher.qualityDampened(
            baseSimilarity: 75.0,
            userDNA: userDNA,
            bowlerDNA: bowlerDNA
        )

        XCTAssertEqual(dampened, 75.0, "No quality data → no dampening (backward compat)")
    }

    func testDampenerPassesThroughWhenOnlyUserHasQuality() {
        // Only user has quality, bowler doesn't → pass through
        var userDNA = BowlingDNA(armPath: .high)
        userDNA.releaseQuality = 0.5
        let bowlerDNA = BowlingDNA(armPath: .high)

        let dampened = BowlingDNAMatcher.qualityDampened(
            baseSimilarity: 75.0,
            userDNA: userDNA,
            bowlerDNA: bowlerDNA
        )

        XCTAssertEqual(dampened, 75.0, "Missing bowler quality → no dampening")
    }

    // MARK: - Quality Dampener Integration

    func testRecreationalBowlerGetsLowerSimilarityThanLegend() {
        // Simulate a recreational bowler with same categorical DNA as McGrath
        // but much lower execution quality
        var recreationalDNA = FamousBowlerDatabase.mcGrath.dna
        recreationalDNA.runUpQuality = 0.4
        recreationalDNA.gatherQuality = 0.3
        recreationalDNA.deliveryStrideQuality = 0.4
        recreationalDNA.releaseQuality = 0.5
        recreationalDNA.followThroughQuality = 0.3

        let matches = BowlingDNAMatcher.match(userDNA: recreationalDNA, topN: 1)
        XCTAssertFalse(matches.isEmpty)

        // With quality dampening, should be well below 100%
        XCTAssertLessThan(matches[0].similarityPercent, 55.0,
            "Recreational bowler with 0.3-0.5 quality should NOT get >55% match to an elite bowler")
    }

    func testFamousBowlerStillGets100PercentSelfMatch() {
        // Famous bowler matching themselves: quality ratio is 1.0, so no dampening
        let matches = BowlingDNAMatcher.match(userDNA: FamousBowlerDatabase.mcGrath.dna, topN: 1)
        XCTAssertEqual(matches[0].bowlerName, "Glenn McGrath")
        XCTAssertEqual(matches[0].similarityPercent, 100.0, accuracy: 0.1)
    }

    // MARK: - Backward Compatibility

    func testDNAWithoutQualityFieldsDecodesFromOldJSON() throws {
        // Simulate old JSON without quality fields
        let oldJSON = """
        {
            "runUpStride": "medium",
            "runUpSpeed": "fast",
            "armPath": "high"
        }
        """
        let data = oldJSON.data(using: .utf8)!
        let dna = try JSONDecoder().decode(BowlingDNA.self, from: data)

        XCTAssertEqual(dna.runUpStride, .medium)
        XCTAssertEqual(dna.runUpSpeed, .fast)
        XCTAssertEqual(dna.armPath, .high)
        XCTAssertNil(dna.runUpQuality, "Quality fields should be nil when absent from old JSON")
        XCTAssertNil(dna.averageQuality)
    }

    func testDNAWithQualityFieldsRoundTrips() throws {
        var dna = FamousBowlerDatabase.steyn.dna
        dna.runUpQuality = 1.0
        dna.gatherQuality = 0.9
        dna.deliveryStrideQuality = 1.0
        dna.releaseQuality = 1.0
        dna.followThroughQuality = 0.9

        let data = try JSONEncoder().encode(dna)
        let decoded = try JSONDecoder().decode(BowlingDNA.self, from: data)
        XCTAssertEqual(dna, decoded)
        XCTAssertEqual(decoded.runUpQuality, 1.0)
        XCTAssertEqual(decoded.releaseQuality, 1.0)
    }

    // MARK: - Famous Bowler Quality Scores

    func testAllFamousBowlersHaveQualityScores() {
        for bowler in FamousBowlerDatabase.allBowlers {
            let dna = bowler.dna
            XCTAssertNotNil(dna.runUpQuality, "\(bowler.name) missing runUpQuality")
            XCTAssertNotNil(dna.gatherQuality, "\(bowler.name) missing gatherQuality")
            XCTAssertNotNil(dna.deliveryStrideQuality, "\(bowler.name) missing deliveryStrideQuality")
            XCTAssertNotNil(dna.releaseQuality, "\(bowler.name) missing releaseQuality")
            XCTAssertNotNil(dna.followThroughQuality, "\(bowler.name) missing followThroughQuality")
        }
    }

    func testFamousBowlerQualityInEliteRange() {
        for bowler in FamousBowlerDatabase.allBowlers {
            let avg = bowler.dna.averageQuality!
            XCTAssertGreaterThanOrEqual(avg, 0.8,
                "\(bowler.name) average quality \(avg) is below 0.8 — famous bowlers should be elite")
            XCTAssertLessThanOrEqual(avg, 1.0,
                "\(bowler.name) average quality \(avg) exceeds 1.0")
        }
    }
}
