import Foundation

// MARK: - Vector Encoder

/// Encodes a BowlingDNA into a 20-dimension Double vector for distance computation.
/// Ordinal encoding: 3-value → 0, 0.5, 1.0; 4-value → 0, 0.33, 0.67, 1.0.
/// Missing fields → -1 sentinel (excluded from distance calculation).
struct BowlingDNAVectorEncoder {

    static let dimensionCount = 20

    /// Dimension labels for human-readable output
    static let dimensionLabels: [String] = [
        // Phase 1: Run-Up
        "Run-up stride", "Run-up speed", "Approach angle",
        // Phase 2: Gather
        "Body alignment", "Back-foot contact", "Trunk lean",
        // Phase 3: Delivery Stride
        "Stride length", "Front arm action", "Head stability",
        // Phase 4: Release (weighted 2x)
        "Arm path", "Release height", "Wrist position", "Wrist angular velocity", "Release wrist height",
        // Phase 5: Seam/Spin
        "Seam orientation", "Revolutions",
        // Phase 6: Follow-Through
        "Follow-through direction", "Balance at finish",
        // Padding to 20
        "Reserved 1", "Reserved 2"
    ]

    /// Phase name for each dimension (for "closest phase" output)
    static let dimensionPhases: [String] = [
        "Run-Up", "Run-Up", "Run-Up",
        "Gather", "Gather", "Gather",
        "Delivery Stride", "Delivery Stride", "Delivery Stride",
        "Release", "Release", "Release", "Release", "Release",
        "Seam/Spin", "Seam/Spin",
        "Follow-Through", "Follow-Through",
        "Reserved", "Reserved"
    ]

    /// Per-dimension weights — tuned for "naked eye" similarity.
    /// What makes two bowlers look alike to a cricket watcher?
    ///
    /// 3.0x  Action identity — arm path, body alignment
    /// 2.5x  Strongly distinctive — release height, run-up speed, follow-through dir
    /// 2.0x  Clearly visible — stride length, front arm, wrist pos, balance
    /// 1.5x  Noticeable — run-up stride, head stability, trunk lean, revolutions
    /// 1.0x  Subtle — back-foot, approach angle, seam, wrist omega
    /// 0.75x Derived — release wrist Y (correlated with arm path)
    static let weights: [Double] = [
        1.5, 2.5, 1.0,                    // Run-Up: stride, speed, approach angle
        3.0, 1.0, 1.5,                    // Gather: alignment, back-foot, trunk lean
        2.0, 2.0, 1.5,                    // Delivery Stride: length, front arm, head stability
        3.0, 2.5, 2.0, 1.0, 0.75,         // Release: arm path, height, wrist pos, omega, wristY
        1.0, 1.5,                          // Seam/Spin: orientation, revolutions
        2.5, 2.0,                          // Follow-Through: direction, balance
        0.0, 0.0                           // Reserved (ignored)
    ]

    private static let sentinel: Double = -1.0

    static func encode(_ dna: BowlingDNA) -> [Double] {
        var v = [Double](repeating: sentinel, count: dimensionCount)

        // Phase 1: Run-Up
        v[0] = ordinal3(dna.runUpStride)
        v[1] = ordinal4(dna.runUpSpeed)
        v[2] = ordinal3(dna.approachAngle)

        // Phase 2: Gather
        v[3] = ordinal3(dna.gatherAlignment)
        v[4] = ordinal3(dna.backFootContact)
        v[5] = ordinal3(dna.trunkLean)

        // Phase 3: Delivery Stride
        v[6] = ordinal3(dna.deliveryStrideLength)
        v[7] = ordinal3(dna.frontArmAction)
        v[8] = ordinal3(dna.headStability)

        // Phase 4: Release
        v[9] = ordinal3(dna.armPath)
        v[10] = ordinal3(dna.releaseHeight)
        v[11] = ordinal3(dna.wristPosition)
        v[12] = dna.wristOmegaNormalized ?? sentinel
        v[13] = dna.releaseWristYNormalized ?? sentinel

        // Phase 5: Seam/Spin
        v[14] = ordinal3(dna.seamOrientation)
        v[15] = ordinal3(dna.revolutions)

        // Phase 6: Follow-Through
        v[16] = ordinal3(dna.followThroughDirection)
        v[17] = ordinal3(dna.balanceAtFinish)

        // Reserved
        v[18] = sentinel
        v[19] = sentinel

        return v
    }

    // MARK: - Ordinal Encoding Helpers

    /// 3-value enum → 0.0, 0.5, 1.0
    private static func ordinal3<T: CaseIterable & Equatable>(_ value: T?) -> Double {
        guard let value else { return sentinel }
        let all = Array(T.allCases)
        guard let idx = all.firstIndex(of: value) else { return sentinel }
        let position = all.distance(from: all.startIndex, to: idx)
        switch all.count {
        case 1: return 0.5
        case 2: return position == 0 ? 0.0 : 1.0
        case 3: return [0.0, 0.5, 1.0][position]
        default: return Double(position) / Double(all.count - 1)
        }
    }

