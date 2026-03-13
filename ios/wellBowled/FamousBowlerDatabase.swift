import Foundation

// MARK: - Famous Bowler Profile

struct FamousBowlerProfile {
    let name: String
    let country: String
    let era: String
    let style: String
    let dna: BowlingDNA
    let signatureTraits: [String]
}

// MARK: - Database (12 Bowlers)

enum FamousBowlerDatabase {

    static let allBowlers: [FamousBowlerProfile] = [
        mcGrath, akram, warne, akhtar, muralitharan,
        anderson, starc, ashwin, marshall, bumrah,
        vaas, steyn
    ]

    // 1. Glenn McGrath (AUS) — Classic side-on seam
    static let mcGrath = FamousBowlerProfile(
        name: "Glenn McGrath",
        country: "AUS",
        era: "1993-2007",
        style: "Right-arm fast-medium",
        dna: BowlingDNA(
            runUpStride: .medium, runUpSpeed: .moderate, approachAngle: .straight,
            gatherAlignment: .sideOn, backFootContact: .braced, trunkLean: .slight,
            deliveryStrideLength: .normal, frontArmAction: .pull, headStability: .stable,
            armPath: .high, releaseHeight: .high, wristPosition: .behind,
            wristOmegaNormalized: 0.5, releaseWristYNormalized: 0.3,
            seamOrientation: .upright, revolutions: .low,
            followThroughDirection: .straight, balanceAtFinish: .balanced
        ),
        signatureTraits: [
            "Metronomic line and length — relentless accuracy",
            "Classic high-arm side-on action with textbook seam position",
            "Minimal wasted energy — pure efficiency over brute force"
        ]
    )

    // 2. Wasim Akram (PAK) — Left-arm swing/sling
    static let akram = FamousBowlerProfile(
        name: "Wasim Akram",
        country: "PAK",
        era: "1985-2003",
        style: "Left-arm fast",
        dna: BowlingDNA(
            runUpStride: .medium, runUpSpeed: .fast, approachAngle: .angled,
            gatherAlignment: .semi, backFootContact: .sliding, trunkLean: .slight,
            deliveryStrideLength: .normal, frontArmAction: .sweep, headStability: .stable,
            armPath: .sling, releaseHeight: .medium, wristPosition: .cocked,
            wristOmegaNormalized: 0.75, releaseWristYNormalized: 0.5,
            seamOrientation: .angled, revolutions: .medium,
            followThroughDirection: .across, balanceAtFinish: .balanced
        ),
        signatureTraits: [
            "Devastating reverse swing at pace — could move it both ways",
            "Slingy action generating late movement invisible to batsmen",
            "Left-arm angle creating natural variation off the pitch"
        ]
    )

    // 3. Shane Warne (AUS) — Leg-spin
    static let warne = FamousBowlerProfile(
        name: "Shane Warne",
        country: "AUS",
        era: "1992-2007",
        style: "Right-arm leg-spin",
        dna: BowlingDNA(
            runUpStride: .short, runUpSpeed: .slow, approachAngle: .straight,
            gatherAlignment: .frontOn, backFootContact: .braced, trunkLean: .upright,
            deliveryStrideLength: .short, frontArmAction: .delayed, headStability: .stable,
            armPath: .roundArm, releaseHeight: .medium, wristPosition: .cocked,
            wristOmegaNormalized: 0.2, releaseWristYNormalized: 0.6,
            seamOrientation: .angled, revolutions: .high,
            followThroughDirection: .across, balanceAtFinish: .balanced
        ),
        signatureTraits: [
            "Prodigious leg-spin with massive revolutions on the ball",
            "Round-arm action disguising variations (flipper, slider, googly)",
            "Supreme accuracy despite being a wrist spinner"
        ]
    )

    // 4. Shoaib Akhtar (PAK) — Express pace
    static let akhtar = FamousBowlerProfile(
        name: "Shoaib Akhtar",
        country: "PAK",
        era: "1997-2011",
        style: "Right-arm express fast",
        dna: BowlingDNA(
            runUpStride: .long, runUpSpeed: .explosive, approachAngle: .wide,
            gatherAlignment: .frontOn, backFootContact: .jumping, trunkLean: .pronounced,
            deliveryStrideLength: .overStriding, frontArmAction: .sweep, headStability: .falling,
            armPath: .sling, releaseHeight: .high, wristPosition: .behind,
            wristOmegaNormalized: 1.0, releaseWristYNormalized: 0.25,
            seamOrientation: .scrambled, revolutions: .low,
            followThroughDirection: .wide, balanceAtFinish: .stumbling
        ),
        signatureTraits: [
            "Fastest recorded delivery in cricket (161.3 kph)",
            "Explosive long run-up with immense physical effort",
            "Front-on hyper-extension generating raw pace over control"
        ]
    )

