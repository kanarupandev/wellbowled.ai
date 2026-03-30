# wellBowled.ai — v3 (CURRENT)

## The Idea

Every young bowler watches their heroes and thinks "I want to bowl like Bumrah." But they can't see what's actually different about their own action versus Bumrah's. They feel it's different. They can't see WHY.

wellBowled.ai shows them.

Upload your clip, see your action next to your idol's, at the same scale, same angle, same moment. The differences become obvious. Not through numbers or coaching lectures — through seeing yourself next to the person you're trying to emulate.

## The Goal

Help upcoming bowlers:
- **Understand** their own bowling action (most have never seen it analyzed)
- **Compare** to the bowlers they admire (gives direction, not prescription)
- **Discover** what makes their action unique (every body is different — that's OK)
- **Improve** by seeing specific postural differences they can work on

## The Philosophy

**No preaching.** We don't tell you your action is "wrong." There is no one correct bowling action. Malinga bowls from his hip. Bumrah has a hyperextended arm. Anderson is 40 and still swinging it. All different. All elite.

**No hard rules.** A bent front knee isn't "bad" — it's a style. A low arm slot isn't "wrong" — Malinga took 500 wickets with it. The system shows differences, not verdicts.

**Guides, not prescriptions.** "Your hip-shoulder separation is 19° less than Steyn's. Steyn uses this extra rotation to generate pace. If pace is your goal, this is worth exploring." Not: "You must fix this."

**Every body is unique.** Two bowlers can have identical techniques and different results because of height, strength, flexibility, body proportions. The system acknowledges this. "You're 5'8" comparing to Steyn at 5'11" — your stride will naturally be shorter. Focus on the ratios, not the absolutes."

**The idol as compass, not destination.** The pro bowler is a reference point. A direction to explore. Not a template to copy exactly. The user's job is to find what works for THEIR body, using the comparison as a guide.

## IMPORTANT PRINCIPLES

1. **We NEVER tell anyone how to bowl.** We only find relevant info matching actions based on their current action.
2. **We show, not prescribe.** The pointers are: these bowlers excel at these points. Pick yours.
3. **The system is a menu, not a prescription.** The user discovers. The system informs. Nobody preaches.
4. **No scores. No grades. No "you're doing it wrong."**
5. **Every action is valid.** Malinga, Bumrah, Anderson — all wildly different, all elite.

## What the User Gets — The Core Output

### Step 1: Hard Filter (before any matching)

The system first filters the 1000-bowler database to a relevant subset:

```
Bowling arm:      right / left (detected automatically by MediaPipe)
Arm rotation:     over-the-top / round-arm / sling (detected from arm arc geometry)
Pace category:    fast / medium / spin (user self-selects or detected from action speed)
```

A right-arm over-the-top fast bowler is ONLY matched against other right-arm over-the-top fast bowlers. No comparing apples to oranges.

### Step 2: Overall Top 5 Closest (within the filtered subset)

```
Among right-arm fast bowlers, your 5 closest action matches:

1. James Anderson — similar knee brace, similar lean
2. Chris Woakes — similar hip rotation
3. Stuart Broad — similar stride profile
4. Tim Southee — similar overall profile
5. Kyle Jamieson — similar trunk angle

Tap any bowler to see the side-by-side.
```

No verdict. No score. Just: here are 5 real bowlers in your category whose actions most resemble yours. See what they do. Learn what you want.

### Step 3: Phase-Wise Matches (deeper exploration)

Beyond the overall top 5, the user can explore who in their filtered subset matches them at EACH phase:

```
Your action broken down (right-arm fast bowlers):

FRONT FOOT BRACE:
  Most similar to: Anderson, Broad, Woakes
  These bowlers all have a firm front leg like yours.
  They tend to generate good seam position.

HIP-SHOULDER SEPARATION:
  Most similar to: Bumrah, Rabada, Archer
  Your hip rotation resembles these express pace bowlers.
  They use this rotation to generate raw speed.

TRUNK LEAN:
  Most similar to: Cummins, Hazlewood, Starc
  Your trunk angle at release is similar to these bowlers.
```

The user might have Anderson's knee and Bumrah's hip rotation — a unique combination within the right-arm fast subset. That's THEIR action. The system helps them understand it.

### What the user does with this

They browse. They tap. They see the side-by-side. They think: "Interesting — among right-arm fast bowlers, my hip rotation is like Bumrah's but my knee is like Anderson's."

That's self-directed learning. We provided the information. They made the decision.

---

## What the User Gets

### Free (content — Instagram/YouTube)
Annotated breakdowns of international bowlers. The content that brings them to the site. Shows what world-class technique looks like, visualized.

### Paid ($1 — the comparison)

**Input:** Side-on video of their bowling delivery (3-10 seconds, phone camera is fine)

**Process:**
1. Verify clip is side-on (automatic, instant, before payment)
2. Pay $1
3. Click on yourself in one frame (SAM 2 annotation — like the Meta demo)
4. Wait 1-2 minutes

**Output: The Comparison Card**

Two figures. Same size. Same delivery phase. Your body next to your idol's body.

```
        YOU                    STEYN
    [your figure]          [steyn figure]
    at front foot          at front foot

    Front knee: 129°          172°
    Hip-shoulder: 31°          46°
    Trunk lean: 15°            8°

    "Steyn braces his front leg straighter — this gives him
     a firmer platform to rotate over. Worth exploring if
     you want more pace, but some great bowlers flex more.
     Find what works for your body."
```

No scores. No percentages. No "DNA match." Just: here's you, here's them, here are the visible differences, here's what they might mean.

**The auto-match:** The system picks the closest international bowler automatically — filtered by bowling arm and pace type. The user doesn't choose. The system says "Based on your action, you're most similar to Anderson among our right-arm pace bowlers."

**Language:** English, Tamil, Hindi. The descriptive text is generated by Gemini in the user's preferred language. Cricket terminology localized properly.

## Why Side-On Only

Side-on is the standard angle for bowling analysis worldwide. Every coaching manual, every biomechanics paper, every broadcast slow-mo replay uses side-on.

From side-on:
- Front knee angle is clearly visible
- Hip-shoulder separation is measurable
- Trunk lean is visible
- Stride length is measurable
- Bowling arm arc is visible

From other angles, these metrics are unreliable due to 2D projection.

We verify side-on BEFORE payment using MediaPipe: if left/right shoulder x-coordinates are too far apart, it's not side-on. Instant check, no cost.

If the clip isn't side-on, we tell the user: "For the best comparison, film from the side. Here's a quick guide." Not a rejection — a helpful redirect.

## What We Measure

Only metrics that are **reliable at 30fps from a side-on phone camera:**

| Metric | What it tells you |
|--------|------------------|
| Front knee angle at landing | How stiff your brace is (straight = firm platform, bent = absorbing energy) |
| Hip-shoulder separation | How much rotational energy you're storing before release |
| Trunk lateral lean | How much you're tilting sideways (more lean = more injury risk, less = more upright power) |

Three metrics. Not five. Not ten. Three that we can measure honestly and explain clearly.

We dropped stride length (computation was unreliable) and arm slot (changes too fast at 30fps).

## The International Bowler Database

Start with 5. Add more over time. Each bowler processed once from a clean side-on clip:

**Right-arm pace:**
- Dale Steyn — the textbook side-on action
- Jasprit Bumrah — the unique action (shows that different works)

**Right-arm medium:**
- James Anderson — longevity, classic swing bowler

**Left-arm pace:**
- Mitchell Starc — the left-arm comparison point

**Unique:**
- Lasith Malinga — the sling (shows extreme difference is OK)

Each stored as:
```json
{
  "id": "steyn",
  "name": "Dale Steyn",
  "country": "South Africa",
  "bowling_arm": "right",
  "pace_type": "fast",
  "height_cm": 179,
  "tagline": "The textbook side-on fast bowler",
  "angles": {
    "front_knee": 172,
    "hip_shoulder_sep": 46,
    "trunk_lean": 8
  },
  "phase_frame": "bowler_db/steyn_front_foot.png",
  "isolated_figure": "bowler_db/steyn_isolated.png"
}
```

## Auto-Matching

Simple. Honest. No overclaiming.

```
1. Detect bowling arm (left/right) from MediaPipe
2. Within same-arm bowlers, find smallest angle distance:
   distance = |user.front_knee - bowler.front_knee| +
              |user.hip_shoulder - bowler.hip_shoulder| +
              |user.trunk_lean - bowler.trunk_lean|
3. Smallest distance = closest match
```

Manhattan distance, not cosine similarity. Simpler, more interpretable, doesn't need normalization.

The result: "Your action is most similar to Anderson's among our right-arm bowlers."

If the user is left-arm and we only have Starc, they get compared to Starc. As we add more bowlers, matches get more meaningful.

## Pre-Payment Validation

Before taking $1:
1. Upload clip
2. Instant checks (< 2 seconds, CPU only, no API calls):
   - Is it a valid video? (cv2 can decode)
   - Is it 3-10 seconds? (duration check)
   - Is there a person? (MediaPipe detects at least one pose)
   - Is it roughly side-on? (shoulder x-spread < threshold)
3. If any check fails → helpful message, no payment
4. If all pass → "Ready to analyze. $1 to continue."

## Cost

| Item | Cost |
|------|------|
| SAM 2 (Replicate) | $0.05 |
| Gemini (text) | $0.01 |
| Stripe fee | $0.33 |
| Buffer (failures) | $0.05 |
| **Total** | **~$0.44** |
| **Revenue** | **$1.00** |
| **Margin** | **$0.56** |

## What We Don't Do

- Don't claim exact biomechanical measurement
- Don't prescribe coaching changes
- Don't promise pace improvements
- Don't compare across different camera angles
- Don't use unreliable metrics (arm speed, elbow flex, wrist snap)
- Don't tell the user they're "wrong"
- Don't pretend this replaces a real coach

## What We Do

- Show you your action next to a pro's action
- Measure 3 reliable postural differences
- Explain what those differences might mean
- Let you decide what to work on
- Make it fun, shareable, and educational
- In your language

## Roadmap

### Phase 1: Build DB + Manual Input Matching (NOW)

**Goal:** 10 bowlers in DB. Interface takes JSON input → returns top 5 matches.

```
Step 1: Find 10 side-on clips (YouTube, 5 right-arm, 3 left-arm, 2 unique)
Step 2: SAM 2 extract each bowler (manual clicks, ~30 min each on CPU)
Step 3: MediaPipe → measure 3 angles at front-foot-contact frame
Step 4: Store as JSON in bowler_db/
Step 5: Build matching function:
        Input:  {"bowling_arm": "right", "pace_type": "fast",
                 "front_knee": 145, "hip_shoulder_sep": 31, "trunk_lean": 15}
        Output: top 5 matches with distances
Step 6: Simple web page to enter angles manually + see matches
```

**Effort:** ~1 week
**Proves:** The pipeline works end-to-end. Matching is meaningful.

### Phase 2: Scale DB to 50-100 bowlers

**Goal:** Enough bowlers that matches are genuinely close within each category.

```
Step 1: Batch-process clips (tooling from Phase 1 speeds this up)
Step 2: Cover all categories: right/left × fast/medium/spin × over/round/sling
Step 3: Add phase-wise angles (not just front-foot-contact)
Step 4: Validate: do the top 5 matches make intuitive cricket sense?
```

**Effort:** ~2 weeks
**Proves:** The matching produces results that cricket people find credible.

### Phase 3: User Video Input (the $1 product)

**Goal:** User uploads their clip → system extracts angles → matches against DB.

```
Step 1: Side-on detection (code check, before payment)
Step 2: SAM 2 self-annotation (user clicks on themselves)
Step 3: MediaPipe → angles extracted automatically
Step 4: Matching against DB → top 5 overall + phase-wise
Step 5: Comparison card rendered
Step 6: Stripe payment integration
```

**Effort:** ~2-3 weeks
**Proves:** Users will pay $1 for this.

### Phase 4: Scale to 1000 bowlers + multilingual

**Goal:** Comprehensive reference library. Tamil/Hindi support.

```
Step 1: Batch-process remaining bowlers (tooling is mature by now)
Step 2: Gemini multilingual coaching observations
Step 3: Browse/search on website (free, drives traffic)
Step 4: Content creation pipeline for social media
```

**Effort:** ~4-6 weeks
**Proves:** This is a sustainable business.

### Feasibility Assessment

| Phase | Feasible? | Risk |
|-------|-----------|------|
| Phase 1 (10 bowlers, manual input) | YES — proven tech, small scope | Low |
| Phase 2 (50-100 bowlers) | YES — same process, just more clips | Medium (finding quality side-on clips for all) |
| Phase 3 (user video input) | YES — SAM 2 + MediaPipe proven | Medium (diverse user clip quality) |
| Phase 4 (1000 bowlers) | YES but time-intensive | High (50+ hours of clip processing) |

### What Could Kill This

1. **3 angles isn't enough signal** — if all right-arm fast bowlers look identical on 3 metrics, matching is meaningless. Mitigation: test with 10 bowlers first. If they cluster too tightly, add more metrics or switch approach.
2. **Side-on clips don't exist for many bowlers** — some only have broadcast footage. Mitigation: accept "roughly side-on" for the DB, strict side-on for user clips.
3. **Nobody cares** — the comparison might not be interesting enough to share or pay for. Mitigation: Phase 1 is cheap to test. Kill it early if there's no interest.

---

## Experiments Completed

| Experiment | Result |
|-----------|--------|
| Angle determinism (3 runs) | PASSED — identical every time |
| Front knee measurement | Plausible (129° amateur vs 176° Steyn) |
| Hip-shoulder separation | Plausible (31° amateur vs 46° Steyn) |
| SAM 2 bowler isolation | WORKING (manual clicks, full body) |
| MediaPipe on isolated figure | WORKING (clean single-person detection) |
| Side-on detection | Feasible (shoulder x-spread threshold) |

## Experiments Still Needed

1. Fix trunk lean formula and verify
2. Generate comparison card image (side-by-side figures)
3. Test auto-matching with 3+ bowlers
4. Test Gemini multilingual coaching text
5. End-to-end timing (upload → result in <5 min)
