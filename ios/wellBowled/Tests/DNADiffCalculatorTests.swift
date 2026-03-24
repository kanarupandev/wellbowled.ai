import XCTest
@testable import wellBowled

final class DNADiffCalculatorTests: XCTestCase {

    // MARK: - Identical DNAs → all diffs = 0, all white

    func testIdenticalDNAs_allZeroDiff() {
        let dna = BowlingDNA(
            runUpStride: .medium,
            runUpSpeed: .fast,
            approachAngle: .straight,
            gatherAlignment: .semi,
            backFootContact: .braced,
            trunkLean: .slight,
            deliveryStrideLength: .normal,
            frontArmAction: .pull,
            headStability: .stable,
            armPath: .high,
            releaseHeight: .high,
            wristPosition: .behind,
            seamOrientation: .upright,
            revolutions: .medium,
            followThroughDirection: .straight,
            balanceAtFinish: .balanced
        )

        let rows = DNADiffCalculator.diff(a: dna, b: dna)
        XCTAssertFalse(rows.isEmpty)
        for row in rows {
            XCTAssertEqual(row.diffMagnitude, 0.0, accuracy: 0.001, "Row '\(row.label)' should have zero diff")
        }
    }

    // MARK: - Opposite DNAs → diffs sorted descending

    func testOppositeDNAs_sortedByDiffDescending() {
        let dnaA = BowlingDNA(
            runUpStride: .short,
            runUpSpeed: .slow,
            approachAngle: .straight,
            gatherAlignment: .frontOn,
            backFootContact: .braced,
            trunkLean: .upright,
            deliveryStrideLength: .short,
            frontArmAction: .pull,
            headStability: .stable,
            armPath: .high,
            releaseHeight: .high,
            wristPosition: .behind,
            seamOrientation: .upright,
            revolutions: .low,
            followThroughDirection: .across,
            balanceAtFinish: .balanced
        )
        let dnaB = BowlingDNA(
            runUpStride: .long,
            runUpSpeed: .explosive,
            approachAngle: .wide,
            gatherAlignment: .sideOn,
            backFootContact: .jumping,
            trunkLean: .pronounced,
            deliveryStrideLength: .overStriding,
            frontArmAction: .delayed,
            headStability: .falling,
            armPath: .sling,
            releaseHeight: .low,
            wristPosition: .sideArm,
            seamOrientation: .angled,
            revolutions: .high,
            followThroughDirection: .wide,
            balanceAtFinish: .stumbling
        )

        let rows = DNADiffCalculator.diff(a: dnaA, b: dnaB)

        // All rows should have diff > 0
        for row in rows {
            XCTAssertGreaterThan(row.diffMagnitude, 0.0, "Row '\(row.label)' should have nonzero diff")
        }

        // Should be sorted descending by diffMagnitude
        for i in 1..<rows.count {
            XCTAssertGreaterThanOrEqual(
                rows[i - 1].diffMagnitude,
                rows[i].diffMagnitude,
                "Rows should be sorted descending: '\(rows[i-1].label)' (\(rows[i-1].diffMagnitude)) >= '\(rows[i].label)' (\(rows[i].diffMagnitude))"
            )
        }
    }

    // MARK: - Nil fields → excluded from diff

    func testPartialDNA_nilFieldsExcluded() {
        let dnaA = BowlingDNA(runUpStride: .short)
        let dnaB = BowlingDNA(runUpStride: .long)

        let rows = DNADiffCalculator.diff(a: dnaA, b: dnaB)

        // Should only contain rows where BOTH sides have values
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].label, "Run-up stride")
        XCTAssertGreaterThan(rows[0].diffMagnitude, 0.0)
    }

    // MARK: - One side nil → row excluded

    func testOneSideNil_rowExcluded() {
        let dnaA = BowlingDNA(runUpStride: .short, runUpSpeed: .fast)
        let dnaB = BowlingDNA(runUpStride: .short) // runUpSpeed nil

        let rows = DNADiffCalculator.diff(a: dnaA, b: dnaB)
        let labels = rows.map(\.label)

        XCTAssertTrue(labels.contains("Run-up stride"))
        XCTAssertFalse(labels.contains("Run-up speed"), "Should not include row where one side is nil")
    }

    // MARK: - Quality fields included

    func testQualityFieldsIncluded() {
        let dnaA = BowlingDNA(
            runUpStride: .medium,
            runUpQuality: 0.8,
            gatherQuality: 0.5
        )
        let dnaB = BowlingDNA(
            runUpStride: .medium,
            runUpQuality: 0.3,
            gatherQuality: 0.5
        )

        let rows = DNADiffCalculator.diff(a: dnaA, b: dnaB)
        let qualityRows = rows.filter { $0.label.contains("quality") }

        // runUpQuality differs (0.8 vs 0.3 = 0.5 diff), gatherQuality same (0.0 diff)
        XCTAssertEqual(qualityRows.count, 2)

        let runUpQ = qualityRows.first(where: { $0.label == "Run-up quality" })
        XCTAssertNotNil(runUpQ)
        XCTAssertEqual(runUpQ!.diffMagnitude, 0.5, accuracy: 0.01)

        let gatherQ = qualityRows.first(where: { $0.label == "Gather quality" })
        XCTAssertNotNil(gatherQ)
        XCTAssertEqual(gatherQ!.diffMagnitude, 0.0, accuracy: 0.01)
    }

    // MARK: - DiffRow has correct display values

    func testDiffRowDisplayValues() {
        let dnaA = BowlingDNA(armPath: .high, releaseHeight: .medium)
        let dnaB = BowlingDNA(armPath: .sling, releaseHeight: .medium)

        let rows = DNADiffCalculator.diff(a: dnaA, b: dnaB)

        let armRow = rows.first(where: { $0.label == "Arm path" })
        XCTAssertNotNil(armRow)
        XCTAssertEqual(armRow!.valueA, "High")
        XCTAssertEqual(armRow!.valueB, "Sling")
        XCTAssertEqual(armRow!.diffMagnitude, 1.0, accuracy: 0.01) // high=0, sling=1

        let releaseRow = rows.first(where: { $0.label == "Release height" })
        XCTAssertNotNil(releaseRow)
        XCTAssertEqual(releaseRow!.valueA, "Medium")
        XCTAssertEqual(releaseRow!.valueB, "Medium")
        XCTAssertEqual(releaseRow!.diffMagnitude, 0.0, accuracy: 0.01)
    }

    // MARK: - Adjacent values have intermediate diff

    func testAdjacentValues_intermediateDiff() {
        let dnaA = BowlingDNA(runUpStride: .short)   // ordinal = 0.0
        let dnaB = BowlingDNA(runUpStride: .medium)  // ordinal = 0.5

        let rows = DNADiffCalculator.diff(a: dnaA, b: dnaB)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].diffMagnitude, 0.5, accuracy: 0.01)
    }

    // MARK: - 4-value enum diff (RunUpSpeed)

    func testFourValueEnum_correctDiff() {
        let dnaA = BowlingDNA(runUpSpeed: .slow)      // ordinal = 0.0
        let dnaB = BowlingDNA(runUpSpeed: .explosive)  // ordinal = 1.0

        let rows = DNADiffCalculator.diff(a: dnaA, b: dnaB)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].diffMagnitude, 1.0, accuracy: 0.01)
    }
}
