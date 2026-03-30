# wellBowled.ai — Product Spec v2 (Feasible)

Addresses all 15 Codex review comments. Grounded in what's proven experimentally.

---

## What We're Selling

**"See how your bowling action compares to the pros."**

NOT: precise biomechanical measurement.
NOT: coaching prescription.
IS: visual, educational, fun comparison of bowling posture at key moments.

The framing is "style comparison" — like a personality quiz for your bowling action. Entertaining, educational, shareable. Not a medical-grade analysis.

---

## Two Products (Separate Truth Standards)

### Product 1: Content (editorial, can interpret)
- Annotated videos of international bowlers
- "Bumrah's hip rotation is extraordinary — look at that separation"
- Can use approximate language, visual storytelling
- Purpose: marketing, brand building, drive traffic

### Product 2: Paid Comparison ($1, must be defensible)
- User's posture compared to a pro at matching delivery phases
- Shows angle differences, not prescriptions
- "Your front knee at landing: 145°. Steyn at landing: 172°. Difference: 27°"
- Does NOT say "this will add 10 km/h" — says "this is the biggest postural difference"
- Purpose: revenue, user engagement, shareable result

---

## Paid Comparison — User Flow

```
1. Land on wellBowled.ai
2. Pay $1 (Stripe) — BEFORE any compute
3. Upload clip (3-10 sec, requirements shown)
4. SAM 2 self-annotation:
   - See a frame from their clip
   - Click on themselves (green mask grows)
   - "Looks good? → Analyze"
5. Processing (30-90 sec, loading bar):
   - SAM 2 propagation (cloud GPU)
   - MediaPipe pose extraction
   - Phase detection + angle measurement
6. Auto-match:
   - Filter by bowling arm (detected by MediaPipe)
   - Match against bowler database by posture similarity
   - "Your closest style match: Dale Steyn (side-on fast)"
7. Pick language (English / Tamil / Hindi)
8. Receive:
   - Comparison card image
   - Optional: user can browse other bowlers to compare
```

Payment is BEFORE compute. Failed clips get a refund or retry. No abuse vector.

---

## Clip Acceptance Contract

User is shown these requirements before upload:

```
✓ 3-10 seconds long
✓ Shows one full delivery (run-up through release)
✓ Bowler clearly visible (not too far, not cut off)
✓ Camera roughly steady (not shaking wildly)
✓ Minimum 480p resolution
✓ Side-on angle preferred (gives best comparison)
✗ No slow-motion clips (must be real-time 25-30fps)
✗ No screen recordings of other videos
```

After upload, Gemini Flash validates:
- Is there a bowler? Is the delivery visible?
- Quality score 1-10. Below 4 → reject with guidance.

---

## What We Measure (honest about limitations)

### Reliable at 30fps (use these):

| Metric | How | Why reliable |
|--------|-----|-------------|
| Front knee angle at landing | Angle at knee joint (hip-knee-ankle) | Holds for 3-5 frames, slow-changing |
| Hip-shoulder separation | Angle between hip line and shoulder line | Proven (X-factor pipeline), slow-changing |
| Trunk lateral lean | Angle from vertical at spine midpoint | Holds for several frames |
| Stride length ratio | Ankle-to-ankle distance / torso length | Static measurement, one frame |

### Unreliable at 30fps (do NOT use):

| Metric | Why unreliable |
|--------|---------------|
| Arm slot / arm speed | Changes 90° in 2 frames |
| Elbow flexion | ICC needs 240fps for this |
| Wrist snap timing | Changes in 1 frame |
| Energy transfer timing | Peaks overlap within 1-2 frames |

### Camera angle caveat:

Absolute angles are affected by camera position. We mitigate by:
- Recommending side-on filming
- Comparing only metrics stable across angles (hip-shoulder sep is most stable)
- Showing the comparison VISUALLY (side-by-side frames) not just numbers
- Adding disclaimer: "Angles are approximate from video. Film from side-on for best accuracy."

---

## Bowler Matching

### Step 1: Auto-detect bowling arm
MediaPipe detects which wrist moves fastest during delivery → left or right arm bowler. Binary filter, reliable.

### Step 2: Action archetype (simple, not over-classified)
Three categories only:
```
PACE:     Bowls fast/medium-fast (arm comes over the top or high)
MEDIUM:   Medium pace, emphasis on swing/seam
SPIN:     Wrist spin or finger spin (completely different metrics)
```

Detected by: arm speed relative to body speed. Fast bowlers have wrist velocity >> hip velocity. Spinners have wrist rotation >> linear wrist velocity.

Do NOT try to classify side-on/front-on/sling — too granular, too error-prone from user video.

### Step 3: Posture similarity within archetype
```
Angle vector: [front_knee, hip_shoulder_sep, trunk_lean, stride_ratio]
Similarity: cosine similarity (normalized)
```

4 metrics, not 5. Dropped arm_slot (unreliable at 30fps).

Result: "Your closest match among right-arm pace bowlers: Dale Steyn"

### What "closest match" means (honest framing)
"Based on your body position at key delivery moments, your action most resembles Steyn's among the bowlers in our database. This is a postural similarity score, not a performance prediction."

NOT: "You bowl like Steyn."
NOT: "You have 82% Steyn DNA."
IS: "Your posture at these moments is closest to Steyn's."

---

## The Comparison Card