    /// 4-value enum → 0.0, 0.33, 0.67, 1.0
    private static func ordinal4<T: CaseIterable & Equatable>(_ value: T?) -> Double {
        guard let value else { return sentinel }
        let all = Array(T.allCases)
        guard let idx = all.firstIndex(of: value) else { return sentinel }
        let position = all.distance(from: all.startIndex, to: idx)
        guard all.count > 1 else { return 0.5 }
        return Double(position) / Double(all.count - 1)
    }
}

// MARK: - Matcher

struct BowlingDNAMatcher {

    /// Pre-encoded vectors for all famous bowlers (computed once, reused for every match).
    private static let cachedBowlerVectors: [(bowler: FamousBowlerProfile, vector: [Double])] = {
        FamousBowlerDatabase.allBowlers.map { ($0, BowlingDNAVectorEncoder.encode($0.dna)) }
    }()

    /// Match user DNA against the famous bowler database.
    /// Returns top-N matches sorted by similarity (highest first).
    /// Quality dampener ensures recreational bowlers don't get inflated matches.
    static func match(userDNA: BowlingDNA, topN: Int = 1) -> [BowlingDNAMatch] {
        let userVec = BowlingDNAVectorEncoder.encode(userDNA)

        var results: [(bowler: FamousBowlerProfile, similarity: Double, closestPhaseIdx: Int, biggestDiffIdx: Int)] = []

        for (bowler, bowlerVec) in cachedBowlerVectors {
            let (normalisedDistance, closestIdx, biggestIdx) = weightedEuclidean(userVec, bowlerVec)

            // normalisedDistance is 0…1 (0 = identical, 1 = maximally different)
            let baseSimilarity = max(0, min(100, (1.0 - normalisedDistance) * 100))
            let similarity = qualityDampened(
                baseSimilarity: baseSimilarity,
                userDNA: userDNA,
                bowlerDNA: bowler.dna
            )
            results.append((bowler, similarity, closestIdx, biggestIdx))
        }

        results.sort { $0.similarity > $1.similarity }
        let top = results.prefix(topN)

        return top.map { item in
            BowlingDNAMatch(
                bowlerName: item.bowler.name,
                country: item.bowler.country,
                era: item.bowler.era,
                style: item.bowler.style,
                similarityPercent: (item.similarity * 10).rounded() / 10,
                closestPhase: BowlingDNAVectorEncoder.dimensionPhases[item.closestPhaseIdx],
                biggestDifference: BowlingDNAVectorEncoder.dimensionLabels[item.biggestDiffIdx],
                signatureTraits: item.bowler.signatureTraits,
                bowlerDNA: item.bowler.dna
            )
        }
    }

    // MARK: - Distance Calculation

    /// Returns (normalised distance 0…1, index of closest dimension, index of biggest difference).
    /// Skips dimensions where either vector has sentinel (-1).
    /// Distance is normalised against the theoretical maximum so 0 = identical, 1 = maximally different.
    private static func weightedEuclidean(_ a: [Double], _ b: [Double]) -> (Double, Int, Int) {
        var sumSq = 0.0
        var maxSumSq = 0.0
        var minDiff = Double.infinity
        var maxDiff = 0.0
        var closestIdx = 0
        var biggestIdx = 0
        var validDims = 0

        for i in 0..<min(a.count, b.count) {
            let w = BowlingDNAVectorEncoder.weights[i]
            guard w > 0, a[i] >= 0, b[i] >= 0 else { continue }

            let diff = abs(a[i] - b[i])
            let weighted = diff * w
            sumSq += weighted * weighted
            // Max possible diff per dimension is 1.0 (values are in [0,1])
            maxSumSq += w * w
            validDims += 1

            if diff < minDiff {
                minDiff = diff
                closestIdx = i
            }
            if diff > maxDiff {
                maxDiff = diff
                biggestIdx = i
            }
        }

        guard validDims > 0, maxSumSq > 0 else { return (Double.infinity, 0, 0) }

        // Normalise distance to [0, 1] using theoretical maximum for the valid dimensions
        let distance = sqrt(sumSq / Double(validDims))
        let theoreticalMax = sqrt(maxSumSq / Double(validDims))
        let normalised = distance / theoreticalMax
        return (normalised, closestIdx, biggestIdx)
    }

    // MARK: - Quality Dampener

    /// Adjusts base similarity by execution quality ratio.
    /// If the user's average quality is lower than the bowler's, similarity is dampened.
    /// Formula: adjustedSimilarity = base × min(1, userAvg / bowlerAvg)
    /// If either side has no quality data, returns base unchanged (backward compatible).
    static func qualityDampened(baseSimilarity: Double, userDNA: BowlingDNA, bowlerDNA: BowlingDNA) -> Double {
        guard let userAvg = userDNA.averageQuality,
              let bowlerAvg = bowlerDNA.averageQuality,
              bowlerAvg > 0 else {
            return baseSimilarity
        }
        let ratio = min(1.0, userAvg / bowlerAvg)
        return baseSimilarity * ratio
    }
}