    // 5. Muttiah Muralitharan (SL) — Off-spin/doosra
    static let muralitharan = FamousBowlerProfile(
        name: "Muttiah Muralitharan",
        country: "SL",
        era: "1992-2010",
        style: "Right-arm off-spin",
        dna: BowlingDNA(
            runUpStride: .short, runUpSpeed: .slow, approachAngle: .straight,
            gatherAlignment: .frontOn, backFootContact: .braced, trunkLean: .upright,
            deliveryStrideLength: .short, frontArmAction: .delayed, headStability: .stable,
            armPath: .roundArm, releaseHeight: .medium, wristPosition: .cocked,
            wristOmegaNormalized: 0.15, releaseWristYNormalized: 0.55,
            seamOrientation: .angled, revolutions: .high,
            followThroughDirection: .across, balanceAtFinish: .balanced
        ),
        signatureTraits: [
            "Most Test wickets ever (800) with unique flexion-based action",
            "Doosra delivery spinning away from right-handers",
            "Extraordinary wrist and finger revolutions from a side-on release"
        ]
    )

    // 6. James Anderson (ENG) — Swing
    static let anderson = FamousBowlerProfile(
        name: "James Anderson",
        country: "ENG",
        era: "2003-2024",
        style: "Right-arm fast-medium",
        dna: BowlingDNA(
            runUpStride: .medium, runUpSpeed: .moderate, approachAngle: .angled,
            gatherAlignment: .sideOn, backFootContact: .braced, trunkLean: .slight,
            deliveryStrideLength: .normal, frontArmAction: .pull, headStability: .stable,
            armPath: .high, releaseHeight: .high, wristPosition: .behind,
            wristOmegaNormalized: 0.45, releaseWristYNormalized: 0.3,
            seamOrientation: .upright, revolutions: .low,
            followThroughDirection: .straight, balanceAtFinish: .balanced
        ),
        signatureTraits: [
            "Master of swing — conventional and reverse at will",
            "Smooth side-on action with impeccable seam position",
            "Longevity through efficiency — adapted pace for 20+ years"
        ]
    )

    // 7. Mitchell Starc (AUS) — Left-arm fast
    static let starc = FamousBowlerProfile(
        name: "Mitchell Starc",
        country: "AUS",
        era: "2011-present",
        style: "Left-arm fast",
        dna: BowlingDNA(
            runUpStride: .long, runUpSpeed: .fast, approachAngle: .angled,
            gatherAlignment: .semi, backFootContact: .jumping, trunkLean: .slight,
            deliveryStrideLength: .normal, frontArmAction: .pull, headStability: .tilted,
            armPath: .high, releaseHeight: .high, wristPosition: .behind,
            wristOmegaNormalized: 0.8, releaseWristYNormalized: 0.25,
            seamOrientation: .upright, revolutions: .low,
            followThroughDirection: .across, balanceAtFinish: .falling
        ),
        signatureTraits: [
            "Devastating inswinging yorker — best in white-ball cricket",
            "Left-arm pace with genuine speed (150+ kph regularly)",
            "High release point creating steep bounce and movement"
        ]
    )

    // 8. R Ashwin (IND) — Off-spin/carrom
    static let ashwin = FamousBowlerProfile(
        name: "R Ashwin",
        country: "IND",
        era: "2011-2025",
        style: "Right-arm off-spin",
        dna: BowlingDNA(
            runUpStride: .short, runUpSpeed: .slow, approachAngle: .straight,
            gatherAlignment: .frontOn, backFootContact: .braced, trunkLean: .upright,
            deliveryStrideLength: .short, frontArmAction: .delayed, headStability: .stable,
            armPath: .high, releaseHeight: .high, wristPosition: .cocked,
            wristOmegaNormalized: 0.2, releaseWristYNormalized: 0.45,
            seamOrientation: .angled, revolutions: .medium,
            followThroughDirection: .straight, balanceAtFinish: .balanced
        ),
        signatureTraits: [
            "Master of carrom ball and multiple variations from same action",
            "High-arm off-spin with drift and dip from above head height",
            "Tactical bowler — changes pace, angle, and trajectory constantly"
        ]
    )

