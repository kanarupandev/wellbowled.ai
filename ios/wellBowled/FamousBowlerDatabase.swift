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

// MARK: - Database (103 Bowlers)

enum FamousBowlerDatabase {

    static let allBowlers: [FamousBowlerProfile] = [
        // === EXISTING 12 ===
        mcGrath, akram, warne, akhtar, muralitharan,
        anderson, starc, ashwin, marshall, bumrah,
        vaas, steyn,
        // === AUSTRALIA ===
        lee, johnson, gillespie, thomson, hazlewood, cummins,
        siddle, ryanHarris, mcdermott, alderman, mervHughes, lillee,
        // === ENGLAND ===
        trueman, botham, willis, gough, harmison, flintoff,
        hoggard, snow, larwood, tyson, bedser, statham,
        woakes, wood, archer,
        // === WEST INDIES ===
        ambrose, walsh, garner, holding, roberts,
        wesHall, griffith, bishop, roach, gabriel,
        taylor, edwards, patterson, dottin,
        // === PAKISTAN ===
        younis, imranKhan, amir, asif, shaheen, naseem,
        umarGul, aaqibJaved, fazalMahmood,
        // === SOUTH AFRICA ===
        donald, pollock, ntini, rabada, morkel,
        philander, nortje, ismail, kapp, khaka,
        // === NEW ZEALAND ===
        hadlee, boult, southee, bond, wagner,
        chrisMartin, jamieson, mattHenry, morrison, tahuhu,
        // === SRI LANKA ===
        malinga,
        // === INDIA ===
        kapilDev, srinath, zaheerKhan, shami, ishant,
        umeshYadav, bhuvneshwar, jhulanGoswami,
        renukaSingh, poojaVastrakar,
        // === ZIMBABWE ===
        streak,
        // === WOMEN (additional) ===
        sciverBrunt, shrubsole, perry, schutt,
        darcieBrown, dianaBaig, fatimaSana,
        issyWong, vlaeminck
    ]

    // ============================================================
    // MARK: - EXISTING PROFILES (preserved exactly)
    // ============================================================

