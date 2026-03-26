# Top 30 Analysis Values — What to Measure & Show

> Each value answers: "What number or verdict can I put on screen
> that makes a bowler, coach, or fan say 'I didn't know that'?"

---

## Speed & Power

| # | Value | What It Shows | Why Viewers Care |
|---|-------|---------------|------------------|
| 1 | **Ball Speed (kph)** | Release velocity | The universal cricket number. Everyone understands 150 kph. |
| 2 | **Run-Up Speed (kph)** | Approach velocity | How much pace comes from the run vs the arm? Surprises people. |
| 3 | **Wrist Snap Speed (m/s)** | Wrist velocity at release | The invisible multiplier — "that's where the extra 10 kph comes from." |
| 4 | **Speed Efficiency %** | Ball speed ÷ run-up speed ratio | Are you converting run-up momentum into ball speed? Low = wasted energy. |

## Angles — The Mechanics

| # | Value | What It Shows | Why Viewers Care |
|---|-------|---------------|------------------|
| 5 | **Front Knee Angle** | Brace leg angle at delivery | Textbook says ~160-170°. Straight leg = more pace. Bent = pace leak. |
| 6 | **Bowling Arm Elbow Angle** | Arm straightness | >15° flex = illegal action (ICC rule). Most controversial metric in cricket. |
| 7 | **Shoulder Rotation** | Degrees of shoulder turn through delivery | Directly linked to pace. Elite: 40-50°+ of counter-rotation. |
| 8 | **Hip-Shoulder Separation** | X-factor: angle between hip line and shoulder line | The torque generator. Peak separation = peak pace potential. |
| 9 | **Trunk Lateral Flexion** | Side-bend at release | Too much = lower back injury risk. The injury predictor. |
| 10 | **Release Arm Angle** | Arm position at ball release (clock position) | 12 o'clock = over-arm, 10 o'clock = round-arm. Defines bowling type. |

## Distances & Positions

| # | Value | What It Shows | Why Viewers Care |
|---|-------|---------------|------------------|
| 11 | **Stride Length** | Distance from back foot to front foot | As % of body height (80-100% optimal). Too short = no pace, too long = injury. |
| 12 | **Release Height** | How high above ground the ball leaves the hand | Tall bowlers' advantage quantified. Bounce = release height. |
| 13 | **Front Foot Landing Position** | Where the front foot plants relative to crease | Inside/outside line, how close to the crease — no-ball risk. |
| 14 | **Head Position Stability** | How much the head moves during delivery | Stable head = accuracy. Wobbly head = control problems. |

## Timing & Rhythm

| # | Value | What It Shows | Why Viewers Care |
|---|-------|---------------|------------------|
| 15 | **Delivery Time** | Duration from back foot contact to ball release | Elite: ~0.15-0.20s. Shows how explosive the action is. |
| 16 | **Run-Up Rhythm** | Acceleration pattern through approach | Smooth build-up vs sudden sprint. Rhythm = repeatability = accuracy. |
| 17 | **Ground Contact Time** | How long the front foot is on the ground at delivery | Shorter = explosive. Longer = absorbing energy (pace leak). |
| 18 | **Phase Timing Split** | Time in each phase (run-up / loading / release / follow-through) | Where the bowler spends time = where the action lives. |

## Energy & Chain

| # | Value | What It Shows | Why Viewers Care |
|---|-------|---------------|------------------|
| 19 | **Kinetic Chain Score** | How well energy transfers from ground → legs → torso → arm → wrist | A-F grade. Broken chain = wasted pace. Complete chain = effortless speed. |
| 20 | **Front Leg Brace Score** | How effectively the front leg converts momentum to rotation | The "pole vault" of bowling. Stiff leg = catapult. Collapsed = dead. |
| 21 | **Follow-Through Completion %** | Does the bowling arm complete full rotation after release? | Incomplete = shoulder strain. Complete = natural deceleration. |

## Comparison & Identity

| # | Value | What It Shows | Why Viewers Care |
|---|-------|---------------|------------------|
| 22 | **Bowling DNA Match %** | Similarity to famous bowler | "You're 87% Bumrah" — the most shareable stat in the entire system. |
| 23 | **Bowler Type Classification** | Fast / fast-medium / medium / spin + action type | "You're a chest-on fast-medium bowler" — identity in one sentence. |
| 24 | **Consistency Score** | Variation across multiple deliveries | Low variation = reliable. High variation = unpredictable (could be good or bad). |

## Health & Risk

| # | Value | What It Shows | Why Viewers Care |
|---|-------|---------------|------------------|
| 25 | **Lower Back Stress Index** | Combined trunk flexion + rotation load | #1 injury site for fast bowlers. Red zone = "your back is screaming." |
| 26 | **Shoulder Load** | Arm velocity + range of motion stress | Overuse predictor. High load + high volume = rotator cuff risk. |
| 27 | **Mixed Action Alert** | Detecting mixed bowling action (front-on hips + side-on shoulders) | The proven injury mechanism. If detected, viewer needs to fix immediately. |

## Verdict & Grades

| # | Value | What It Shows | Why Viewers Care |
|---|-------|---------------|------------------|
| 28 | **Phase Grades (A+ to D)** | Letter grade per phase: run-up, loading, release, follow-through | Gamification. Everyone wants an A. "Your run-up is A but your release is C+." |
| 29 | **Overall Action Rating** | Single score out of 100 | The headline number. "Bumrah: 94/100. Your backyard mate: 61/100." |
| 30 | **Top Improvement Priority** | The ONE thing to fix that gives the biggest gain | "Fix your front knee brace. Estimated +8 kph gain." Actionable = valuable. |

---

## What We Can Compute Today vs Later

### Now (pose estimation from 2D video)
Values 1*, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 18, 22, 23, 24, 28, 29, 30
(*speed requires stump calibration or known distance)

### Soon (enhanced pose + multi-frame analysis)
Values 2, 3, 4, 15, 16, 17, 19, 20, 21, 25, 26, 27

### Key Insight
**18 of 30 values are computable TODAY** from the existing skeleton data.
The remaining 12 need multi-frame velocity calculation and force estimation —
achievable with the same pose data, just more computation.

---

## The Hierarchy for Content

**First 3 seconds of any video — show ONE of these:**
- Ball speed (everyone gets it)
- Elbow angle (controversy)
- DNA match % (curiosity)

**Middle of video — show 3-5 of these with skeleton overlay.**

**End of video — show the verdict:**
- Phase grades OR overall rating OR top improvement priority

This is the formula. Speed → Skeleton → Verdict.