    // 9. Malcolm Marshall (WI) — Compact fast
    static let marshall = FamousBowlerProfile(
        name: "Malcolm Marshall",
        country: "WI",
        era: "1978-1991",
        style: "Right-arm fast",
        dna: BowlingDNA(
            runUpStride: .short, runUpSpeed: .fast, approachAngle: .straight,
            gatherAlignment: .sideOn, backFootContact: .braced, trunkLean: .slight,
            deliveryStrideLength: .normal, frontArmAction: .pull, headStability: .stable,
            armPath: .sling, releaseHeight: .medium, wristPosition: .cocked,
            wristOmegaNormalized: 0.85, releaseWristYNormalized: 0.4,
            seamOrientation: .upright, revolutions: .low,
            followThroughDirection: .straight, balanceAtFinish: .balanced
        ),
        signatureTraits: [
            "Compact run-up generating frightening pace from minimal effort",
            "Skiddy slingy action making the ball arrive faster than expected",
            "Lethal outswinger complemented by sharp short-pitched bowling"
        ]
    )

    // 10. Jasprit Bumrah (IND) — Unorthodox fast
    static let bumrah = FamousBowlerProfile(
        name: "Jasprit Bumrah",
        country: "IND",
        era: "2016-present",
        style: "Right-arm fast",
        dna: BowlingDNA(
            runUpStride: .short, runUpSpeed: .moderate, approachAngle: .angled,
            gatherAlignment: .frontOn, backFootContact: .braced, trunkLean: .pronounced,
            deliveryStrideLength: .short, frontArmAction: .sweep, headStability: .tilted,
            armPath: .sling, releaseHeight: .low, wristPosition: .sideArm,
            wristOmegaNormalized: 0.8, releaseWristYNormalized: 0.55,
            seamOrientation: .upright, revolutions: .low,
            followThroughDirection: .across, balanceAtFinish: .falling
        ),
        signatureTraits: [
            "Unorthodox sling action — virtually impossible to pick up early",
            "Short run-up but generates 145+ kph through hyper-extension",
            "Deadly yorker specialist with late outswing from nowhere"
        ]
    )

    // 11. Chaminda Vaas (SL) — Left-arm swing fast-medium
    static let vaas = FamousBowlerProfile(
        name: "Chaminda Vaas",
        country: "SL",
        era: "1994-2009",
        style: "Left-arm fast-medium",
        dna: BowlingDNA(
            runUpStride: .medium, runUpSpeed: .fast, approachAngle: .angled,
            gatherAlignment: .sideOn, backFootContact: .braced, trunkLean: .slight,
            deliveryStrideLength: .normal, frontArmAction: .pull, headStability: .stable,
            armPath: .high, releaseHeight: .high, wristPosition: .behind,
            wristOmegaNormalized: 0.6, releaseWristYNormalized: 0.34,
            seamOrientation: .upright, revolutions: .low,
            followThroughDirection: .straight, balanceAtFinish: .balanced
        ),
        signatureTraits: [
            "Elite left-arm swing control with relentless line and length",
            "Compact, repeatable action built for discipline and seam position",
            "New-ball threat with natural angle into right-handers"
        ]
    )

    // 12. Dale Steyn (SA) — Right-arm fast
    static let steyn = FamousBowlerProfile(
        name: "Dale Steyn",
        country: "SA",
        era: "2004-2020",
        style: "Right-arm fast",
        dna: BowlingDNA(
            runUpStride: .long, runUpSpeed: .explosive, approachAngle: .angled,
            gatherAlignment: .sideOn, backFootContact: .jumping, trunkLean: .slight,
            deliveryStrideLength: .normal, frontArmAction: .pull, headStability: .stable,
            armPath: .high, releaseHeight: .high, wristPosition: .behind,
            wristOmegaNormalized: 0.9, releaseWristYNormalized: 0.28,
            seamOrientation: .upright, revolutions: .low,
            followThroughDirection: .straight, balanceAtFinish: .balanced
        ),
        signatureTraits: [
            "Explosive high-pace action with late outswing at full speed",
            "Classical seam position enabling movement in all conditions",
            "Aggressive strike bowler rhythm with relentless attacking intent"
        ]
    )
}