```
┌──────────────────────────────────────────┐
│                                          │
│   YOUR ACTION vs DALE STEYN              │
│   Closest style match (pace bowlers)     │
│                                          │
│   [your frame]      [steyn frame]        │
│   at FRONT FOOT     at FRONT FOOT        │
│                                          │
│   Front Knee:    145°  vs  172°          │
│   Hip-Shoulder:   28°  vs   47°          │
│   Trunk Lean:     34°  vs   22°          │
│   Stride:         85%  vs   92%          │
│                                          │
│   BIGGEST DIFFERENCE:                    │
│   Hip-shoulder separation (19° gap)      │
│   Steyn's hips rotate further ahead      │
│   of his shoulders before release.       │
│                                          │
│   📐 Angles measured from video.         │
│   Film side-on for best accuracy.        │
│                                          │
│   wellBowled.ai                          │
└──────────────────────────────────────────┘
```

No speed claims. No "this will add X km/h." Just the measured differences and which is biggest.

Gemini generates the description text in the chosen language.

---

## Bowler Database (corrected taxonomy)

### Right-arm pace
- Dale Steyn (SA) — 150 km/h, side-on
- Jasprit Bumrah (IND) — 145 km/h, unique/chest-on
- Pat Cummins (AUS) — 145 km/h, side-on
- Kagiso Rabada (SA) — 145 km/h, side-on
- Jofra Archer (ENG) — 150 km/h, side-on

### Right-arm medium
- James Anderson (ENG) — 135 km/h, side-on, swing
- Josh Hazlewood (AUS) — 135 km/h, side-on, seam
- Glenn McGrath (AUS) — 135 km/h, side-on, line/length

### Left-arm pace
- Mitchell Starc (AUS) — 155 km/h, front-on
- Mitchell Johnson (AUS) — 150 km/h, side-on
- Trent Boult (NZ) — 140 km/h, side-on
- Wasim Akram (PAK) — 145 km/h, side-on

### Left-arm medium
- Sam Curran (ENG) — 130 km/h
- Chaminda Vaas (SL) — 130 km/h

### Unique action
- Lasith Malinga (SL) — sling/round-arm
- Shaun Tait (AUS) — extreme pace, slinging

Start with 5 for MVP: **Steyn, Bumrah, Starc, Anderson, Malinga**

Each bowler needs: one clean 3-5 sec side-on clip processed through SAM 2 + MediaPipe. Angles stored. Phase frames stored. One-time effort per bowler.

---

## Experiments to Run Today

### Experiment 1: Angle measurement accuracy
- Take the nets clip (already isolated by SAM 2)
- Measure front_knee, hip_shoulder_sep, trunk_lean, stride_ratio at frame 28 (arm over)
- Manually verify by looking at the frame: does 145° knee look right?
- Run 3 times: must be identical (determinism)

### Experiment 2: Two-bowler comparison
- Measure same 4 angles on the nets clip bowler
- Measure same 4 angles on the Steyn side-on clip
- Produce a comparison card image
- Visually verify: does the comparison look credible?

### Experiment 3: Auto bowler matching
- Create angle vectors for nets bowler, Steyn, Bumrah (from existing clips)
- Compute cosine similarity
- Check: does the matching make intuitive sense?

### Experiment 4: Gemini multilingual coaching text
- Send comparison data to Gemini Pro
- Get coaching text in English, Tamil, Hindi
- Check: is the text specific and sensible in all 3 languages?

### Experiment 5: End-to-end user flow mock
- Upload the nets clip
- Use SAM 2 web UI to annotate
- Run analysis
- Generate comparison card
- Time the whole process
- Target: under 5 minutes

---

## Cost Model (revised, conservative)

| Item | Cost |
|------|------|
| SAM 2 (Replicate cloud GPU) | $0.05 |
| Gemini Pro (coaching text) | $0.01 |
| Gemini Flash (clip validation) | $0.001 |
| Stripe fee (on $1) | $0.33 |
| Server/hosting (amortized) | $0.02 |
| Failed job buffer (10% fail rate) | $0.05 |
| **Total cost** | **~$0.46** |
| **Revenue** | **$1.00** |
| **Margin** | **$0.54 (54%)** |

At 50 analyses/day = $27/day margin = $810/month.
At 200 analyses/day = $108/day = $3240/month.

---

## MVP Build Order

1. **Today: Run experiments 1-4** (prove angles work, comparison is credible)
2. **This week: Bowler database** (5 bowlers, process clips, store angles)
3. **This week: Comparison card renderer** (side-by-side image generator)
4. **Next week: Web UI** (upload + SAM 2 annotation + payment)
5. **Next week: Gemini multilingual** (3 languages)
6. **Ongoing: Content creation** (annotated international bowler videos)

---

## What Changed from v1 (addressing Codex review)

| # | Codex concern | Fix |
|---|--------------|-----|
| 1 | Claims too strong | Reframed as "style comparison" not "DNA match" |
| 2 | Matching underpowered | Acknowledged — 4 angles is coarse. Visual comparison is the real product, not the % |
| 3 | Filters not operational | Simplified to 3 categories. Arm detected by MediaPipe. |
| 4 | Compute before payment | Payment FIRST, then compute |
| 5 | Pricing too low | Revised cost model with Stripe fees, failure buffer. 54% margin. |
| 6 | Coaching overclaims | Removed "add 5-10 km/h." Now just shows differences. |
| 7 | Schema inconsistent | To be defined properly in experiment phase |
| 8 | Taxonomy mistakes | Fixed bowler list with correct categories |
| 9 | Side 1 vs Side 2 mixed | Separated with explicit truth standards |
| 10 | Phase model overfit | Only use phases we can reliably detect at 30fps |
| 11 | Language underspecified | Acknowledged — validate in experiment 4 |
| 12 | Camera angle variation | Added explicit caveat, recommend side-on, visual comparison compensates |
| 13 | No clip acceptance | Added acceptance contract with requirements |
| 14 | Manual override weakens match | Framed as "browse other bowlers" not override |
| 15 | Cost model optimistic | Added Stripe, failure buffer, realistic margin |
