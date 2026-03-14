# T1: Expand Famous Bowler Database to 100 Bowlers

## Owner: Codex
## Priority: P0
## Status: TODO

## Goal
Expand `FamousBowlerDatabase.swift` from 12 to 100 famous bowlers with accurate, research-backed DNA profiles. This is the vector store used for "Action Archetype" matching — comparing a user's bowling action to famous bowlers.

## File to Modify
`/ios/wellBowled/FamousBowlerDatabase.swift`

## Current State
12 bowlers: McGrath, Akram, Warne, Shoaib Akhtar, Muralitharan, Anderson, Starc, Ashwin, Malcolm Marshall, Bumrah, Vaas, Steyn.

## What to Add
88 more bowlers across all eras, styles, and countries. Target mix:

### By Style (approximate)
- ~35 right-arm fast/fast-medium
- ~15 left-arm fast/fast-medium
- ~15 right-arm off-spin
- ~10 right-arm leg-spin
- ~10 left-arm orthodox spin
- ~5 left-arm wrist spin
- ~10 medium-pace/all-rounders with distinctive actions

### By Era (approximate)
- ~20 pre-1990 legends
- ~30 1990s-2000s golden era
- ~30 2010s-present modern
- ~20 current active players

### By Country (ensure representation)
Australia, England, India, Pakistan, Sri Lanka, South Africa, West Indies, New Zealand, Bangladesh, Zimbabwe, Afghanistan, Ireland

## DNA Schema (20 dimensions)
Every bowler needs ALL fields populated. **When in doubt about a specific field, leave it as nil** — the matcher gracefully handles missing fields. But aim for full profiles where research is clear.

```swift
BowlingDNA(
    // Phase 1: Run-Up
    runUpStride: .short | .medium | .long,
    runUpSpeed: .slow | .moderate | .fast | .explosive,
    approachAngle: .straight | .angled | .wide,

    // Phase 2: Gather
    gatherAlignment: .frontOn | .semi | .sideOn,
    backFootContact: .braced | .sliding | .jumping,
    trunkLean: .upright | .slight | .pronounced,

    // Phase 3: Delivery Stride
    deliveryStrideLength: .short | .normal | .overStriding,
    frontArmAction: .pull | .sweep | .delayed,
    headStability: .stable | .tilted | .falling,

    // Phase 4: Release (weighted 2x in matching)
    armPath: .high | .roundArm | .sling,
    releaseHeight: .high | .medium | .low,
    wristPosition: .behind | .cocked | .sideArm,
    wristOmegaNormalized: 0.0...1.0,  // 0=slow arm, 1=express pace
    releaseWristYNormalized: 0.0...1.0,  // 0=very high release, 1=low sling

    // Phase 5: Seam/Spin
    seamOrientation: .upright | .scrambled | .angled,
    revolutions: .low | .medium | .high,

    // Phase 6: Follow-Through
    followThroughDirection: .across | .straight | .wide,
    balanceAtFinish: .balanced | .falling | .stumbling
)
```

## Guidelines for DNA Values

### wristOmegaNormalized (arm speed proxy)
- 0.0-0.2 = spinners (Warne ~0.2, Murali ~0.15)
- 0.2-0.5 = medium-pace (McGrath ~0.5, Anderson ~0.45)
- 0.5-0.8 = fast (Starc ~0.8, Bumrah ~0.8, Marshall ~0.85)
- 0.8-1.0 = express (Shoaib ~1.0, Lee ~0.95, Steyn ~0.9)

### releaseWristYNormalized (release height proxy)
- 0.2-0.3 = very high release (McGrath ~0.3, Steyn ~0.28)
- 0.3-0.5 = standard height (most fast bowlers)
- 0.5-0.6 = medium/round-arm (Bumrah ~0.55, spinners ~0.45-0.6)
- 0.6-0.8 = low sling (Malinga ~0.75)

### Signature Traits (3 per bowler)
Each bowler needs exactly 3 signature traits — concise, specific, cricket-knowledgeable descriptions of what makes their action distinctive. Not generic praise — biomechanical and tactical specifics.

## Accuracy Requirements
- **Research each bowler's actual action** — watch footage descriptions, biomechanical analyses, coaching literature
- **Do not guess** — if unsure about a specific dimension (e.g., exact back-foot contact for a 1970s bowler), set it to nil
- **Cross-validate** — a side-on bowler with .frontOn alignment is a red flag
- **Consistency** — express pace bowlers should have high wristOmega, spinners should have high revolutions, etc.
- **Style field** must accurately describe the bowler's bowling type (e.g., "Right-arm fast", "Left-arm orthodox spin", "Right-arm leg-spin/googly")

## Suggested Bowlers to Include (non-exhaustive)

### Fast Bowlers
Brett Lee, Dennis Lillee, Jeff Thomson, Curtly Ambrose, Courtney Walsh, Allan Donald, Waqar Younis, Imran Khan, Kapil Dev, Richard Hadlee, Shaun Pollock, Andrew Flintoff, Stuart Broad, Pat Cummins, Kagiso Rabada, Trent Boult, Tim Southee, Shaheen Afridi, Mohammad Shami, Ishant Sharma, Zaheer Khan, Javagal Srinath, Lasith Malinga, Fidel Edwards, Andy Roberts, Michael Holding, Joel Garner, Colin Croft, Patrick Patterson, Devon Malcolm, Simon Jones, Steve Harmison, Chris Cairns, Shane Bond, Mitchell Johnson, Josh Hazlewood, Marco Jansen, Naseem Shah

### Spinners
Anil Kumble, Harbhajan Singh, Graeme Swann, Daniel Vettori, Saqlain Mushtaq, Saeed Ajmal, Shakib Al Hasan, Rangana Herath, Nathan Lyon, Jack Leach, Ravindra Jadeja, Kuldeep Yadav, Yuzvendra Chahal, Rashid Khan, Imran Tahir, Brad Hogg, Bishan Bedi, Erapalli Prasanna, B.S. Chandrasekhar, Abdul Qadir, Mushtaq Ahmed

### Medium-Pace / All-Rounders
Jacques Kallis, Chris Woakes, Ben Stokes, Sam Curran, Lance Gibbs

## Verification
After populating, verify:
1. `allBowlers` array includes all new entries
2. No duplicate names
3. Build compiles without errors
4. Existing DNA tests still pass (self-match = 100%)
5. Spinner vs fast bowler similarity should be < 60%

## Output
Updated `FamousBowlerDatabase.swift` with 100 bowlers total.
