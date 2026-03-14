import Foundation

// MARK: - BowlingDNA — 20-Dimension Action Signature

/// Describes a bowling action across 6 phases using categorical + normalized fields.
/// All fields optional — partial DNA is valid (graceful degradation from limited video/pose data).
struct BowlingDNA: Codable, Equatable {

    // Phase 1: Run-Up (3 fields)
    var runUpStride: RunUpStrideCategory?         // short / medium / long
    var runUpSpeed: RunUpSpeed?                    // slow / moderate / fast / explosive
    var approachAngle: ApproachAngle?              // straight / angled / wide

    // Phase 2: Gather / Load (3 fields)
    var gatherAlignment: BodyAlignment?            // front-on / semi / side-on
    var backFootContact: BackFootContact?          // braced / sliding / jumping
    var trunkLean: TrunkLean?                      // upright / slight / pronounced

    // Phase 3: Delivery Stride (3 fields)
    var deliveryStrideLength: StrideLength?        // short / normal / overStriding
    var frontArmAction: FrontArmAction?            // pull / sweep / delayed
    var headStability: HeadStability?              // stable / tilted / falling

    // Phase 4: Release (5 fields — weighted 2x in matching)
    var armPath: ArmPath?                          // high / roundArm / sling
    var releaseHeight: ReleaseHeight?              // high / medium / low
    var wristPosition: WristPosition?              // behind / cocked / sideArm
    var wristOmegaNormalized: Double?              // 0..1 from MediaPipe (clamp((omega-800)/1200))
    var releaseWristYNormalized: Double?            // 0..1 from MediaPipe (Y position at release)

    // Phase 5: Seam/Spin (2 fields)
    var seamOrientation: SeamOrientation?          // upright / scrambled / angled
    var revolutions: Revolutions?                  // low / medium / high

    // Phase 6: Follow-Through (2 fields)
    var followThroughDirection: FollowThroughDir?  // across / straight / wide
    var balanceAtFinish: BalanceAtFinish?           // balanced / falling / stumbling

    // Total: 18 categorical + 2 continuous = 20 dimensions
}

// MARK: - Phase 1: Run-Up Enums

enum RunUpStrideCategory: String, Codable, CaseIterable {
    case short, medium, long
}

enum RunUpSpeed: String, Codable, CaseIterable {
    case slow, moderate, fast, explosive
}

enum ApproachAngle: String, Codable, CaseIterable {
    case straight, angled, wide
}

// MARK: - Phase 2: Gather Enums

enum BodyAlignment: String, Codable, CaseIterable {
    case frontOn = "front_on"
    case semi
    case sideOn = "side_on"
}

enum BackFootContact: String, Codable, CaseIterable {
    case braced, sliding, jumping
}

enum TrunkLean: String, Codable, CaseIterable {
    case upright, slight, pronounced
}

// MARK: - Phase 3: Delivery Stride Enums

enum StrideLength: String, Codable, CaseIterable {
    case short, normal, overStriding = "over_striding"
}

enum FrontArmAction: String, Codable, CaseIterable {
    case pull, sweep, delayed
}

enum HeadStability: String, Codable, CaseIterable {
    case stable, tilted, falling
}

// MARK: - Phase 4: Release Enums

enum ArmPath: String, Codable, CaseIterable {
    case high, roundArm = "round_arm", sling
}

enum ReleaseHeight: String, Codable, CaseIterable {
    case high, medium, low
}

enum WristPosition: String, Codable, CaseIterable {
    case behind, cocked, sideArm = "side_arm"
}

// MARK: - Phase 5: Seam/Spin Enums

enum SeamOrientation: String, Codable, CaseIterable {
    case upright, scrambled, angled
}

enum Revolutions: String, Codable, CaseIterable {
    case low, medium, high
}

// MARK: - Phase 6: Follow-Through Enums

enum FollowThroughDir: String, Codable, CaseIterable {
    case across, straight, wide
}

enum BalanceAtFinish: String, Codable, CaseIterable {
    case balanced, falling, stumbling
}

// MARK: - DNA Match Result

struct BowlingDNAMatch: Codable, Equatable, Identifiable {
    var id: String { bowlerName }
    let bowlerName: String
    let country: String
    let era: String
    let style: String
    let similarityPercent: Double     // 0-100
    let closestPhase: String          // e.g. "Release Action"
    let biggestDifference: String     // e.g. "Body alignment"
    let signatureTraits: [String]     // 3 bullet points
    let bowlerDNA: BowlingDNA         // reference bowler DNA for comparison
}