    // 1. Glenn McGrath (AUS)
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
            followThroughDirection: .straight, balanceAtFinish: .balanced,
            runUpQuality: 0.9, gatherQuality: 1.0, deliveryStrideQuality: 0.9,
            releaseQuality: 1.0, followThroughQuality: 0.9
        ),
        signatureTraits: [
            "Metronomic line and length — relentless accuracy",
            "Classic high-arm side-on action with textbook seam position",
            "Minimal wasted energy — pure efficiency over brute force"
        ]
    )

    // 2. Wasim Akram (PAK)
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
            followThroughDirection: .across, balanceAtFinish: .balanced,
            runUpQuality: 0.9, gatherQuality: 0.9, deliveryStrideQuality: 0.9,
            releaseQuality: 1.0, followThroughQuality: 0.9
        ),
        signatureTraits: [
            "Devastating reverse swing at pace — could move it both ways",
            "Slingy action generating late movement invisible to batsmen",
            "Left-arm angle creating natural variation off the pitch"
        ]
    )

    // 3. Shane Warne (AUS)
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
            followThroughDirection: .across, balanceAtFinish: .balanced,
            runUpQuality: 0.9, gatherQuality: 0.9, deliveryStrideQuality: 0.8,
            releaseQuality: 1.0, followThroughQuality: 0.9
        ),
        signatureTraits: [
            "Prodigious leg-spin with massive revolutions on the ball",
            "Round-arm action disguising variations (flipper, slider, googly)",
            "Supreme accuracy despite being a wrist spinner"
        ]
    )

    // 4. Shoaib Akhtar (PAK)
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
            followThroughDirection: .wide, balanceAtFinish: .stumbling,
            runUpQuality: 1.0, gatherQuality: 0.9, deliveryStrideQuality: 0.9,
            releaseQuality: 0.9, followThroughQuality: 0.8
        ),
        signatureTraits: [
            "Fastest recorded delivery in cricket (161.3 kph)",
            "Explosive long run-up with immense physical effort",
            "Front-on hyper-extension generating raw pace over control"
        ]
    )

    // 5. Muttiah Muralitharan (SL)
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
            followThroughDirection: .across, balanceAtFinish: .balanced,
            runUpQuality: 0.8, gatherQuality: 0.9, deliveryStrideQuality: 0.8,
            releaseQuality: 1.0, followThroughQuality: 0.9
        ),
        signatureTraits: [
            "Most Test wickets ever (800) with unique flexion-based action",
            "Doosra delivery spinning away from right-handers",
            "Extraordinary wrist and finger revolutions from a side-on release"
        ]
    )

    // 6. James Anderson (ENG)
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
            followThroughDirection: .straight, balanceAtFinish: .balanced,
            runUpQuality: 0.9, gatherQuality: 0.9, deliveryStrideQuality: 0.9,
            releaseQuality: 1.0, followThroughQuality: 0.9
        ),
        signatureTraits: [
            "Master of swing — conventional and reverse at will",
            "Smooth side-on action with impeccable seam position",
            "Longevity through efficiency — adapted pace for 20+ years"
        ]
    )

    // 7. Mitchell Starc (AUS)
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
            followThroughDirection: .across, balanceAtFinish: .falling,
            runUpQuality: 0.9, gatherQuality: 0.9, deliveryStrideQuality: 0.9,
            releaseQuality: 0.9, followThroughQuality: 0.8
        ),
        signatureTraits: [
            "Devastating inswinging yorker — best in white-ball cricket",
            "Left-arm pace with genuine speed (150+ kph regularly)",
            "High release point creating steep bounce and movement"
        ]
    )

    // 8. R Ashwin (IND)
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
            followThroughDirection: .straight, balanceAtFinish: .balanced,
            runUpQuality: 0.8, gatherQuality: 0.9, deliveryStrideQuality: 0.8,
            releaseQuality: 0.9, followThroughQuality: 0.9
        ),
        signatureTraits: [
            "Master of carrom ball and multiple variations from same action",
            "High-arm off-spin with drift and dip from above head height",
            "Tactical bowler — changes pace, angle, and trajectory constantly"
        ]
    )

    // 9. Malcolm Marshall (WI)
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
            followThroughDirection: .straight, balanceAtFinish: .balanced,
            runUpQuality: 0.9, gatherQuality: 1.0, deliveryStrideQuality: 0.9,
            releaseQuality: 1.0, followThroughQuality: 0.9
        ),
        signatureTraits: [
            "Compact run-up generating frightening pace from minimal effort",
            "Skiddy slingy action making the ball arrive faster than expected",
            "Lethal outswinger complemented by sharp short-pitched bowling"
        ]
    )

    // 10. Jasprit Bumrah (IND)
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
            followThroughDirection: .across, balanceAtFinish: .falling,
            runUpQuality: 0.8, gatherQuality: 0.9, deliveryStrideQuality: 0.9,
            releaseQuality: 1.0, followThroughQuality: 0.8
        ),
        signatureTraits: [
            "Unorthodox sling action — virtually impossible to pick up early",
            "Short run-up but generates 145+ kph through hyper-extension",
            "Deadly yorker specialist with late outswing from nowhere"
        ]
    )

    // 11. Chaminda Vaas (SL)
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
            followThroughDirection: .straight, balanceAtFinish: .balanced,
            runUpQuality: 0.9, gatherQuality: 0.9, deliveryStrideQuality: 0.9,
            releaseQuality: 0.9, followThroughQuality: 0.9
        ),
        signatureTraits: [
            "Elite left-arm swing control with relentless line and length",
            "Compact, repeatable action built for discipline and seam position",
            "New-ball threat with natural angle into right-handers"
        ]
    )

    // 12. Dale Steyn (SA)
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
            followThroughDirection: .straight, balanceAtFinish: .balanced,
            runUpQuality: 1.0, gatherQuality: 0.9, deliveryStrideQuality: 1.0,
            releaseQuality: 1.0, followThroughQuality: 0.9
        ),
        signatureTraits: [
            "Explosive high-pace action with late outswing at full speed",
            "Classical seam position enabling movement in all conditions",
            "Aggressive strike bowler rhythm with relentless attacking intent"
        ]
    )

    // ============================================================
    // MARK: - AUSTRALIA
    // ============================================================

    static let lee = FamousBowlerProfile(
        name: "Brett Lee",
        country: "AUS",
        era: "1999-2012",
        style: "Right-arm fast",
        dna: BowlingDNA(
            runUpStride: .long, runUpSpeed: .explosive, approachAngle: .straight,
            gatherAlignment: .frontOn, backFootContact: .jumping, trunkLean: .slight,
            deliveryStrideLength: .normal, frontArmAction: .pull, headStability: .tilted,
            armPath: .high, releaseHeight: .high, wristPosition: .behind,
            wristOmegaNormalized: 0.9, releaseWristYNormalized: 0.28,
            seamOrientation: .upright, revolutions: .low,
            followThroughDirection: .straight, balanceAtFinish: .falling,
            runUpQuality: 0.9, gatherQuality: 0.9, deliveryStrideQuality: 0.9,
            releaseQuality: 0.9, followThroughQuality: 0.9
        ),
        signatureTraits: [
            "Explosive pace from front-on action regularly clocking 150+ kph",
            "Trademark bouncer and yorker combination at extreme speed",
            "Athletic and dynamic follow-through with full commitment"
        ]
    )

    static let johnson = FamousBowlerProfile(
        name: "Mitchell Johnson",
        country: "AUS",
        era: "2005-2015",
        style: "Left-arm fast",
        dna: BowlingDNA(
            runUpStride: .long, runUpSpeed: .explosive, approachAngle: .angled,
            gatherAlignment: .semi, backFootContact: .jumping, trunkLean: .pronounced,
            deliveryStrideLength: .overStriding, frontArmAction: .sweep, headStability: .falling,
            armPath: .sling, releaseHeight: .medium, wristPosition: .behind,
            wristOmegaNormalized: 0.9, releaseWristYNormalized: 0.4,
            seamOrientation: .scrambled, revolutions: .low,
            followThroughDirection: .wide, balanceAtFinish: .stumbling,
            runUpQuality: 0.9, gatherQuality: 0.8, deliveryStrideQuality: 0.9,
            releaseQuality: 0.9, followThroughQuality: 0.8
        ),
        signatureTraits: [
            "Devastating left-arm thunderbolts with slingy action at 150+ kph",
            "Unpredictable angle and bounce terrorising batting lineups",
            "2013-14 Ashes demolition — the most feared spell in modern cricket"
        ]
    )

    static let gillespie = FamousBowlerProfile(
        name: "Jason Gillespie",
        country: "AUS",
        era: "1996-2006",
        style: "Right-arm fast",
        dna: BowlingDNA(
            runUpStride: .long, runUpSpeed: .fast, approachAngle: .straight,
            gatherAlignment: .sideOn, backFootContact: .braced, trunkLean: .slight,
            deliveryStrideLength: .normal, frontArmAction: .pull, headStability: .stable,
            armPath: .high, releaseHeight: .high, wristPosition: .behind,
            wristOmegaNormalized: 0.75, releaseWristYNormalized: 0.3,
            seamOrientation: .upright, revolutions: .low,
            followThroughDirection: .straight, balanceAtFinish: .balanced,
            runUpQuality: 0.9, gatherQuality: 0.9, deliveryStrideQuality: 0.9,
            releaseQuality: 0.9, followThroughQuality: 0.9
        ),
        signatureTraits: [
            "Tall seamer with classical side-on action and bounce",
            "Reliable workhorse complementing McGrath and Warne",
            "Consistent seam position extracting movement off any surface"
        ]
    )

    static let thomson = FamousBowlerProfile(
        name: "Jeff Thomson",
        country: "AUS",
        era: "1972-1985",
        style: "Right-arm express fast",
        dna: BowlingDNA(
            runUpStride: .long, runUpSpeed: .explosive, approachAngle: .wide,
            gatherAlignment: .frontOn, backFootContact: .jumping, trunkLean: .pronounced,
            deliveryStrideLength: .overStriding, frontArmAction: .sweep, headStability: .falling,
            armPath: .sling, releaseHeight: .medium, wristPosition: .sideArm,
            wristOmegaNormalized: 0.95, releaseWristYNormalized: 0.45,
            seamOrientation: .scrambled, revolutions: .low,
            followThroughDirection: .wide, balanceAtFinish: .stumbling,
            runUpQuality: 1.0, gatherQuality: 0.8, deliveryStrideQuality: 0.9,
            releaseQuality: 0.9, followThroughQuality: 0.8
        ),
        signatureTraits: [
            "Catapult sling action generating ferocious pace from the hip",
            "One of the fastest bowlers ever — recorded at 160+ kph",
            "Unorthodox javelin-throw delivery stride terrifying batsmen"
        ]
    )

    static let hazlewood = FamousBowlerProfile(
        name: "Josh Hazlewood",
        country: "AUS",
        era: "2014-present",
        style: "Right-arm fast-medium",
        dna: BowlingDNA(
            runUpStride: .medium, runUpSpeed: .moderate, approachAngle: .straight,
            gatherAlignment: .sideOn, backFootContact: .braced, trunkLean: .slight,
            deliveryStrideLength: .normal, frontArmAction: .pull, headStability: .stable,
            armPath: .high, releaseHeight: .high, wristPosition: .behind,
            wristOmegaNormalized: 0.55, releaseWristYNormalized: 0.28,
            seamOrientation: .upright, revolutions: .low,
            followThroughDirection: .straight, balanceAtFinish: .balanced,
            runUpQuality: 0.9, gatherQuality: 0.9, deliveryStrideQuality: 0.9,
            releaseQuality: 0.9, followThroughQuality: 0.9
        ),
        signatureTraits: [
            "McGrath-like accuracy from towering height with steep bounce",
            "Immaculate seam position extracting movement on any surface",
            "Patient, relentless probing on fourth-stump corridor"
        ]
    )

    static let cummins = FamousBowlerProfile(
        name: "Pat Cummins",
        country: "AUS",
        era: "2011-present",
        style: "Right-arm fast",
        dna: BowlingDNA(
            runUpStride: .medium, runUpSpeed: .fast, approachAngle: .straight,
            gatherAlignment: .sideOn, backFootContact: .jumping, trunkLean: .slight,
            deliveryStrideLength: .normal, frontArmAction: .pull, headStability: .stable,
            armPath: .high, releaseHeight: .high, wristPosition: .behind,
            wristOmegaNormalized: 0.8, releaseWristYNormalized: 0.28,
            seamOrientation: .upright, revolutions: .low,
            followThroughDirection: .straight, balanceAtFinish: .balanced,
            runUpQuality: 0.9, gatherQuality: 0.9, deliveryStrideQuality: 0.9,
            releaseQuality: 0.9, followThroughQuality: 0.9
        ),
        signatureTraits: [
            "Genuine pace from classical high-arm side-on action",
            "Elite athlete combining 145+ kph with pinpoint control",
            "Brilliant bouncer and change of pace from same smooth action"
        ]
    )

    static let siddle = FamousBowlerProfile(
        name: "Peter Siddle",
        country: "AUS",
        era: "2008-2019",
        style: "Right-arm fast-medium",
        dna: BowlingDNA(
            runUpStride: .medium, runUpSpeed: .fast, approachAngle: .straight,
            gatherAlignment: .sideOn, backFootContact: .braced, trunkLean: .slight,
            deliveryStrideLength: .normal, frontArmAction: .pull, headStability: .stable,
            armPath: .high, releaseHeight: .high, wristPosition: .behind,
            wristOmegaNormalized: 0.6, releaseWristYNormalized: 0.3,
            seamOrientation: .upright, revolutions: .low,
            followThroughDirection: .straight, balanceAtFinish: .balanced,
            runUpQuality: 0.9, gatherQuality: 0.9, deliveryStrideQuality: 0.9,
            releaseQuality: 0.9, followThroughQuality: 0.9
        ),
        signatureTraits: [
            "Tireless workhorse with relentless energy and aggression",
            "Side-on action with nagging accuracy on off-stump line",
            "Whole-hearted competitor — Ashes hat-trick on his birthday"
        ]
    )

    static let ryanHarris = FamousBowlerProfile(
        name: "Ryan Harris",
        country: "AUS",
        era: "2010-2015",
        style: "Right-arm fast-medium",
        dna: BowlingDNA(
            runUpStride: .medium, runUpSpeed: .fast, approachAngle: .straight,
            gatherAlignment: .sideOn, backFootContact: .braced, trunkLean: .slight,
            deliveryStrideLength: .normal, frontArmAction: .pull, headStability: .stable,
            armPath: .high, releaseHeight: .high, wristPosition: .behind,
            wristOmegaNormalized: 0.65, releaseWristYNormalized: 0.3,
            seamOrientation: .upright, revolutions: .low,
            followThroughDirection: .straight, balanceAtFinish: .balanced,
            runUpQuality: 0.9, gatherQuality: 0.9, deliveryStrideQuality: 0.9,
            releaseQuality: 0.9, followThroughQuality: 0.9
        ),
        signatureTraits: [
            "Masterful seam and swing bowling with deceptive pace",
            "Classical side-on action generating late movement both ways",
            "Arguably Australia's best fast bowler when fit — devastating in England"
        ]
    )

    static let mcdermott = FamousBowlerProfile(
        name: "Craig McDermott",
        country: "AUS",
        era: "1984-1996",
        style: "Right-arm fast",
        dna: BowlingDNA(
            runUpStride: .long, runUpSpeed: .fast, approachAngle: .straight,
            gatherAlignment: .sideOn, backFootContact: .jumping, trunkLean: .slight,
            deliveryStrideLength: .normal, frontArmAction: .pull, headStability: .stable,
            armPath: .high, releaseHeight: .high, wristPosition: .behind,
            wristOmegaNormalized: 0.75, releaseWristYNormalized: 0.3,
            seamOrientation: .upright, revolutions: .low,
            followThroughDirection: .straight, balanceAtFinish: .balanced,
            runUpQuality: 0.9, gatherQuality: 0.9, deliveryStrideQuality: 0.9,
            releaseQuality: 0.9, followThroughQuality: 0.9
        ),
        signatureTraits: [
            "Aggressive fast bowler with genuine pace and bounce",
            "Classical action generating outswing with occasional cutter",
            "Spearheaded Australian attack through the late 80s and early 90s"
        ]
    )

    static let alderman = FamousBowlerProfile(
        name: "Terry Alderman",
        country: "AUS",
        era: "1981-1991",
        style: "Right-arm fast-medium",
        dna: BowlingDNA(
            runUpStride: .medium, runUpSpeed: .moderate, approachAngle: .angled,
            gatherAlignment: .sideOn, backFootContact: .braced, trunkLean: .slight,
            deliveryStrideLength: .normal, frontArmAction: .pull, headStability: .stable,
            armPath: .high, releaseHeight: .high, wristPosition: .behind,
            wristOmegaNormalized: 0.45, releaseWristYNormalized: 0.32,
            seamOrientation: .upright, revolutions: .low,
            followThroughDirection: .straight, balanceAtFinish: .balanced,
            runUpQuality: 0.9, gatherQuality: 0.9, deliveryStrideQuality: 0.9,
            releaseQuality: 0.9, followThroughQuality: 0.9
        ),
        signatureTraits: [
            "Supreme outswing bowler who tormented English batsmen",
            "Textbook seam presentation with late away movement",
            "42 Ashes wickets in 1981 and 1989 — Ashes specialist"
        ]
    )

    static let mervHughes = FamousBowlerProfile(
        name: "Merv Hughes",
        country: "AUS",
        era: "1985-1994",
        style: "Right-arm fast-medium",
        dna: BowlingDNA(
            runUpStride: .long, runUpSpeed: .fast, approachAngle: .straight,
            gatherAlignment: .semi, backFootContact: .jumping, trunkLean: .slight,
            deliveryStrideLength: .overStriding, frontArmAction: .pull, headStability: .tilted,
            armPath: .high, releaseHeight: .high, wristPosition: .behind,
            wristOmegaNormalized: 0.65, releaseWristYNormalized: 0.32,
            seamOrientation: .upright, revolutions: .low,
            followThroughDirection: .wide, balanceAtFinish: .falling,
            runUpQuality: 0.9, gatherQuality: 0.9, deliveryStrideQuality: 0.9,
            releaseQuality: 0.9, followThroughQuality: 0.9
        ),
        signatureTraits: [
            "Big-hearted fast-medium bowler with intimidating presence",
            "Long bounding run-up with heavy effort ball at 140+ kph",
            "Aggressive competitor who extracted bounce from any surface"
        ]
    )

    // ============================================================
    // MARK: - ENGLAND
    // ============================================================

    static let trueman = FamousBowlerProfile(
        name: "Fred Trueman",
        country: "ENG",
        era: "1952-1965",
        style: "Right-arm fast",
        dna: BowlingDNA(
            runUpStride: .medium, runUpSpeed: .fast, approachAngle: .straight,
            gatherAlignment: .sideOn, backFootContact: .braced, trunkLean: .slight,
            deliveryStrideLength: .normal, frontArmAction: .pull, headStability: .stable,
            armPath: .high, releaseHeight: .high, wristPosition: .behind,
            wristOmegaNormalized: 0.8, releaseWristYNormalized: 0.3,
            seamOrientation: .upright, revolutions: .low,
            followThroughDirection: .straight, balanceAtFinish: .balanced,
            runUpQuality: 0.9, gatherQuality: 0.9, deliveryStrideQuality: 0.9,
            releaseQuality: 0.9, followThroughQuality: 0.9
        ),
        signatureTraits: [
            "First bowler to 300 Test wickets — classical fast bowling",
            "Textbook side-on action with devastating outswing",
            "Aggressive, fiery competitor with genuine pace and movement"
        ]
    )

    static let botham = FamousBowlerProfile(
        name: "Ian Botham",
        country: "ENG",
        era: "1977-1992",
        style: "Right-arm fast-medium",
        dna: BowlingDNA(
            runUpStride: .medium, runUpSpeed: .fast, approachAngle: .straight,
            gatherAlignment: .semi, backFootContact: .braced, trunkLean: .slight,
            deliveryStrideLength: .normal, frontArmAction: .pull, headStability: .stable,
            armPath: .high, releaseHeight: .high, wristPosition: .behind,
            wristOmegaNormalized: 0.65, releaseWristYNormalized: 0.32,
            seamOrientation: .upright, revolutions: .low,
            followThroughDirection: .straight, balanceAtFinish: .balanced,
            runUpQuality: 0.9, gatherQuality: 0.8, deliveryStrideQuality: 0.8,
            releaseQuality: 0.9, followThroughQuality: 0.8
        ),
        signatureTraits: [
            "Magnificent all-rounder swinging the ball both ways at pace",
            "Natural outswing with ability to generate late movement",
            "Attacking mentality — always looking for wickets, never defensive"
        ]
    )

    static let willis = FamousBowlerProfile(
        name: "Bob Willis",
        country: "ENG",
        era: "1971-1984",
        style: "Right-arm fast",
        dna: BowlingDNA(
            runUpStride: .long, runUpSpeed: .fast, approachAngle: .straight,
            gatherAlignment: .semi, backFootContact: .jumping, trunkLean: .slight,
            deliveryStrideLength: .overStriding, frontArmAction: .sweep, headStability: .falling,
            armPath: .high, releaseHeight: .high, wristPosition: .behind,
            wristOmegaNormalized: 0.75, releaseWristYNormalized: 0.3,
            seamOrientation: .upright, revolutions: .low,
            followThroughDirection: .wide, balanceAtFinish: .stumbling,
            runUpQuality: 0.8, gatherQuality: 0.8, deliveryStrideQuality: 0.9,
            releaseQuality: 0.9, followThroughQuality: 0.8
        ),
        signatureTraits: [
            "Headington 1981 — 8/43 to win the unwinnable Ashes Test",
            "Long gangly run-up building to explosive delivery stride",
            "Awkward bouncing action generating steep bounce and pace"
        ]
    )

    static let gough = FamousBowlerProfile(
        name: "Darren Gough",
        country: "ENG",
        era: "1994-2006",
        style: "Right-arm fast",
        dna: BowlingDNA(
            runUpStride: .medium, runUpSpeed: .fast, approachAngle: .straight,
            gatherAlignment: .semi, backFootContact: .jumping, trunkLean: .slight,
            deliveryStrideLength: .normal, frontArmAction: .pull, headStability: .stable,
            armPath: .high, releaseHeight: .high, wristPosition: .behind,
            wristOmegaNormalized: 0.7, releaseWristYNormalized: 0.32,
            seamOrientation: .upright, revolutions: .low,
            followThroughDirection: .straight, balanceAtFinish: .balanced,
            runUpQuality: 0.9, gatherQuality: 0.9, deliveryStrideQuality: 0.9,
            releaseQuality: 0.9, followThroughQuality: 0.9
        ),
        signatureTraits: [
            "Explosive reverse swing specialist at genuine pace",
            "Compact athletic action with real heart and aggression",
            "England's premier fast bowler through the late 1990s"
        ]
    )

    static let harmison = FamousBowlerProfile(
        name: "Steve Harmison",
        country: "ENG",
        era: "2002-2009",
        style: "Right-arm fast",
        dna: BowlingDNA(
            runUpStride: .long, runUpSpeed: .fast, approachAngle: .straight,
            gatherAlignment: .semi, backFootContact: .jumping, trunkLean: .slight,
            deliveryStrideLength: .overStriding, frontArmAction: .pull, headStability: .tilted,
            armPath: .high, releaseHeight: .high, wristPosition: .behind,
            wristOmegaNormalized: 0.8, releaseWristYNormalized: 0.25,
            seamOrientation: .scrambled, revolutions: .low,
            followThroughDirection: .wide, balanceAtFinish: .falling,
            runUpQuality: 0.9, gatherQuality: 0.9, deliveryStrideQuality: 0.9,
            releaseQuality: 0.9, followThroughQuality: 0.9
        ),
        signatureTraits: [
            "Towering height generating extreme bounce at 150 kph",
            "2004 spell vs West Indies — world's no.1 ranked bowler",
            "Steep trajectory from 6ft4 making batsmen uncomfortable"
        ]
    )

    static let flintoff = FamousBowlerProfile(
        name: "Andrew Flintoff",
        country: "ENG",
        era: "1998-2009",
        style: "Right-arm fast",
        dna: BowlingDNA(
            runUpStride: .long, runUpSpeed: .fast, approachAngle: .straight,
            gatherAlignment: .semi, backFootContact: .jumping, trunkLean: .slight,
            deliveryStrideLength: .normal, frontArmAction: .pull, headStability: .stable,
            armPath: .high, releaseHeight: .high, wristPosition: .behind,
            wristOmegaNormalized: 0.75, releaseWristYNormalized: 0.3,
            seamOrientation: .upright, revolutions: .low,
            followThroughDirection: .straight, balanceAtFinish: .balanced,
            runUpQuality: 0.9, gatherQuality: 0.9, deliveryStrideQuality: 0.9,
            releaseQuality: 0.9, followThroughQuality: 0.9
        ),
        signatureTraits: [
            "2005 Ashes hero — reverse swing at 90mph with all-rounder brilliance",
            "Powerful physique generating pace and bounce from good length",
            "Match-winning spells from sheer force of will and athleticism"
        ]
    )

    static let hoggard = FamousBowlerProfile(
        name: "Matthew Hoggard",
        country: "ENG",
        era: "2000-2008",
        style: "Right-arm fast-medium",
        dna: BowlingDNA(
            runUpStride: .medium, runUpSpeed: .moderate, approachAngle: .angled,
            gatherAlignment: .sideOn, backFootContact: .braced, trunkLean: .slight,
            deliveryStrideLength: .normal, frontArmAction: .pull, headStability: .stable,
            armPath: .high, releaseHeight: .high, wristPosition: .behind,
            wristOmegaNormalized: 0.5, releaseWristYNormalized: 0.32,
            seamOrientation: .upright, revolutions: .low,
            followThroughDirection: .straight, balanceAtFinish: .balanced,
            runUpQuality: 0.9, gatherQuality: 0.9, deliveryStrideQuality: 0.9,
            releaseQuality: 0.9, followThroughQuality: 0.9
        ),
        signatureTraits: [
            "Outstanding swing bowler moving the ball late both ways",
            "Classical English seamer thriving in home conditions",
            "Unsung 2005 Ashes hero with crucial wickets throughout"
        ]
    )

    static let snow = FamousBowlerProfile(
        name: "John Snow",
        country: "ENG",
        era: "1965-1977",
        style: "Right-arm fast",
        dna: BowlingDNA(
            runUpStride: .medium, runUpSpeed: .fast, approachAngle: .straight,
            gatherAlignment: .sideOn, backFootContact: .braced, trunkLean: .slight,
            deliveryStrideLength: .normal, frontArmAction: .pull, headStability: .stable,
            armPath: .high, releaseHeight: .high, wristPosition: .behind,
            wristOmegaNormalized: 0.75, releaseWristYNormalized: 0.3,
            seamOrientation: .upright, revolutions: .low,
            followThroughDirection: .straight, balanceAtFinish: .balanced,
            runUpQuality: 0.9, gatherQuality: 0.9, deliveryStrideQuality: 0.9,
            releaseQuality: 0.9, followThroughQuality: 0.9
        ),
        signatureTraits: [
            "England's finest fast bowler of the 1960s-70s era",
            "Smooth rhythmical action generating genuine pace and bounce",
            "1970-71 Ashes in Australia — match-winning performances away"
        ]
    )

    static let larwood = FamousBowlerProfile(
        name: "Harold Larwood",
        country: "ENG",
        era: "1926-1933",
        style: "Right-arm express fast",
        dna: BowlingDNA(
            runUpStride: .medium, runUpSpeed: .explosive, approachAngle: .straight,
            gatherAlignment: .sideOn, backFootContact: .braced, trunkLean: .slight,
            deliveryStrideLength: .normal, frontArmAction: .pull, headStability: .stable,
            armPath: .high, releaseHeight: .high, wristPosition: .behind,
            wristOmegaNormalized: 0.9, releaseWristYNormalized: 0.28,
            seamOrientation: .upright, revolutions: .low,
            followThroughDirection: .straight, balanceAtFinish: .balanced,
            runUpQuality: 0.9, gatherQuality: 0.9, deliveryStrideQuality: 0.9,
            releaseQuality: 0.9, followThroughQuality: 0.9
        ),
        signatureTraits: [
            "Bodyline series spearhead — extreme pace with pinpoint accuracy",
            "Compact build generating frightening speed from smooth action",
            "Considered one of the fastest bowlers in cricket history"
        ]
    )

    static let tyson = FamousBowlerProfile(
        name: "Frank Tyson",
        country: "ENG",
        era: "1954-1959",
        style: "Right-arm express fast",
        dna: BowlingDNA(
            runUpStride: .long, runUpSpeed: .explosive, approachAngle: .straight,
            gatherAlignment: .sideOn, backFootContact: .jumping, trunkLean: .slight,
            deliveryStrideLength: .overStriding, frontArmAction: .pull, headStability: .tilted,
            armPath: .high, releaseHeight: .high, wristPosition: .behind,
            wristOmegaNormalized: 0.95, releaseWristYNormalized: 0.27,
            seamOrientation: .scrambled, revolutions: .low,
            followThroughDirection: .wide, balanceAtFinish: .falling,
            runUpQuality: 0.9, gatherQuality: 0.9, deliveryStrideQuality: 0.9,
            releaseQuality: 0.9, followThroughQuality: 0.9
        ),
        signatureTraits: [
            "The Typhoon — devastating pace that won the 1954-55 Ashes",
            "Shortened his run-up mid-series to become even more lethal",
            "Brief but brilliant career as one of the fastest ever"
        ]
    )

    static let bedser = FamousBowlerProfile(
        name: "Alec Bedser",
        country: "ENG",
        era: "1946-1955",
        style: "Right-arm fast-medium",
        dna: BowlingDNA(
            runUpStride: .medium, runUpSpeed: .moderate, approachAngle: .straight,
            gatherAlignment: .sideOn, backFootContact: .braced, trunkLean: .upright,
            deliveryStrideLength: .normal, frontArmAction: .pull, headStability: .stable,
            armPath: .high, releaseHeight: .high, wristPosition: .behind,
            wristOmegaNormalized: 0.45, releaseWristYNormalized: 0.32,
            seamOrientation: .upright, revolutions: .low,
            followThroughDirection: .straight, balanceAtFinish: .balanced,
            runUpQuality: 0.9, gatherQuality: 0.9, deliveryStrideQuality: 0.9,
            releaseQuality: 0.9, followThroughQuality: 0.9
        ),
        signatureTraits: [
            "Inswing and leg-cutter master — England's post-war workhorse",
            "Tireless accuracy with big frame generating natural movement",
            "39 wickets in 1953 Ashes — regaining the urn for England"
        ]
    )

    static let statham = FamousBowlerProfile(
        name: "Brian Statham",
        country: "ENG",
        era: "1951-1965",
        style: "Right-arm fast",
        dna: BowlingDNA(
            runUpStride: .medium, runUpSpeed: .fast, approachAngle: .straight,
            gatherAlignment: .sideOn, backFootContact: .braced, trunkLean: .slight,
            deliveryStrideLength: .normal, frontArmAction: .pull, headStability: .stable,
            armPath: .high, releaseHeight: .high, wristPosition: .behind,
            wristOmegaNormalized: 0.7, releaseWristYNormalized: 0.3,
            seamOrientation: .upright, revolutions: .low,
            followThroughDirection: .straight, balanceAtFinish: .balanced,
            runUpQuality: 0.9, gatherQuality: 0.9, deliveryStrideQuality: 0.9,
            releaseQuality: 0.9, followThroughQuality: 0.9
        ),
        signatureTraits: [
            "Metronomic accuracy earning the nickname The Greyhound",
            "Classical side-on action with relentless line just outside off",
            "Perfect foil to Trueman — accuracy complementing aggression"
        ]
    )

    static let woakes = FamousBowlerProfile(
        name: "Chris Woakes",
        country: "ENG",
        era: "2013-present",
        style: "Right-arm fast-medium",
        dna: BowlingDNA(
            runUpStride: .medium, runUpSpeed: .moderate, approachAngle: .straight,
            gatherAlignment: .sideOn, backFootContact: .braced, trunkLean: .slight,
            deliveryStrideLength: .normal, frontArmAction: .pull, headStability: .stable,
            armPath: .high, releaseHeight: .high, wristPosition: .behind,
            wristOmegaNormalized: 0.55, releaseWristYNormalized: 0.3,
            seamOrientation: .upright, revolutions: .low,
            followThroughDirection: .straight, balanceAtFinish: .balanced,
            runUpQuality: 0.9, gatherQuality: 0.9, deliveryStrideQuality: 0.9,
            releaseQuality: 0.9, followThroughQuality: 0.9
        ),
        signatureTraits: [
            "Outstanding swing bowler in home conditions at Edgbaston",
            "Smooth repeatable action with late conventional swing",
            "All-round cricketer contributing with bat and in the field"
        ]
    )

    static let wood = FamousBowlerProfile(
        name: "Mark Wood",
        country: "ENG",
        era: "2015-present",
        style: "Right-arm fast",
        dna: BowlingDNA(
            runUpStride: .long, runUpSpeed: .explosive, approachAngle: .straight,
            gatherAlignment: .semi, backFootContact: .jumping, trunkLean: .slight,
            deliveryStrideLength: .normal, frontArmAction: .pull, headStability: .tilted,
            armPath: .high, releaseHeight: .high, wristPosition: .behind,
            wristOmegaNormalized: 0.9, releaseWristYNormalized: 0.28,
            seamOrientation: .scrambled, revolutions: .low,
            followThroughDirection: .wide, balanceAtFinish: .falling,
            runUpQuality: 0.9, gatherQuality: 0.9, deliveryStrideQuality: 0.9,
            releaseQuality: 0.9, followThroughQuality: 0.9
        ),
        signatureTraits: [
            "Express pace regularly exceeding 150 kph with skiddy trajectory",
            "Unique bounding run-up building to explosive delivery",
            "Whole-hearted competitor giving everything in short sharp spells"
        ]
    )

    static let archer = FamousBowlerProfile(
        name: "Jofra Archer",
        country: "ENG",
        era: "2019-present",
        style: "Right-arm fast",
        dna: BowlingDNA(
            runUpStride: .medium, runUpSpeed: .fast, approachAngle: .straight,
            gatherAlignment: .semi, backFootContact: .jumping, trunkLean: .slight,
            deliveryStrideLength: .normal, frontArmAction: .pull, headStability: .stable,
            armPath: .high, releaseHeight: .high, wristPosition: .behind,
            wristOmegaNormalized: 0.85, releaseWristYNormalized: 0.28,
            seamOrientation: .upright, revolutions: .low,
            followThroughDirection: .straight, balanceAtFinish: .balanced,
            runUpQuality: 0.9, gatherQuality: 0.9, deliveryStrideQuality: 0.9,
            releaseQuality: 0.9, followThroughQuality: 0.9
        ),
        signatureTraits: [
            "Effortless 150 kph pace from a silky smooth action",
            "2019 World Cup final super-over hero under extreme pressure",
            "Deceptive pace — ball arrives faster than the action suggests"
        ]
    )

    // ============================================================
    // MARK: - WEST INDIES
    // ============================================================

    static let ambrose = FamousBowlerProfile(
        name: "Curtly Ambrose",
        country: "WI",
        era: "1988-2000",
        style: "Right-arm fast",
        dna: BowlingDNA(
            runUpStride: .medium, runUpSpeed: .fast, approachAngle: .straight,
            gatherAlignment: .sideOn, backFootContact: .braced, trunkLean: .upright,
            deliveryStrideLength: .normal, frontArmAction: .pull, headStability: .stable,
            armPath: .high, releaseHeight: .high, wristPosition: .behind,
            wristOmegaNormalized: 0.75, releaseWristYNormalized: 0.25,
            seamOrientation: .upright, revolutions: .low,
            followThroughDirection: .straight, balanceAtFinish: .balanced,
            runUpQuality: 0.9, gatherQuality: 0.9, deliveryStrideQuality: 0.9,
            releaseQuality: 0.9, followThroughQuality: 0.9
        ),
        signatureTraits: [
            "6ft7 generating extreme bounce from just back of a length",
            "Parsimonious accuracy — batsmen scored at barely 2 runs per over",
            "Menacing presence with ice-cold temperament and staring eyes"
        ]
    )

    static let walsh = FamousBowlerProfile(
        name: "Courtney Walsh",
        country: "WI",
        era: "1984-2001",
        style: "Right-arm fast",
        dna: BowlingDNA(
            runUpStride: .long, runUpSpeed: .fast, approachAngle: .angled,
            gatherAlignment: .semi, backFootContact: .jumping, trunkLean: .slight,
            deliveryStrideLength: .overStriding, frontArmAction: .sweep, headStability: .tilted,
            armPath: .high, releaseHeight: .high, wristPosition: .behind,
            wristOmegaNormalized: 0.7, releaseWristYNormalized: 0.28,
            seamOrientation: .upright, revolutions: .low,
            followThroughDirection: .across, balanceAtFinish: .falling,
            runUpQuality: 0.9, gatherQuality: 0.9, deliveryStrideQuality: 0.9,
            releaseQuality: 0.9, followThroughQuality: 0.9
        ),
        signatureTraits: [
            "519 Test wickets — first to 500 through sheer longevity",
            "Distinctive galloping run-up and high leaping delivery stride",
            "Tireless workhorse partnering Ambrose for over a decade"
        ]
    )

    static let garner = FamousBowlerProfile(
        name: "Joel Garner",
        country: "WI",
        era: "1977-1987",
        style: "Right-arm fast",
        dna: BowlingDNA(
            runUpStride: .medium, runUpSpeed: .fast, approachAngle: .straight,
            gatherAlignment: .sideOn, backFootContact: .braced, trunkLean: .upright,
            deliveryStrideLength: .normal, frontArmAction: .pull, headStability: .stable,
            armPath: .high, releaseHeight: .high, wristPosition: .behind,
            wristOmegaNormalized: 0.75, releaseWristYNormalized: 0.22,
            seamOrientation: .upright, revolutions: .low,
            followThroughDirection: .straight, balanceAtFinish: .balanced,
            runUpQuality: 0.9, gatherQuality: 0.9, deliveryStrideQuality: 0.9,
            releaseQuality: 0.9, followThroughQuality: 0.9
        ),
        signatureTraits: [
            "Big Bird — 6ft8 delivering yorkers from near-vertical release",
            "Devastating at the death in ODIs with unplayable toe-crushers",
            "Steep bounce making even good-length balls rise sharply"
        ]
    )

    static let holding = FamousBowlerProfile(
        name: "Michael Holding",
        country: "WI",
        era: "1975-1987",
        style: "Right-arm fast",
        dna: BowlingDNA(
            runUpStride: .long, runUpSpeed: .fast, approachAngle: .straight,
            gatherAlignment: .sideOn, backFootContact: .sliding, trunkLean: .slight,
            deliveryStrideLength: .normal, frontArmAction: .pull, headStability: .stable,
            armPath: .high, releaseHeight: .high, wristPosition: .behind,
            wristOmegaNormalized: 0.9, releaseWristYNormalized: 0.27,
            seamOrientation: .upright, revolutions: .low,
            followThroughDirection: .straight, balanceAtFinish: .balanced,
            runUpQuality: 1.0, gatherQuality: 1.0, deliveryStrideQuality: 1.0,
            releaseQuality: 1.0, followThroughQuality: 1.0
        ),
        signatureTraits: [
            "Whispering Death — silent approach at express pace",
            "Most beautiful fast bowling action in cricket history",
            "14/149 vs England at The Oval 1976 — sustained hostile speed"
        ]
    )

    static let roberts = FamousBowlerProfile(
        name: "Andy Roberts",
        country: "WI",
        era: "1974-1983",
        style: "Right-arm fast",
        dna: BowlingDNA(
            runUpStride: .medium, runUpSpeed: .fast, approachAngle: .straight,
            gatherAlignment: .sideOn, backFootContact: .braced, trunkLean: .slight,
            deliveryStrideLength: .normal, frontArmAction: .pull, headStability: .stable,
            armPath: .high, releaseHeight: .high, wristPosition: .behind,
            wristOmegaNormalized: 0.8, releaseWristYNormalized: 0.3,
            seamOrientation: .upright, revolutions: .low,
            followThroughDirection: .straight, balanceAtFinish: .balanced,
            runUpQuality: 0.9, gatherQuality: 0.9, deliveryStrideQuality: 0.9,
            releaseQuality: 0.9, followThroughQuality: 0.9
        ),
        signatureTraits: [
            "Pioneer of the West Indian pace quartet revolution",
            "Two bouncers — one slow to set up, one genuinely fast",
            "Intelligent fast bowler who thought batsmen out at pace"
        ]
    )

    static let wesHall = FamousBowlerProfile(
        name: "Wes Hall",
        country: "WI",
        era: "1958-1969",
        style: "Right-arm fast",
        dna: BowlingDNA(
            runUpStride: .long, runUpSpeed: .explosive, approachAngle: .straight,
            gatherAlignment: .semi, backFootContact: .jumping, trunkLean: .slight,
            deliveryStrideLength: .overStriding, frontArmAction: .pull, headStability: .tilted,
            armPath: .high, releaseHeight: .high, wristPosition: .behind,
            wristOmegaNormalized: 0.85, releaseWristYNormalized: 0.28,
            seamOrientation: .scrambled, revolutions: .low,
            followThroughDirection: .wide, balanceAtFinish: .falling,
            runUpQuality: 0.9, gatherQuality: 0.9, deliveryStrideQuality: 0.9,
            releaseQuality: 0.9, followThroughQuality: 0.9
        ),
        signatureTraits: [
            "Fearsome pace from one of the longest run-ups in cricket",
            "Gold crucifix bouncing as he charged in at top speed",
            "Explosive fast bowler who terrorised batsmen in the 1960s"
        ]
    )

    static let griffith = FamousBowlerProfile(
        name: "Charlie Griffith",
        country: "WI",
        era: "1960-1969",
        style: "Right-arm fast",
        dna: BowlingDNA(
            runUpStride: .medium, runUpSpeed: .fast, approachAngle: .straight,
            gatherAlignment: .semi, backFootContact: .braced, trunkLean: .slight,
            deliveryStrideLength: .normal, frontArmAction: .pull, headStability: .stable,
            armPath: .high, releaseHeight: .high, wristPosition: .behind,
            wristOmegaNormalized: 0.8, releaseWristYNormalized: 0.3,
            seamOrientation: .upright, revolutions: .low,
            followThroughDirection: .straight, balanceAtFinish: .balanced,
            runUpQuality: 0.9, gatherQuality: 0.9, deliveryStrideQuality: 0.9,
            releaseQuality: 0.9, followThroughQuality: 0.9
        ),
        signatureTraits: [
            "Fearsome pace partner to Wes Hall in the 1960s",
            "Devastating bouncer from a powerful build",
            "Controversial action debated throughout his career"
        ]
    )

    static let bishop = FamousBowlerProfile(
        name: "Ian Bishop",
        country: "WI",
        era: "1989-1998",
        style: "Right-arm fast",
        dna: BowlingDNA(
            runUpStride: .long, runUpSpeed: .fast, approachAngle: .straight,
            gatherAlignment: .sideOn, backFootContact: .jumping, trunkLean: .slight,
            deliveryStrideLength: .normal, frontArmAction: .pull, headStability: .stable,
            armPath: .high, releaseHeight: .high, wristPosition: .behind,
            wristOmegaNormalized: 0.8, releaseWristYNormalized: 0.28,
            seamOrientation: .upright, revolutions: .low,
            followThroughDirection: .straight, balanceAtFinish: .balanced,
            runUpQuality: 0.9, gatherQuality: 0.9, deliveryStrideQuality: 0.9,
            releaseQuality: 0.9, followThroughQuality: 0.9
        ),
        signatureTraits: [
            "Genuinely quick with classical high-arm action",
            "Smooth run-up generating 145+ kph with seam movement",
            "Career curtailed by back injuries — devastating when fit"
        ]
    )

    static let roach = FamousBowlerProfile(
        name: "Kemar Roach",
        country: "WI",
        era: "2009-present",
        style: "Right-arm fast",
        dna: BowlingDNA(
            runUpStride: .medium, runUpSpeed: .fast, approachAngle: .straight,
            gatherAlignment: .sideOn, backFootContact: .braced, trunkLean: .slight,
            deliveryStrideLength: .normal, frontArmAction: .pull, headStability: .stable,
            armPath: .high, releaseHeight: .high, wristPosition: .behind,
            wristOmegaNormalized: 0.75, releaseWristYNormalized: 0.3,
            seamOrientation: .upright, revolutions: .low,
            followThroughDirection: .straight, balanceAtFinish: .balanced,
            runUpQuality: 0.9, gatherQuality: 0.9, deliveryStrideQuality: 0.9,
            releaseQuality: 0.9, followThroughQuality: 0.9
        ),
        signatureTraits: [
            "Modern West Indian pace leader with classical action",
            "Dangerous outswing bowler at genuine fast pace",
            "Consistent performer carrying the WI attack for over a decade"
        ]
    )

    static let gabriel = FamousBowlerProfile(
        name: "Shannon Gabriel",
        country: "WI",
        era: "2012-2021",
        style: "Right-arm fast",
        dna: BowlingDNA(
            runUpStride: .long, runUpSpeed: .explosive, approachAngle: .straight,
            gatherAlignment: .semi, backFootContact: .jumping, trunkLean: .slight,
            deliveryStrideLength: .overStriding, frontArmAction: .pull, headStability: .tilted,
            armPath: .high, releaseHeight: .high, wristPosition: .behind,
            wristOmegaNormalized: 0.85, releaseWristYNormalized: 0.28,
            seamOrientation: .scrambled, revolutions: .low,
            followThroughDirection: .wide, balanceAtFinish: .falling,
            runUpQuality: 0.9, gatherQuality: 0.9, deliveryStrideQuality: 0.9,
            releaseQuality: 0.9, followThroughQuality: 0.9
        ),
        signatureTraits: [
            "Raw express pace regularly exceeding 150 kph",
            "Hostile bouncer from tall frame generating steep bounce",
            "Heart-on-sleeve effort ball every delivery"
        ]
    )

    static let taylor = FamousBowlerProfile(
        name: "Jerome Taylor",
        country: "WI",
        era: "2003-2016",
        style: "Right-arm fast",
        dna: BowlingDNA(
            runUpStride: .medium, runUpSpeed: .fast, approachAngle: .straight,
            gatherAlignment: .semi, backFootContact: .braced, trunkLean: .slight,
            deliveryStrideLength: .normal, frontArmAction: .pull, headStability: .stable,
            armPath: .high, releaseHeight: .high, wristPosition: .behind,
            wristOmegaNormalized: 0.75, releaseWristYNormalized: 0.3,
            seamOrientation: .upright, revolutions: .low,
            followThroughDirection: .straight, balanceAtFinish: .balanced,
            runUpQuality: 0.9, gatherQuality: 0.9, deliveryStrideQuality: 0.9,
            releaseQuality: 0.9, followThroughQuality: 0.9
        ),
        signatureTraits: [
            "5/11 vs England at Headingley — destructive at his best",
            "Smooth action generating sharp swing at 140+ kph",
            "Talented but inconsistent — brilliant on his day"
        ]
    )

    static let edwards = FamousBowlerProfile(
        name: "Fidel Edwards",
        country: "WI",
        era: "2003-2012",
        style: "Right-arm fast",
        dna: BowlingDNA(
            runUpStride: .long, runUpSpeed: .explosive, approachAngle: .angled,
            gatherAlignment: .frontOn, backFootContact: .jumping, trunkLean: .pronounced,
            deliveryStrideLength: .overStriding, frontArmAction: .sweep, headStability: .falling,
            armPath: .sling, releaseHeight: .medium, wristPosition: .behind,
            wristOmegaNormalized: 0.9, releaseWristYNormalized: 0.4,
            seamOrientation: .scrambled, revolutions: .low,
            followThroughDirection: .wide, balanceAtFinish: .stumbling,
            runUpQuality: 0.9, gatherQuality: 0.9, deliveryStrideQuality: 0.9,
            releaseQuality: 0.9, followThroughQuality: 0.9
        ),
        signatureTraits: [
            "Explosive slingy action generating 150+ kph from small frame",
            "Front-on chest-on delivery reminiscent of Jeff Thomson",
            "Raw pace and aggression with unorthodox bowling action"
        ]
    )

    static let patterson = FamousBowlerProfile(
        name: "Patrick Patterson",
        country: "WI",
        era: "1986-1993",
        style: "Right-arm express fast",
        dna: BowlingDNA(
            runUpStride: .long, runUpSpeed: .explosive, approachAngle: .straight,
            gatherAlignment: .semi, backFootContact: .jumping, trunkLean: .slight,
            deliveryStrideLength: .overStriding, frontArmAction: .pull, headStability: .tilted,
            armPath: .high, releaseHeight: .high, wristPosition: .behind,
            wristOmegaNormalized: 0.9, releaseWristYNormalized: 0.27,
            seamOrientation: .scrambled, revolutions: .low,
            followThroughDirection: .wide, balanceAtFinish: .falling,
            runUpQuality: 0.9, gatherQuality: 0.9, deliveryStrideQuality: 0.9,
            releaseQuality: 0.9, followThroughQuality: 0.9
        ),
        signatureTraits: [
            "Raw express pace — among the fastest of the WI pace era",
            "Terrifying bouncer that unsettled the best batsmen",
            "Brief but devastating career — pure hostile fast bowling"
        ]
    )

    static let dottin = FamousBowlerProfile(
        name: "Deandra Dottin",
        country: "WI",
        era: "2008-present",
        style: "Right-arm fast-medium",
        dna: BowlingDNA(
            runUpStride: .medium, runUpSpeed: .fast, approachAngle: .straight,
            gatherAlignment: .semi, backFootContact: .braced, trunkLean: .slight,
            deliveryStrideLength: .normal, frontArmAction: .pull, headStability: .stable,
            armPath: .high, releaseHeight: .high, wristPosition: .behind,
            wristOmegaNormalized: 0.5, releaseWristYNormalized: 0.35,
            seamOrientation: .upright, revolutions: .low,
            followThroughDirection: .straight, balanceAtFinish: .balanced,
            runUpQuality: 0.9, gatherQuality: 0.9, deliveryStrideQuality: 0.9,
            releaseQuality: 0.9, followThroughQuality: 0.9
        ),
        signatureTraits: [
            "Explosive all-rounder with genuine pace for women's cricket",
            "Athletic action generating speed and bounce",
            "Match-winner with both bat and ball in T20 internationals"
        ]
    )

    // ============================================================
    // MARK: - PAKISTAN
    // ============================================================

    static let younis = FamousBowlerProfile(
        name: "Waqar Younis",
        country: "PAK",
        era: "1989-2003",
        style: "Right-arm fast",
        dna: BowlingDNA(
            runUpStride: .medium, runUpSpeed: .fast, approachAngle: .straight,
            gatherAlignment: .semi, backFootContact: .jumping, trunkLean: .slight,
            deliveryStrideLength: .normal, frontArmAction: .pull, headStability: .stable,
            armPath: .high, releaseHeight: .high, wristPosition: .behind,
            wristOmegaNormalized: 0.85, releaseWristYNormalized: 0.3,
            seamOrientation: .angled, revolutions: .low,
            followThroughDirection: .straight, balanceAtFinish: .balanced,
            runUpQuality: 0.9, gatherQuality: 0.9, deliveryStrideQuality: 0.9,
            releaseQuality: 0.9, followThroughQuality: 0.9
        ),
        signatureTraits: [
            "Devastating reverse-swinging yorker — toe-crushing specialist",
            "Genuine pace at 150 kph with lethal late inswing",
            "Deadly partnership with Wasim Akram — greatest pace duo ever"
        ]
    )

    static let imranKhan = FamousBowlerProfile(
        name: "Imran Khan",
        country: "PAK",
        era: "1971-1992",
        style: "Right-arm fast",
        dna: BowlingDNA(
            runUpStride: .long, runUpSpeed: .fast, approachAngle: .straight,
            gatherAlignment: .sideOn, backFootContact: .braced, trunkLean: .slight,
            deliveryStrideLength: .normal, frontArmAction: .pull, headStability: .stable,
            armPath: .high, releaseHeight: .high, wristPosition: .behind,
            wristOmegaNormalized: 0.8, releaseWristYNormalized: 0.3,
            seamOrientation: .upright, revolutions: .low,
            followThroughDirection: .straight, balanceAtFinish: .balanced,
            runUpQuality: 0.9, gatherQuality: 0.9, deliveryStrideQuality: 0.9,
            releaseQuality: 0.9, followThroughQuality: 0.9
        ),
        signatureTraits: [
            "Complete fast bowler — pace, swing, and reverse swing pioneer",
            "Classical side-on action with textbook technique",
            "Captain who led Pakistan to 1992 World Cup glory"
        ]
    )

    static let amir = FamousBowlerProfile(
        name: "Mohammad Amir",
        country: "PAK",
        era: "2009-2020",
        style: "Left-arm fast",
        dna: BowlingDNA(
            runUpStride: .medium, runUpSpeed: .fast, approachAngle: .angled,
            gatherAlignment: .sideOn, backFootContact: .braced, trunkLean: .slight,
            deliveryStrideLength: .normal, frontArmAction: .pull, headStability: .stable,
            armPath: .high, releaseHeight: .high, wristPosition: .behind,
            wristOmegaNormalized: 0.75, releaseWristYNormalized: 0.3,
            seamOrientation: .upright, revolutions: .low,
            followThroughDirection: .straight, balanceAtFinish: .balanced,
            runUpQuality: 0.9, gatherQuality: 0.9, deliveryStrideQuality: 0.9,
            releaseQuality: 0.9, followThroughQuality: 0.9
        ),
        signatureTraits: [
            "Prodigious swing bowling from left-arm over at genuine pace",
            "Silky smooth action producing late outswing to right-handers",
            "Natural talent — devastating at 17 before career interruption"
        ]
    )

    static let asif = FamousBowlerProfile(
        name: "Mohammad Asif",
        country: "PAK",
        era: "2005-2010",
        style: "Right-arm fast-medium",
        dna: BowlingDNA(
            runUpStride: .medium, runUpSpeed: .moderate, approachAngle: .straight,
            gatherAlignment: .sideOn, backFootContact: .braced, trunkLean: .slight,
            deliveryStrideLength: .normal, frontArmAction: .pull, headStability: .stable,
            armPath: .high, releaseHeight: .high, wristPosition: .behind,
            wristOmegaNormalized: 0.55, releaseWristYNormalized: 0.3,
            seamOrientation: .upright, revolutions: .low,
            followThroughDirection: .straight, balanceAtFinish: .balanced,
            runUpQuality: 0.9, gatherQuality: 0.9, deliveryStrideQuality: 0.9,
            releaseQuality: 0.9, followThroughQuality: 0.9
        ),
        signatureTraits: [
            "Immaculate seam position producing movement both ways",
            "Tall bowler using height for bounce and late deviation",
            "Subtle changes of pace and angle from a smooth action"
        ]
    )

    static let shaheen = FamousBowlerProfile(
        name: "Shaheen Shah Afridi",
        country: "PAK",
        era: "2018-present",
        style: "Left-arm fast",
        dna: BowlingDNA(
            runUpStride: .long, runUpSpeed: .fast, approachAngle: .angled,
            gatherAlignment: .semi, backFootContact: .jumping, trunkLean: .slight,
            deliveryStrideLength: .normal, frontArmAction: .pull, headStability: .stable,
            armPath: .high, releaseHeight: .high, wristPosition: .behind,
            wristOmegaNormalized: 0.8, releaseWristYNormalized: 0.27,
            seamOrientation: .upright, revolutions: .low,
            followThroughDirection: .across, balanceAtFinish: .falling,
            runUpQuality: 0.9, gatherQuality: 0.9, deliveryStrideQuality: 0.9,
            releaseQuality: 0.9, followThroughQuality: 0.9
        ),
        signatureTraits: [
            "Left-arm pace spearhead — devastating inswing to right-handers",
            "Tall frame generating steep bounce and movement at 145+ kph",
            "T20 World Cup 2021 final spell demolishing India's top order"
        ]
    )

    static let naseem = FamousBowlerProfile(
        name: "Naseem Shah",
        country: "PAK",
        era: "2019-present",
        style: "Right-arm fast",
        dna: BowlingDNA(
            runUpStride: .long, runUpSpeed: .explosive, approachAngle: .straight,
            gatherAlignment: .semi, backFootContact: .jumping, trunkLean: .slight,
            deliveryStrideLength: .normal, frontArmAction: .pull, headStability: .tilted,
            armPath: .high, releaseHeight: .high, wristPosition: .behind,
            wristOmegaNormalized: 0.85, releaseWristYNormalized: 0.28,
            seamOrientation: .upright, revolutions: .low,
            followThroughDirection: .straight, balanceAtFinish: .falling,
            runUpQuality: 0.9, gatherQuality: 0.9, deliveryStrideQuality: 0.9,
            releaseQuality: 0.9, followThroughQuality: 0.9
        ),
        signatureTraits: [
            "Youngest fast bowler to take a Test hat-trick at age 16",
            "Express pace with natural seam movement at 145+ kph",
            "Aggressive young paceman with a high-arm classical action"
        ]
    )

    static let umarGul = FamousBowlerProfile(
        name: "Umar Gul",
        country: "PAK",
        era: "2003-2016",
        style: "Right-arm fast-medium",
        dna: BowlingDNA(
            runUpStride: .medium, runUpSpeed: .fast, approachAngle: .straight,
            gatherAlignment: .semi, backFootContact: .braced, trunkLean: .slight,
            deliveryStrideLength: .normal, frontArmAction: .pull, headStability: .stable,
            armPath: .high, releaseHeight: .high, wristPosition: .behind,
            wristOmegaNormalized: 0.65, releaseWristYNormalized: 0.32,
            seamOrientation: .angled, revolutions: .low,
            followThroughDirection: .straight, balanceAtFinish: .balanced,
            runUpQuality: 0.9, gatherQuality: 0.9, deliveryStrideQuality: 0.9,
            releaseQuality: 0.9, followThroughQuality: 0.9
        ),
        signatureTraits: [
            "T20 specialist with brilliant death bowling variations",
            "Reverse swing and yorker combination at the death",
            "Key performer in Pakistan's 2009 T20 World Cup triumph"
        ]
    )

    static let aaqibJaved = FamousBowlerProfile(
        name: "Aaqib Javed",
        country: "PAK",
        era: "1988-1998",
        style: "Right-arm fast-medium",
        dna: BowlingDNA(
            runUpStride: .medium, runUpSpeed: .fast, approachAngle: .straight,
            gatherAlignment: .sideOn, backFootContact: .braced, trunkLean: .slight,
            deliveryStrideLength: .normal, frontArmAction: .pull, headStability: .stable,
            armPath: .high, releaseHeight: .high, wristPosition: .behind,
            wristOmegaNormalized: 0.6, releaseWristYNormalized: 0.32,
            seamOrientation: .upright, revolutions: .low,
            followThroughDirection: .straight, balanceAtFinish: .balanced,
            runUpQuality: 0.9, gatherQuality: 0.9, deliveryStrideQuality: 0.9,
            releaseQuality: 0.9, followThroughQuality: 0.9
        ),
        signatureTraits: [
            "Skilful swing bowler thriving in subcontinental conditions",
            "7/37 vs India at Sharjah — one of Pakistan's finest ODI spells",
            "Reliable new-ball bowler complementing Wasim and Waqar"
        ]
    )

    static let fazalMahmood = FamousBowlerProfile(
        name: "Fazal Mahmood",
        country: "PAK",
        era: "1952-1962",
        style: "Right-arm fast-medium",
        dna: BowlingDNA(
            runUpStride: .medium, runUpSpeed: .moderate, approachAngle: .straight,
            gatherAlignment: .sideOn, backFootContact: .braced, trunkLean: .upright,
            deliveryStrideLength: .normal, frontArmAction: .pull, headStability: .stable,
            armPath: .high, releaseHeight: .high, wristPosition: .behind,
            wristOmegaNormalized: 0.45, releaseWristYNormalized: 0.32,
            seamOrientation: .upright, revolutions: .low,
            followThroughDirection: .straight, balanceAtFinish: .balanced,
            runUpQuality: 0.9, gatherQuality: 0.9, deliveryStrideQuality: 0.9,
            releaseQuality: 0.9, followThroughQuality: 0.9
        ),
        signatureTraits: [
            "Pakistan's first great fast bowler — 12/99 vs England at The Oval",
            "Master of swing and cut in English conditions",
            "Pioneer of Pakistan cricket bowling with classical technique"
        ]
    )

    // ============================================================
    // MARK: - SOUTH AFRICA
    // ============================================================

    static let donald = FamousBowlerProfile(
        name: "Allan Donald",
        country: "SA",
        era: "1992-2003",
        style: "Right-arm fast",
        dna: BowlingDNA(
            runUpStride: .long, runUpSpeed: .explosive, approachAngle: .straight,
            gatherAlignment: .sideOn, backFootContact: .jumping, trunkLean: .slight,
            deliveryStrideLength: .normal, frontArmAction: .pull, headStability: .stable,
            armPath: .high, releaseHeight: .high, wristPosition: .behind,
            wristOmegaNormalized: 0.85, releaseWristYNormalized: 0.28,
            seamOrientation: .upright, revolutions: .low,
            followThroughDirection: .straight, balanceAtFinish: .balanced,
            runUpQuality: 1.0, gatherQuality: 0.9, deliveryStrideQuality: 0.9,
            releaseQuality: 1.0, followThroughQuality: 0.9
        ),
        signatureTraits: [
            "White Lightning — express pace with hostile aggression",
            "Classical high-arm action producing bounce and movement",
            "Fierce competitor who defined post-isolation SA fast bowling"
        ]
    )

    static let pollock = FamousBowlerProfile(
        name: "Shaun Pollock",
        country: "SA",
        era: "1995-2008",
        style: "Right-arm fast-medium",
        dna: BowlingDNA(
            runUpStride: .medium, runUpSpeed: .fast, approachAngle: .straight,
            gatherAlignment: .sideOn, backFootContact: .braced, trunkLean: .slight,
            deliveryStrideLength: .normal, frontArmAction: .pull, headStability: .stable,
            armPath: .high, releaseHeight: .high, wristPosition: .behind,
            wristOmegaNormalized: 0.6, releaseWristYNormalized: 0.3,
            seamOrientation: .upright, revolutions: .low,
            followThroughDirection: .straight, balanceAtFinish: .balanced,
            runUpQuality: 0.9, gatherQuality: 1.0, deliveryStrideQuality: 0.9,
            releaseQuality: 1.0, followThroughQuality: 1.0
        ),
        signatureTraits: [
            "Immaculate line and length with subtle seam movement",
            "Classical side-on action — textbook fast-medium bowling",
            "Brilliant all-rounder and captain with supreme consistency"
        ]
    )

    static let ntini = FamousBowlerProfile(
        name: "Makhaya Ntini",
        country: "SA",
        era: "1998-2009",
        style: "Right-arm fast",
        dna: BowlingDNA(
            runUpStride: .long, runUpSpeed: .fast, approachAngle: .straight,
            gatherAlignment: .semi, backFootContact: .jumping, trunkLean: .slight,
            deliveryStrideLength: .normal, frontArmAction: .pull, headStability: .tilted,
            armPath: .high, releaseHeight: .high, wristPosition: .behind,
            wristOmegaNormalized: 0.75, releaseWristYNormalized: 0.3,
            seamOrientation: .upright, revolutions: .low,
            followThroughDirection: .straight, balanceAtFinish: .falling,
            runUpQuality: 0.9, gatherQuality: 0.9, deliveryStrideQuality: 0.9,
            releaseQuality: 0.9, followThroughQuality: 0.9
        ),
        signatureTraits: [
            "Tireless fast bowler with boundless energy and enthusiasm",
            "First Black African to play Test cricket for South Africa",
            "Wholehearted competitor generating pace through raw athleticism"
        ]
    )

    static let rabada = FamousBowlerProfile(
        name: "Kagiso Rabada",
        country: "SA",
        era: "2015-present",
        style: "Right-arm fast",
        dna: BowlingDNA(
            runUpStride: .long, runUpSpeed: .fast, approachAngle: .straight,
            gatherAlignment: .sideOn, backFootContact: .jumping, trunkLean: .slight,
            deliveryStrideLength: .normal, frontArmAction: .pull, headStability: .stable,
            armPath: .high, releaseHeight: .high, wristPosition: .behind,
            wristOmegaNormalized: 0.8, releaseWristYNormalized: 0.28,
            seamOrientation: .upright, revolutions: .low,
            followThroughDirection: .straight, balanceAtFinish: .balanced,
            runUpQuality: 0.9, gatherQuality: 0.9, deliveryStrideQuality: 0.9,
            releaseQuality: 0.9, followThroughQuality: 0.9
        ),
        signatureTraits: [
            "Youngest South African to 200 Test wickets — generational talent",
            "Express pace at 145+ with deadly outswing at high speed",
            "Aggressive wicket-taker with ice-cool composure under pressure"
        ]
    )

    static let morkel = FamousBowlerProfile(
        name: "Morne Morkel",
        country: "SA",
        era: "2006-2018",
        style: "Right-arm fast",
        dna: BowlingDNA(
            runUpStride: .long, runUpSpeed: .fast, approachAngle: .straight,
            gatherAlignment: .sideOn, backFootContact: .jumping, trunkLean: .slight,
            deliveryStrideLength: .overStriding, frontArmAction: .pull, headStability: .tilted,
            armPath: .high, releaseHeight: .high, wristPosition: .behind,
            wristOmegaNormalized: 0.8, releaseWristYNormalized: 0.25,
            seamOrientation: .upright, revolutions: .low,
            followThroughDirection: .straight, balanceAtFinish: .falling,
            runUpQuality: 0.9, gatherQuality: 0.9, deliveryStrideQuality: 0.9,
            releaseQuality: 0.9, followThroughQuality: 0.9
        ),
        signatureTraits: [
            "6ft5 generating extreme bounce from back of a length",
            "Steep trajectory at 145+ kph making batsmen uncomfortable",
            "Reliable workhorse partnering Steyn for over a decade"
        ]
    )

    static let philander = FamousBowlerProfile(
        name: "Vernon Philander",
        country: "SA",
        era: "2011-2020",
        style: "Right-arm fast-medium",
        dna: BowlingDNA(
            runUpStride: .short, runUpSpeed: .moderate, approachAngle: .straight,
            gatherAlignment: .sideOn, backFootContact: .braced, trunkLean: .upright,
            deliveryStrideLength: .normal, frontArmAction: .pull, headStability: .stable,
            armPath: .high, releaseHeight: .high, wristPosition: .behind,
            wristOmegaNormalized: 0.45, releaseWristYNormalized: 0.32,
            seamOrientation: .upright, revolutions: .low,
            followThroughDirection: .straight, balanceAtFinish: .balanced,
            runUpQuality: 0.9, gatherQuality: 0.9, deliveryStrideQuality: 0.9,
            releaseQuality: 0.9, followThroughQuality: 0.9
        ),
        signatureTraits: [
            "Prodigious seam and swing at gentle pace in helpful conditions",
            "Best bowling average in modern cricket when conditions suit",
            "Compact action producing late movement off the seam"
        ]
    )

    static let nortje = FamousBowlerProfile(
        name: "Anrich Nortje",
        country: "SA",
        era: "2019-present",
        style: "Right-arm fast",
        dna: BowlingDNA(
            runUpStride: .long, runUpSpeed: .explosive, approachAngle: .straight,
            gatherAlignment: .semi, backFootContact: .jumping, trunkLean: .slight,
            deliveryStrideLength: .normal, frontArmAction: .pull, headStability: .tilted,
            armPath: .high, releaseHeight: .high, wristPosition: .behind,
            wristOmegaNormalized: 0.9, releaseWristYNormalized: 0.28,
            seamOrientation: .scrambled, revolutions: .low,
            followThroughDirection: .straight, balanceAtFinish: .falling,
            runUpQuality: 0.9, gatherQuality: 0.9, deliveryStrideQuality: 0.9,
            releaseQuality: 0.9, followThroughQuality: 0.9
        ),
        signatureTraits: [
            "Express pace regularly exceeding 150 kph in all formats",
            "IPL's fastest delivery records — raw speed as primary weapon",
            "Strong action generating frightening pace with bounce"
        ]
    )

    static let ismail = FamousBowlerProfile(
        name: "Shabnim Ismail",
        country: "SA",
        era: "2007-present",
        style: "Right-arm fast",
        dna: BowlingDNA(
            runUpStride: .long, runUpSpeed: .fast, approachAngle: .straight,
            gatherAlignment: .semi, backFootContact: .jumping, trunkLean: .slight,
            deliveryStrideLength: .normal, frontArmAction: .pull, headStability: .tilted,
            armPath: .high, releaseHeight: .high, wristPosition: .behind,
            wristOmegaNormalized: 0.6, releaseWristYNormalized: 0.3,
            seamOrientation: .upright, revolutions: .low,
            followThroughDirection: .straight, balanceAtFinish: .falling,
            runUpQuality: 0.9, gatherQuality: 0.9, deliveryStrideQuality: 0.9,
            releaseQuality: 0.9, followThroughQuality: 0.9
        ),
        signatureTraits: [
            "Fastest bowler in women's cricket history — 130+ kph",
            "Aggressive pace attack with genuine speed and bounce",
            "Express pace rare in women's game — a true trailblazer"
        ]
    )

    static let kapp = FamousBowlerProfile(
        name: "Marizanne Kapp",
        country: "SA",
        era: "2009-present",
        style: "Right-arm fast-medium",
        dna: BowlingDNA(
            runUpStride: .medium, runUpSpeed: .moderate, approachAngle: .straight,
            gatherAlignment: .sideOn, backFootContact: .braced, trunkLean: .slight,
            deliveryStrideLength: .normal, frontArmAction: .pull, headStability: .stable,
            armPath: .high, releaseHeight: .high, wristPosition: .behind,
            wristOmegaNormalized: 0.5, releaseWristYNormalized: 0.32,
            seamOrientation: .upright, revolutions: .low,
            followThroughDirection: .straight, balanceAtFinish: .balanced,
            runUpQuality: 0.9, gatherQuality: 0.9, deliveryStrideQuality: 0.9,
            releaseQuality: 0.9, followThroughQuality: 0.9
        ),
        signatureTraits: [
            "Complete all-rounder with precise seam bowling",
            "Consistent swing and seam movement at lively pace",
            "South Africa's most valuable cricketer across all formats"
        ]
    )

    static let khaka = FamousBowlerProfile(
        name: "Ayabonga Khaka",
        country: "SA",
        era: "2013-present",
        style: "Right-arm fast-medium",
        dna: BowlingDNA(
            runUpStride: .medium, runUpSpeed: .moderate, approachAngle: .straight,
            gatherAlignment: .sideOn, backFootContact: .braced, trunkLean: .slight,
            deliveryStrideLength: .normal, frontArmAction: .pull, headStability: .stable,
            armPath: .high, releaseHeight: .high, wristPosition: .behind,
            wristOmegaNormalized: 0.45, releaseWristYNormalized: 0.34,
            seamOrientation: .upright, revolutions: .low,
            followThroughDirection: .straight, balanceAtFinish: .balanced,
            runUpQuality: 0.9, gatherQuality: 0.9, deliveryStrideQuality: 0.9,
            releaseQuality: 0.9, followThroughQuality: 0.9
        ),
        signatureTraits: [
            "Reliable new-ball bowler with consistent line and length",
            "Swing and seam movement extracting early wickets",
            "Workhorse of South African women's bowling attack"
        ]
    )

    // ============================================================
    // MARK: - NEW ZEALAND
    // ============================================================

    static let hadlee = FamousBowlerProfile(
        name: "Richard Hadlee",
        country: "NZ",
        era: "1973-1990",
        style: "Right-arm fast-medium",
        dna: BowlingDNA(
            runUpStride: .medium, runUpSpeed: .fast, approachAngle: .straight,
            gatherAlignment: .sideOn, backFootContact: .braced, trunkLean: .slight,
            deliveryStrideLength: .normal, frontArmAction: .pull, headStability: .stable,
            armPath: .high, releaseHeight: .high, wristPosition: .behind,
            wristOmegaNormalized: 0.7, releaseWristYNormalized: 0.3,
            seamOrientation: .upright, revolutions: .low,
            followThroughDirection: .straight, balanceAtFinish: .balanced,
            runUpQuality: 0.9, gatherQuality: 1.0, deliveryStrideQuality: 0.9,
            releaseQuality: 1.0, followThroughQuality: 1.0
        ),
        signatureTraits: [
            "First to 400 Test wickets — complete fast bowling mastery",
            "Shortened run-up to gain accuracy without losing pace",
            "Single-handedly carried New Zealand's bowling for a decade"
        ]
    )

    static let boult = FamousBowlerProfile(
        name: "Trent Boult",
        country: "NZ",
        era: "2011-present",
        style: "Left-arm fast-medium",
        dna: BowlingDNA(
            runUpStride: .medium, runUpSpeed: .fast, approachAngle: .angled,
            gatherAlignment: .sideOn, backFootContact: .braced, trunkLean: .slight,
            deliveryStrideLength: .normal, frontArmAction: .pull, headStability: .stable,
            armPath: .high, releaseHeight: .high, wristPosition: .behind,
            wristOmegaNormalized: 0.65, releaseWristYNormalized: 0.3,
            seamOrientation: .upright, revolutions: .low,
            followThroughDirection: .across, balanceAtFinish: .balanced,
            runUpQuality: 0.9, gatherQuality: 0.9, deliveryStrideQuality: 0.9,
            releaseQuality: 0.9, followThroughQuality: 0.9
        ),
        signatureTraits: [
            "Elite left-arm swing bowler with devastating new-ball spells",
            "Natural angle across right-handers with late outswing",
            "Key to NZ's rise — WTC final hero with swing in all conditions"
        ]
    )

    static let southee = FamousBowlerProfile(
        name: "Tim Southee",
        country: "NZ",
        era: "2008-present",
        style: "Right-arm fast-medium",
        dna: BowlingDNA(
            runUpStride: .medium, runUpSpeed: .fast, approachAngle: .straight,
            gatherAlignment: .sideOn, backFootContact: .braced, trunkLean: .slight,
            deliveryStrideLength: .normal, frontArmAction: .pull, headStability: .stable,
            armPath: .high, releaseHeight: .high, wristPosition: .behind,
            wristOmegaNormalized: 0.6, releaseWristYNormalized: 0.3,
            seamOrientation: .upright, revolutions: .low,
            followThroughDirection: .straight, balanceAtFinish: .balanced,
            runUpQuality: 0.9, gatherQuality: 0.9, deliveryStrideQuality: 0.9,
            releaseQuality: 0.9, followThroughQuality: 0.9
        ),
        signatureTraits: [
            "Masterful swing bowler thriving with the new ball",
            "Classical action with late outswing at 135-140 kph",
            "NZ's most experienced paceman — 350+ international wickets"
        ]
    )

    static let bond = FamousBowlerProfile(
        name: "Shane Bond",
        country: "NZ",
        era: "2001-2010",
        style: "Right-arm fast",
        dna: BowlingDNA(
            runUpStride: .long, runUpSpeed: .explosive, approachAngle: .straight,
            gatherAlignment: .sideOn, backFootContact: .jumping, trunkLean: .slight,
            deliveryStrideLength: .normal, frontArmAction: .pull, headStability: .stable,
            armPath: .high, releaseHeight: .high, wristPosition: .behind,
            wristOmegaNormalized: 0.9, releaseWristYNormalized: 0.28,
            seamOrientation: .upright, revolutions: .low,
            followThroughDirection: .straight, balanceAtFinish: .falling,
            runUpQuality: 0.9, gatherQuality: 0.9, deliveryStrideQuality: 0.9,
            releaseQuality: 0.9, followThroughQuality: 0.8
        ),
        signatureTraits: [
            "NZ's fastest ever — 150+ kph with outswing at top speed",
            "Devastating when fit but cruelly injury-plagued career",
            "6/23 vs Australia 2003 World Cup — world-class at his peak"
        ]
    )

    static let wagner = FamousBowlerProfile(
        name: "Neil Wagner",
        country: "NZ",
        era: "2012-2023",
        style: "Left-arm fast-medium",
        dna: BowlingDNA(
            runUpStride: .medium, runUpSpeed: .fast, approachAngle: .angled,
            gatherAlignment: .semi, backFootContact: .braced, trunkLean: .slight,
            deliveryStrideLength: .normal, frontArmAction: .pull, headStability: .tilted,
            armPath: .high, releaseHeight: .high, wristPosition: .behind,
            wristOmegaNormalized: 0.6, releaseWristYNormalized: 0.32,
            seamOrientation: .scrambled, revolutions: .low,
            followThroughDirection: .across, balanceAtFinish: .falling,
            runUpQuality: 0.9, gatherQuality: 0.9, deliveryStrideQuality: 0.9,
            releaseQuality: 0.9, followThroughQuality: 0.9
        ),
        signatureTraits: [
            "Relentless short-pitch bowling plan targeting the body",
            "Left-arm angle creating awkward bounce from round the wicket",
            "Tireless competitor who bowled with a broken toe in a Test"
        ]
    )

    static let chrisMartin = FamousBowlerProfile(
        name: "Chris Martin",
        country: "NZ",
        era: "2000-2013",
        style: "Right-arm fast-medium",
        dna: BowlingDNA(
            runUpStride: .medium, runUpSpeed: .fast, approachAngle: .straight,
            gatherAlignment: .sideOn, backFootContact: .braced, trunkLean: .slight,
            deliveryStrideLength: .normal, frontArmAction: .pull, headStability: .stable,
            armPath: .high, releaseHeight: .high, wristPosition: .behind,
            wristOmegaNormalized: 0.6, releaseWristYNormalized: 0.3,
            seamOrientation: .upright, revolutions: .low,
            followThroughDirection: .straight, balanceAtFinish: .balanced,
            runUpQuality: 0.9, gatherQuality: 0.9, deliveryStrideQuality: 0.9,
            releaseQuality: 0.9, followThroughQuality: 0.9
        ),
        signatureTraits: [
            "Prodigious swing and seam from a classical action",
            "233 Test wickets as NZ's reliable new-ball operator",
            "Elite bowler who could barely hold a bat — 36 Test ducks"
        ]
    )

    static let jamieson = FamousBowlerProfile(
        name: "Kyle Jamieson",
        country: "NZ",
        era: "2020-present",
        style: "Right-arm fast-medium",
        dna: BowlingDNA(
            runUpStride: .medium, runUpSpeed: .fast, approachAngle: .straight,
            gatherAlignment: .sideOn, backFootContact: .braced, trunkLean: .upright,
            deliveryStrideLength: .normal, frontArmAction: .pull, headStability: .stable,
            armPath: .high, releaseHeight: .high, wristPosition: .behind,
            wristOmegaNormalized: 0.65, releaseWristYNormalized: 0.25,
            seamOrientation: .upright, revolutions: .low,
            followThroughDirection: .straight, balanceAtFinish: .balanced,
            runUpQuality: 0.9, gatherQuality: 0.9, deliveryStrideQuality: 0.9,
            releaseQuality: 0.9, followThroughQuality: 0.9
        ),
        signatureTraits: [
            "6ft8 generating steep bounce from back of a length",
            "WTC final star with 7/61 against India in Southampton",
            "Uses extreme height to extract bounce on flat surfaces"
        ]
    )

    static let mattHenry = FamousBowlerProfile(
        name: "Matt Henry",
        country: "NZ",
        era: "2014-present",
        style: "Right-arm fast-medium",
        dna: BowlingDNA(
            runUpStride: .medium, runUpSpeed: .fast, approachAngle: .straight,
            gatherAlignment: .sideOn, backFootContact: .braced, trunkLean: .slight,
            deliveryStrideLength: .normal, frontArmAction: .pull, headStability: .stable,
            armPath: .high, releaseHeight: .high, wristPosition: .behind,
            wristOmegaNormalized: 0.6, releaseWristYNormalized: 0.3,
            seamOrientation: .upright, revolutions: .low,
            followThroughDirection: .straight, balanceAtFinish: .balanced,
            runUpQuality: 0.9, gatherQuality: 0.9, deliveryStrideQuality: 0.9,
            releaseQuality: 0.9, followThroughQuality: 0.9
        ),
        signatureTraits: [
            "Sharp swing bowler with late movement at 135-140 kph",
            "Classical seam position producing consistent outswing",
            "Key white-ball performer for New Zealand"
        ]
    )

    static let morrison = FamousBowlerProfile(
        name: "Danny Morrison",
        country: "NZ",
        era: "1987-1997",
        style: "Right-arm fast",
        dna: BowlingDNA(
            runUpStride: .long, runUpSpeed: .fast, approachAngle: .straight,
            gatherAlignment: .semi, backFootContact: .jumping, trunkLean: .slight,
            deliveryStrideLength: .overStriding, frontArmAction: .pull, headStability: .falling,
            armPath: .high, releaseHeight: .high, wristPosition: .behind,
            wristOmegaNormalized: 0.7, releaseWristYNormalized: 0.3,
            seamOrientation: .scrambled, revolutions: .low,
            followThroughDirection: .wide, balanceAtFinish: .stumbling,
            runUpQuality: 0.9, gatherQuality: 0.9, deliveryStrideQuality: 0.9,
            releaseQuality: 0.9, followThroughQuality: 0.9
        ),
        signatureTraits: [
            "Wholehearted fast bowler giving everything in every spell",
            "Bounding run-up and explosive action at genuine pace",
            "160 Test wickets as NZ's strike bowler through the 1990s"
        ]
    )

    static let tahuhu = FamousBowlerProfile(
        name: "Lea Tahuhu",
        country: "NZ",
        era: "2012-present",
        style: "Right-arm fast-medium",
        dna: BowlingDNA(
            runUpStride: .medium, runUpSpeed: .fast, approachAngle: .straight,
            gatherAlignment: .semi, backFootContact: .braced, trunkLean: .slight,
            deliveryStrideLength: .normal, frontArmAction: .pull, headStability: .stable,
            armPath: .high, releaseHeight: .high, wristPosition: .behind,
            wristOmegaNormalized: 0.5, releaseWristYNormalized: 0.32,
            seamOrientation: .upright, revolutions: .low,
            followThroughDirection: .straight, balanceAtFinish: .balanced,
            runUpQuality: 0.9, gatherQuality: 0.9, deliveryStrideQuality: 0.9,
            releaseQuality: 0.9, followThroughQuality: 0.9
        ),
        signatureTraits: [
            "Pace spearhead of New Zealand women's bowling attack",
            "Strong seam position generating movement at lively pace",
            "Aggressive competitor with bounce and carry"
        ]
    )

    // ============================================================
    // MARK: - SRI LANKA
    // ============================================================

    static let malinga = FamousBowlerProfile(
        name: "Lasith Malinga",
        country: "SL",
        era: "2004-2021",
        style: "Right-arm fast",
        dna: BowlingDNA(
            runUpStride: .short, runUpSpeed: .fast, approachAngle: .angled,
            gatherAlignment: .frontOn, backFootContact: .braced, trunkLean: .pronounced,
            deliveryStrideLength: .short, frontArmAction: .sweep, headStability: .falling,
            armPath: .sling, releaseHeight: .low, wristPosition: .sideArm,
            wristOmegaNormalized: 0.8, releaseWristYNormalized: 0.65,
            seamOrientation: .angled, revolutions: .low,
            followThroughDirection: .across, balanceAtFinish: .falling,
            runUpQuality: 0.8, gatherQuality: 0.8, deliveryStrideQuality: 0.8,
            releaseQuality: 1.0, followThroughQuality: 0.8
        ),
        signatureTraits: [
            "Unique round-arm slinging action — lowest release in fast bowling",
            "Deadly yorker from below the batsman's eyeline",
            "Four wickets in four balls — twice in international cricket"
        ]
    )

    // ============================================================
    // MARK: - INDIA
    // ============================================================

    static let kapilDev = FamousBowlerProfile(
        name: "Kapil Dev",
        country: "IND",
        era: "1978-1994",
        style: "Right-arm fast-medium",
        dna: BowlingDNA(
            runUpStride: .medium, runUpSpeed: .fast, approachAngle: .straight,
            gatherAlignment: .sideOn, backFootContact: .jumping, trunkLean: .slight,
            deliveryStrideLength: .normal, frontArmAction: .pull, headStability: .stable,
            armPath: .high, releaseHeight: .high, wristPosition: .behind,
            wristOmegaNormalized: 0.7, releaseWristYNormalized: 0.3,
            seamOrientation: .upright, revolutions: .low,
            followThroughDirection: .straight, balanceAtFinish: .balanced,
            runUpQuality: 0.9, gatherQuality: 0.9, deliveryStrideQuality: 0.9,
            releaseQuality: 0.9, followThroughQuality: 0.9
        ),
        signatureTraits: [
            "India's greatest all-rounder — 434 Test wickets",
            "Outswing at pace with leaping delivery stride",
            "1983 World Cup-winning captain with match-winning bowling"
        ]
    )

    static let srinath = FamousBowlerProfile(
        name: "Javagal Srinath",
        country: "IND",
        era: "1991-2003",
        style: "Right-arm fast",
        dna: BowlingDNA(
            runUpStride: .long, runUpSpeed: .fast, approachAngle: .straight,
            gatherAlignment: .sideOn, backFootContact: .jumping, trunkLean: .slight,
            deliveryStrideLength: .normal, frontArmAction: .pull, headStability: .stable,
            armPath: .high, releaseHeight: .high, wristPosition: .behind,
            wristOmegaNormalized: 0.75, releaseWristYNormalized: 0.3,
            seamOrientation: .upright, revolutions: .low,
            followThroughDirection: .straight, balanceAtFinish: .balanced,
            runUpQuality: 0.9, gatherQuality: 0.9, deliveryStrideQuality: 0.9,
            releaseQuality: 0.9, followThroughQuality: 0.9
        ),
        signatureTraits: [
            "India's fastest bowler of his era — genuine 145+ kph pace",
            "Classical high-arm action with late outswing",
            "236 ODI wickets as India's premier fast bowling threat"
        ]
    )

    static let zaheerKhan = FamousBowlerProfile(
        name: "Zaheer Khan",
        country: "IND",
        era: "2000-2014",
        style: "Left-arm fast-medium",
        dna: BowlingDNA(
            runUpStride: .medium, runUpSpeed: .fast, approachAngle: .angled,
            gatherAlignment: .semi, backFootContact: .braced, trunkLean: .slight,
            deliveryStrideLength: .normal, frontArmAction: .pull, headStability: .stable,
            armPath: .high, releaseHeight: .high, wristPosition: .behind,
            wristOmegaNormalized: 0.6, releaseWristYNormalized: 0.32,
            seamOrientation: .upright, revolutions: .low,
            followThroughDirection: .across, balanceAtFinish: .balanced,
            runUpQuality: 0.9, gatherQuality: 0.9, deliveryStrideQuality: 0.9,
            releaseQuality: 0.9, followThroughQuality: 0.9
        ),
        signatureTraits: [
            "India's finest left-arm seamer — swing both ways on demand",
            "Reverse swing specialist crucial in the 2011 World Cup win",
            "Intelligent bowler who evolved from pace to craft over his career"
        ]
    )

    static let shami = FamousBowlerProfile(
        name: "Mohammed Shami",
        country: "IND",
        era: "2013-present",
        style: "Right-arm fast",
        dna: BowlingDNA(
            runUpStride: .medium, runUpSpeed: .fast, approachAngle: .straight,
            gatherAlignment: .sideOn, backFootContact: .braced, trunkLean: .slight,
            deliveryStrideLength: .normal, frontArmAction: .pull, headStability: .stable,
            armPath: .high, releaseHeight: .high, wristPosition: .behind,
            wristOmegaNormalized: 0.75, releaseWristYNormalized: 0.3,
            seamOrientation: .upright, revolutions: .low,
            followThroughDirection: .straight, balanceAtFinish: .balanced,
            runUpQuality: 0.9, gatherQuality: 0.9, deliveryStrideQuality: 0.9,
            releaseQuality: 0.9, followThroughQuality: 0.9
        ),
        signatureTraits: [
            "Immaculate seam position producing movement both ways",
            "Natural ability to move the ball at 140+ kph consistently",
            "Deadly with both new ball and reverse swing"
        ]
    )

    static let ishant = FamousBowlerProfile(
        name: "Ishant Sharma",
        country: "IND",
        era: "2007-2021",
        style: "Right-arm fast-medium",
        dna: BowlingDNA(
            runUpStride: .long, runUpSpeed: .fast, approachAngle: .straight,
            gatherAlignment: .semi, backFootContact: .jumping, trunkLean: .slight,
            deliveryStrideLength: .overStriding, frontArmAction: .pull, headStability: .tilted,
            armPath: .high, releaseHeight: .high, wristPosition: .behind,
            wristOmegaNormalized: 0.65, releaseWristYNormalized: 0.27,
            seamOrientation: .upright, revolutions: .low,
            followThroughDirection: .straight, balanceAtFinish: .falling,
            runUpQuality: 0.9, gatherQuality: 0.9, deliveryStrideQuality: 0.9,
            releaseQuality: 0.9, followThroughQuality: 0.9
        ),
        signatureTraits: [
            "Tall seamer using 6ft4 height for steep bounce",
            "Famous spell to Ricky Ponting at Perth 2008",
            "Evolved from raw pace to skilled swing bowler over 100+ Tests"
        ]
    )

    static let umeshYadav = FamousBowlerProfile(
        name: "Umesh Yadav",
        country: "IND",
        era: "2011-2023",
        style: "Right-arm fast",
        dna: BowlingDNA(
            runUpStride: .long, runUpSpeed: .fast, approachAngle: .straight,
            gatherAlignment: .semi, backFootContact: .jumping, trunkLean: .slight,
            deliveryStrideLength: .normal, frontArmAction: .pull, headStability: .tilted,
            armPath: .high, releaseHeight: .high, wristPosition: .behind,
            wristOmegaNormalized: 0.75, releaseWristYNormalized: 0.3,
            seamOrientation: .scrambled, revolutions: .low,
            followThroughDirection: .wide, balanceAtFinish: .falling,
            runUpQuality: 0.9, gatherQuality: 0.9, deliveryStrideQuality: 0.9,
            releaseQuality: 0.9, followThroughQuality: 0.9
        ),
        signatureTraits: [
            "Raw pace at 145+ kph with aggressive intent",
            "Skiddy trajectory making the ball hurry onto batsmen",
            "Devastating in home conditions with reverse swing"
        ]
    )

    static let bhuvneshwar = FamousBowlerProfile(
        name: "Bhuvneshwar Kumar",
        country: "IND",
        era: "2012-present",
        style: "Right-arm fast-medium",
        dna: BowlingDNA(
            runUpStride: .medium, runUpSpeed: .moderate, approachAngle: .straight,
            gatherAlignment: .sideOn, backFootContact: .braced, trunkLean: .slight,
            deliveryStrideLength: .normal, frontArmAction: .pull, headStability: .stable,
            armPath: .high, releaseHeight: .high, wristPosition: .behind,
            wristOmegaNormalized: 0.5, releaseWristYNormalized: 0.32,
            seamOrientation: .upright, revolutions: .low,
            followThroughDirection: .straight, balanceAtFinish: .balanced,
            runUpQuality: 0.9, gatherQuality: 0.9, deliveryStrideQuality: 0.9,
            releaseQuality: 0.9, followThroughQuality: 0.9
        ),
        signatureTraits: [
            "India's premier swing bowler with late conventional movement",
            "Excellent seam position generating both inswing and outswing",
            "Skilful death bowler with yorkers and slower ball variations"
        ]
    )

    static let jhulanGoswami = FamousBowlerProfile(
        name: "Jhulan Goswami",
        country: "IND",
        era: "2002-2022",
        style: "Right-arm fast-medium",
        dna: BowlingDNA(
            runUpStride: .medium, runUpSpeed: .fast, approachAngle: .straight,
            gatherAlignment: .sideOn, backFootContact: .braced, trunkLean: .slight,
            deliveryStrideLength: .normal, frontArmAction: .pull, headStability: .stable,
            armPath: .high, releaseHeight: .high, wristPosition: .behind,
            wristOmegaNormalized: 0.55, releaseWristYNormalized: 0.3,
            seamOrientation: .upright, revolutions: .low,
            followThroughDirection: .straight, balanceAtFinish: .balanced,
            runUpQuality: 0.9, gatherQuality: 0.9, deliveryStrideQuality: 0.9,
            releaseQuality: 0.9, followThroughQuality: 0.9
        ),
        signatureTraits: [
            "Highest wicket-taker in women's ODI history (255 wickets)",
            "Tall seamer with genuine pace and outswing",
            "Pioneer of women's fast bowling — inspired a generation"
        ]
    )

    static let renukaSingh = FamousBowlerProfile(
        name: "Renuka Singh Thakur",
        country: "IND",
        era: "2022-present",
        style: "Right-arm fast-medium",
        dna: BowlingDNA(
            runUpStride: .medium, runUpSpeed: .moderate, approachAngle: .straight,
            gatherAlignment: .sideOn, backFootContact: .braced, trunkLean: .slight,
            deliveryStrideLength: .normal, frontArmAction: .pull, headStability: .stable,
            armPath: .high, releaseHeight: .high, wristPosition: .behind,
            wristOmegaNormalized: 0.45, releaseWristYNormalized: 0.34,
            seamOrientation: .upright, revolutions: .low,
            followThroughDirection: .straight, balanceAtFinish: .balanced,
            runUpQuality: 0.9, gatherQuality: 0.9, deliveryStrideQuality: 0.9,
            releaseQuality: 0.9, followThroughQuality: 0.9
        ),
        signatureTraits: [
            "Sharp swing bowling with late movement at the top",
            "Natural seam position producing movement both ways",
            "Rising star of Indian women's pace attack"
        ]
    )

    static let poojaVastrakar = FamousBowlerProfile(
        name: "Pooja Vastrakar",
        country: "IND",
        era: "2017-present",
        style: "Right-arm fast-medium",
        dna: BowlingDNA(
            runUpStride: .medium, runUpSpeed: .moderate, approachAngle: .straight,
            gatherAlignment: .semi, backFootContact: .braced, trunkLean: .slight,
            deliveryStrideLength: .normal, frontArmAction: .pull, headStability: .stable,
            armPath: .high, releaseHeight: .high, wristPosition: .behind,
            wristOmegaNormalized: 0.45, releaseWristYNormalized: 0.34,
            seamOrientation: .upright, revolutions: .low,
            followThroughDirection: .straight, balanceAtFinish: .balanced,
            runUpQuality: 0.9, gatherQuality: 0.9, deliveryStrideQuality: 0.9,
            releaseQuality: 0.9, followThroughQuality: 0.9
        ),
        signatureTraits: [
            "Tall all-rounder generating bounce at brisk pace",
            "Seam movement with ability to hit the deck hard",
            "Key bowling all-rounder in India's women's setup"
        ]
    )

    // ============================================================
    // MARK: - ZIMBABWE
    // ============================================================

    static let streak = FamousBowlerProfile(
        name: "Heath Streak",
        country: "ZIM",
        era: "1993-2005",
        style: "Right-arm fast-medium",
        dna: BowlingDNA(
            runUpStride: .medium, runUpSpeed: .fast, approachAngle: .straight,
            gatherAlignment: .sideOn, backFootContact: .braced, trunkLean: .slight,
            deliveryStrideLength: .normal, frontArmAction: .pull, headStability: .stable,
            armPath: .high, releaseHeight: .high, wristPosition: .behind,
            wristOmegaNormalized: 0.6, releaseWristYNormalized: 0.3,
            seamOrientation: .upright, revolutions: .low,
            followThroughDirection: .straight, balanceAtFinish: .balanced,
            runUpQuality: 0.9, gatherQuality: 0.9, deliveryStrideQuality: 0.9,
            releaseQuality: 0.9, followThroughQuality: 0.9
        ),
        signatureTraits: [
            "Zimbabwe's greatest fast bowler — 216 Test wickets",
            "Reliable swing and seam with classical side-on action",
            "All-rounder who carried Zimbabwe's bowling for over a decade"
        ]
    )

    // ============================================================
    // MARK: - WOMEN (additional)
    // ============================================================

    static let sciverBrunt = FamousBowlerProfile(
        name: "Katherine Sciver-Brunt",
        country: "ENG",
        era: "2004-2023",
        style: "Right-arm fast-medium",
        dna: BowlingDNA(
            runUpStride: .medium, runUpSpeed: .fast, approachAngle: .straight,
            gatherAlignment: .sideOn, backFootContact: .braced, trunkLean: .slight,
            deliveryStrideLength: .normal, frontArmAction: .pull, headStability: .stable,
            armPath: .high, releaseHeight: .high, wristPosition: .behind,
            wristOmegaNormalized: 0.55, releaseWristYNormalized: 0.3,
            seamOrientation: .upright, revolutions: .low,
            followThroughDirection: .straight, balanceAtFinish: .balanced,
            runUpQuality: 0.9, gatherQuality: 0.9, deliveryStrideQuality: 0.9,
            releaseQuality: 0.9, followThroughQuality: 0.9
        ),
        signatureTraits: [
            "England's greatest women's fast bowler — pace and swing",
            "Genuine pace at 120+ kph with late swing movement",
            "Longevity and consistency across nearly two decades"
        ]
    )

    static let shrubsole = FamousBowlerProfile(
        name: "Anya Shrubsole",
        country: "ENG",
        era: "2008-2022",
        style: "Right-arm fast-medium",
        dna: BowlingDNA(
            runUpStride: .medium, runUpSpeed: .moderate, approachAngle: .straight,
            gatherAlignment: .sideOn, backFootContact: .braced, trunkLean: .slight,
            deliveryStrideLength: .normal, frontArmAction: .pull, headStability: .stable,
            armPath: .high, releaseHeight: .high, wristPosition: .behind,
            wristOmegaNormalized: 0.5, releaseWristYNormalized: 0.32,
            seamOrientation: .upright, revolutions: .low,
            followThroughDirection: .straight, balanceAtFinish: .balanced,
            runUpQuality: 0.9, gatherQuality: 0.9, deliveryStrideQuality: 0.9,
            releaseQuality: 0.9, followThroughQuality: 0.9
        ),
        signatureTraits: [
            "2017 World Cup final hero — 6/46 to win at Lord's",
            "Excellent swing bowler with consistent seam position",
            "Big-game performer in pressure moments for England"
        ]
    )

    static let perry = FamousBowlerProfile(
        name: "Ellyse Perry",
        country: "AUS",
        era: "2007-present",
        style: "Right-arm fast-medium",
        dna: BowlingDNA(
            runUpStride: .medium, runUpSpeed: .fast, approachAngle: .straight,
            gatherAlignment: .sideOn, backFootContact: .braced, trunkLean: .slight,
            deliveryStrideLength: .normal, frontArmAction: .pull, headStability: .stable,
            armPath: .high, releaseHeight: .high, wristPosition: .behind,
            wristOmegaNormalized: 0.55, releaseWristYNormalized: 0.3,
            seamOrientation: .upright, revolutions: .low,
            followThroughDirection: .straight, balanceAtFinish: .balanced,
            runUpQuality: 0.9, gatherQuality: 0.9, deliveryStrideQuality: 0.9,
            releaseQuality: 0.9, followThroughQuality: 0.9
        ),
        signatureTraits: [
            "Complete all-rounder — Australia's greatest women's cricketer",
            "Genuine pace at 120+ kph with swing and seam movement",
            "Classical action combining accuracy with subtle variations"
        ]
    )

    static let schutt = FamousBowlerProfile(
        name: "Megan Schutt",
        country: "AUS",
        era: "2012-present",
        style: "Right-arm fast-medium",
        dna: BowlingDNA(
            runUpStride: .medium, runUpSpeed: .moderate, approachAngle: .straight,
            gatherAlignment: .sideOn, backFootContact: .braced, trunkLean: .slight,
            deliveryStrideLength: .normal, frontArmAction: .pull, headStability: .stable,
            armPath: .high, releaseHeight: .high, wristPosition: .behind,
            wristOmegaNormalized: 0.5, releaseWristYNormalized: 0.32,
            seamOrientation: .upright, revolutions: .low,
            followThroughDirection: .straight, balanceAtFinish: .balanced,
            runUpQuality: 0.9, gatherQuality: 0.9, deliveryStrideQuality: 0.9,
            releaseQuality: 0.9, followThroughQuality: 0.9
        ),
        signatureTraits: [
            "Australia's premier women's swing bowler with new ball",
            "Consistent seam position producing outswing to right-handers",
            "Excellent control and variations in death overs"
        ]
    )

    static let darcieBrown = FamousBowlerProfile(
        name: "Darcie Brown",
        country: "AUS",
        era: "2021-present",
        style: "Right-arm fast",
        dna: BowlingDNA(
            runUpStride: .long, runUpSpeed: .fast, approachAngle: .straight,
            gatherAlignment: .semi, backFootContact: .jumping, trunkLean: .slight,
            deliveryStrideLength: .normal, frontArmAction: .pull, headStability: .tilted,
            armPath: .high, releaseHeight: .high, wristPosition: .behind,
            wristOmegaNormalized: 0.6, releaseWristYNormalized: 0.3,
            seamOrientation: .upright, revolutions: .low,
            followThroughDirection: .straight, balanceAtFinish: .falling,
            runUpQuality: 0.9, gatherQuality: 0.9, deliveryStrideQuality: 0.9,
            releaseQuality: 0.9, followThroughQuality: 0.9
        ),
        signatureTraits: [
            "Express pace for women's cricket — regularly clocking 120+ kph",
            "Aggressive young fast bowler with bounce and carry",
            "Future of Australian women's pace bowling"
        ]
    )

    static let dianaBaig = FamousBowlerProfile(
        name: "Diana Baig",
        country: "PAK",
        era: "2015-present",
        style: "Left-arm fast-medium",
        dna: BowlingDNA(
            runUpStride: .medium, runUpSpeed: .moderate, approachAngle: .angled,
            gatherAlignment: .semi, backFootContact: .braced, trunkLean: .slight,
            deliveryStrideLength: .normal, frontArmAction: .pull, headStability: .stable,
            armPath: .high, releaseHeight: .high, wristPosition: .behind,
            wristOmegaNormalized: 0.45, releaseWristYNormalized: 0.34,
            seamOrientation: .upright, revolutions: .low,
            followThroughDirection: .across, balanceAtFinish: .balanced,
            runUpQuality: 0.9, gatherQuality: 0.9, deliveryStrideQuality: 0.9,
            releaseQuality: 0.9, followThroughQuality: 0.9
        ),
        signatureTraits: [
            "Pakistan's leading women's pace bowler with left-arm angle",
            "Natural swing from over the wicket to right-handers",
            "Multi-sport athlete who also represented Pakistan in football"
        ]
    )

    static let fatimaSana = FamousBowlerProfile(
        name: "Fatima Sana",
        country: "PAK",
        era: "2019-present",
        style: "Right-arm fast-medium",
        dna: BowlingDNA(
            runUpStride: .medium, runUpSpeed: .moderate, approachAngle: .straight,
            gatherAlignment: .semi, backFootContact: .braced, trunkLean: .slight,
            deliveryStrideLength: .normal, frontArmAction: .pull, headStability: .stable,
            armPath: .high, releaseHeight: .high, wristPosition: .behind,
            wristOmegaNormalized: 0.45, releaseWristYNormalized: 0.34,
            seamOrientation: .upright, revolutions: .low,
            followThroughDirection: .straight, balanceAtFinish: .balanced,
            runUpQuality: 0.9, gatherQuality: 0.9, deliveryStrideQuality: 0.9,
            releaseQuality: 0.9, followThroughQuality: 0.9
        ),
        signatureTraits: [
            "Emerging Pakistani all-rounder with lively seam bowling",
            "ICC Emerging Women's Cricketer of the Year 2022",
            "Pace and bounce from a strong athletic action"
        ]
    )

    static let issyWong = FamousBowlerProfile(
        name: "Issy Wong",
        country: "ENG",
        era: "2022-present",
        style: "Right-arm fast",
        dna: BowlingDNA(
            runUpStride: .long, runUpSpeed: .fast, approachAngle: .straight,
            gatherAlignment: .semi, backFootContact: .jumping, trunkLean: .slight,
            deliveryStrideLength: .normal, frontArmAction: .pull, headStability: .tilted,
            armPath: .high, releaseHeight: .high, wristPosition: .behind,
            wristOmegaNormalized: 0.6, releaseWristYNormalized: 0.3,
            seamOrientation: .scrambled, revolutions: .low,
            followThroughDirection: .straight, balanceAtFinish: .falling,
            runUpQuality: 0.9, gatherQuality: 0.9, deliveryStrideQuality: 0.9,
            releaseQuality: 0.9, followThroughQuality: 0.9
        ),
        signatureTraits: [
            "Genuine express pace in women's cricket — 125+ kph regularly",
            "Aggressive fast bowler with hostility and bounce",
            "Young English pace prospect with exciting raw speed"
        ]
    )

    static let vlaeminck = FamousBowlerProfile(
        name: "Tayla Vlaeminck",
        country: "AUS",
        era: "2018-present",
        style: "Right-arm fast",
        dna: BowlingDNA(
            runUpStride: .long, runUpSpeed: .fast, approachAngle: .straight,
            gatherAlignment: .semi, backFootContact: .jumping, trunkLean: .slight,
            deliveryStrideLength: .normal, frontArmAction: .pull, headStability: .tilted,
            armPath: .high, releaseHeight: .high, wristPosition: .behind,
            wristOmegaNormalized: 0.6, releaseWristYNormalized: 0.3,
            seamOrientation: .upright, revolutions: .low,
            followThroughDirection: .straight, balanceAtFinish: .falling,
            runUpQuality: 0.9, gatherQuality: 0.9, deliveryStrideQuality: 0.9,
            releaseQuality: 0.9, followThroughQuality: 0.9
        ),
        signatureTraits: [
            "Australia's fastest women's bowler — genuine pace at 120+ kph",
            "Aggressive action with steep bounce from athletic frame",
            "Injury-plagued but devastating when fit — raw pace talent"
        ]
    )

    // MARK: - Dennis Lillee (AUS)

    static let lillee = FamousBowlerProfile(
        name: "Dennis Lillee",
        country: "AUS",
        era: "1971-1984",
        style: "Right-arm fast",
        dna: BowlingDNA(
            runUpStride: .long, runUpSpeed: .fast, approachAngle: .straight,
            gatherAlignment: .sideOn, backFootContact: .braced, trunkLean: .slight,
            deliveryStrideLength: .normal, frontArmAction: .pull, headStability: .stable,
            armPath: .high, releaseHeight: .high, wristPosition: .behind,
            wristOmegaNormalized: 0.85, releaseWristYNormalized: 0.28,
            seamOrientation: .upright, revolutions: .low,
            followThroughDirection: .straight, balanceAtFinish: .balanced,
            runUpQuality: 0.9, gatherQuality: 0.9, deliveryStrideQuality: 0.9,
            releaseQuality: 0.9, followThroughQuality: 0.9
        ),
        signatureTraits: [
            "Greatest Australian fast bowler — 355 Test wickets",
            "Classical side-on action combining pace with swing and cut",
            "Fierce competitor who rebuilt his action after a back injury"
        ]
    )
}
