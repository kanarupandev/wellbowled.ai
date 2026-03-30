# wellBowled.ai — Product Spec

## Overview

Two-sided product:
1. **Content (marketing):** Annotated international bowler videos on Instagram/YouTube
2. **Paid comparison ($1):** User uploads clip, gets personalized comparison to international bowler

## Side 1: Content Creation

Annotated videos of international bowlers (Bumrah, Steyn, Starc, Anderson, etc.) with skeleton overlay, phase annotations, angle measurements. Posted on Instagram/YouTube with wellBowled.ai watermark. Drives traffic to the site.

## Side 2: Paid Comparison ($1)

### User Flow

```
1. Land on wellBowled.ai (from social media content)
2. Upload bowling clip (3-10 seconds)
3. Interactive SAM 2 annotation:
   - User clicks on themselves in one frame
   - Green mask grows with each click (real-time feedback)
   - Keep clicking until full body is highlighted
   - "Looks good? → Analyze"
4. SAM 2 propagates masks through all frames (30-60 sec, cloud GPU)
5. MediaPipe extracts pose → angles computed at 5 delivery phases
6. Bowler matching:
   AUTO: system filters → matches → "You're 82% Steyn among right-arm fast bowlers"
   OR MANUAL: user searches by name, picks any bowler
7. Language: English / Tamil / Hindi
8. Pay $1 (Stripe)
9. Receive in <5 minutes:
   - Comparison card image (shareable, 1080x1920)
   - Short annotated video (15-20s)
   - Both watermarked wellBowled.ai
```

### Bowler Matching Logic

**Step 1: Hard filter (eliminate incompatible bowlers)**
```
Filter by bowling arm:    left / right
Filter by action type:    side-on / front-on / sling / round-arm / unique
Filter by pace category:  fast (140+) / medium-fast (130-140) / medium (120-130) / spin
```

**Step 2: Soft match within filtered subset**
```
Compute angle vector per bowler at each phase:
  [front_knee, hip_shoulder_sep, trunk_lean, stride_pct, arm_slot]

Cosine similarity between user's vector and each bowler in filtered subset.
Best match = highest similarity.
```

A left-arm sling bowler is never compared to a right-arm over-the-top bowler. The comparison is always within the same bowling archetype.

**Step 3: Present result**
```
"Among right-arm fast bowlers, you're closest to Dale Steyn (82% match)"
Also show: "65% Bumrah, 58% Starc" as alternatives
User can override: "Compare me to Bumrah instead"
```

### The Comparison Card

```
┌──────────────────────────────────────────┐
│                                          │
│   YOU  vs  DALE STEYN  (82% match)       │
│   Right-arm fast · Side-on action        │
│                                          │
│   [your frame]      [steyn frame]        │
│   at FRONT FOOT     at FRONT FOOT        │
│                                          │
│   Front Knee:    145°  vs  172°  (-27°)  │
│   Hip-Shoulder:   28°  vs   47°  (-19°)  │
│   Trunk Lean:     34°  vs   22°  (+12°)  │
│   Stride:         85%  vs   92%  (-7%)   │
│                                          │
│   VERDICT:                               │
│   "Your biggest gap is hip-shoulder      │
│    separation. Lead with the hip before  │
│    the shoulders open. This alone could  │
│    add 5-10 km/h."                       │
│                                          │
│   🏏 82% Steyn DNA                       │
│                                          │
│   wellBowled.ai                          │
└──────────────────────────────────────────┘
```

Tamil version:
```
"உங்கள் மிகப்பெரிய இடைவெளி இடுப்பு-தோள்பட்டை
 பிரிவினை. தோள்பட்டைகள் திறக்கும் முன்
 இடுப்பை முன்னிலையில் வைக்கவும்."
```

Hindi version:
```
"आपका सबसे बड़ा अंतर हिप-शोल्डर सेपरेशन है।
 कंधे खुलने से पहले हिप को आगे ले जाएं।"
```

### International Bowler Database

Pre-computed once per bowler. Stored as JSON:

```json
{
  "bowler_id": "steyn",
  "name": "Dale Steyn",
  "country": "South Africa",
  "height_cm": 179,
  "stock_pace_kmh": 150,
  "bowling_arm": "right",
  "action_type": "side-on",
  "pace_category": "fast",
  "searchable_names": ["dale steyn", "steyn", "dale"],
  "phase_angles": {
    "ground_contact": {
      "front_knee": 168,
      "hip_shoulder_sep": 42,
      "trunk_lean": 18,
      "stride_pct_height": 90,
      "arm_slot_clock": 12
    },
    "front_foot_brace": { ... },
    "hip_rotation": { ... },
    "arm_over": { ... },
    "release": { ... }
  },
  "angle_vector": [168, 42, 18, 90, 12, ...],
  "source_clip": "resources/bowler_db/steyn_nets_3sec.mp4",
  "source_camera_angle": "side-on",
  "phase_frames": {
    "ground_contact": "resources/bowler_db/steyn_phase_1.png",
    "front_foot_brace": "resources/bowler_db/steyn_phase_2.png",
    "arm_over": "resources/bowler_db/steyn_phase_4.png",
    "release": "resources/bowler_db/steyn_phase_5.png"
  }
}
```

Target: 20-30 bowlers covering:
- Right-arm fast (Steyn, Bumrah, Starc, Archer, Rabada)
- Right-arm medium-fast (Anderson, Broad, Hazlewood, McGrath)
- Left-arm fast (Wasim, Boult, Starc, Johnson)
- Left-arm medium (Anderson... wait he's right)
- Sling/round-arm (Malinga, Bumrah's unique)
- Spin (Warne, Murali, Ashwin, Bumrah) — different metrics

### Gemini's Role

One call per analysis for multilingual coaching text:

```
Prompt:
"You are a cricket bowling coach. Given these comparison results:

Bowler: {user_description}
Compared to: {bowler_name} ({match_pct}% match)
Category: {bowling_arm} {action_type} {pace_category}

Angles:
  Front Knee: User {user_knee}° vs {bowler_name} {bowler_knee}°
  Hip-Shoulder: User {user_hss}° vs {bowler_name} {bowler_hss}°
  Trunk Lean: User {user_lean}° vs {bowler_name} {bowler_lean}°
  Stride: User {user_stride}% vs {bowler_name} {bowler_stride}%

Generate a 3-line coaching verdict in {language}.
Line 1: The biggest gap and what it means
Line 2: Why fixing this matters (pace / accuracy / injury)
Line 3: One specific drill or focus to improve

Be specific to these numbers. Not generic advice.
Use cricket terminology appropriate for the language.
Languages: English, Tamil (தமிழ்), Hindi (हिंदी)"
```

### Angles Measured (reliable at 30fps)

| Angle | What it measures | How computed | Reliable? |
|-------|-----------------|-------------|-----------|
| Front knee | Brace stiffness at landing | Angle at joint 26 (hip-knee-ankle) | ✓ holds 3-5 frames |
| Hip-shoulder separation | Rotational energy storage | Angle between hip line and shoulder line | ✓ proven in X-Factor |
| Trunk lean | Lateral flexion (injury risk) | Angle from vertical at spine midpoint | ✓ holds several frames |
| Stride length | Delivery stride as % of height | Distance between ankles / torso length | ✓ static measurement |
| Arm slot | Over-the-top vs round-arm | Clock position of wrist relative to shoulder | ⚠ changes fast, measure at arm-over frame |

### Tech Stack

| Component | Tech | Cost |
|-----------|------|------|
| Frontend | Next.js or plain HTML+JS | Free (Vercel) |
| SAM 2 | Replicate API (cloud GPU) | ~$0.05/clip |
| Pose | MediaPipe (server CPU) | Free |
| Coaching text | Gemini Pro | ~$0.01 |
| Payment | Stripe | 30¢ + 2.9% |
| Hosting | Vercel + Railway/Fly.io | ~$10/mo |
| **Total per analysis** | | **~$0.40** |
| **Revenue per analysis** | | **$1.00** |
| **Margin** | | **~60%** |

### Cost Revised (with Stripe)

```
Compute: $0.06
Stripe fee: $0.33 (30¢ + 2.9% of $1)
Hosting amortized: $0.01
Total cost: ~$0.40
Revenue: $1.00
Margin: $0.60 (60%)
```

At 100 analyses/day = $60/day margin = $1800/month.

### MVP Build Order

1. **Bowler database** — process 5 bowlers (Steyn, Bumrah, Starc, Anderson, Malinga), store angle profiles
2. **Comparison engine** — filter → match → generate card image
3. **SAM 2 web UI** — polish the existing bowler_selector/app.py for user self-annotation
4. **Payment** — Stripe integration
5. **Gemini multilingual** — coaching text in 3 languages
6. **Content pipeline** — semi-automated annotation of international bowler clips for social media

### What Already Exists

- SAM 2 web UI (`bowler_selector/app.py`) — working prototype
- MediaPipe pose extraction — working, deterministic (60/60 identical)
- Angle computation — working (hip-shoulder, knee, trunk lean)
- X-Factor pipeline — working (Steyn 47°, Bumrah 41°)
- Video rendering with overlays — working
- Gemini integration — working
- Isolated bowler video — working (SAM 2 large + manual clicks)

### Risks

1. **SAM 2 on diverse user clips** — may fail on poor quality phone footage. Mitigation: user sees the mask and can retry.
2. **Camera angle variation** — user's phone angle vs international bowler's broadcast angle. Mitigation: only compare angles that are stable across angles (hip-shoulder sep is most stable).
3. **MediaPipe accuracy on amateur footage** — lower resolution, unusual clothing. Mitigation: show confidence score, allow re-upload.
4. **Bowler database effort** — processing 20-30 bowlers manually. Mitigation: start with 5, add more over time.

## codex: review comments

1. The core measurement claim is too strong for the current method. The spec still sells “personalized comparison” and “Steyn DNA” off a 5-angle vector at 30 fps, but that is not enough to support a robust cross-bowler similarity claim. The product should be framed more defensibly as archetype-style comparison, not precise DNA matching.

2. The matching model is underpowered and likely misleading. The current vector of `front_knee, hip_shoulder_sep, trunk_lean, stride_pct, arm_slot` with cosine similarity is too little signal to distinguish elite bowlers reliably, especially across different camera angles and clip quality.

3. The hard filters are not operationally defined. Filtering by `action type` and `pace category` is not machine-safe as written. Pace cannot be inferred from a casual user clip, and labels like `side-on / front-on / sling / unique` are too loose.

4. The user flow hides a major compute/product risk before payment. Running SAM2 propagation, pose extraction, comparison, and likely rendering before charging only `$1` creates abuse risk and weak unit economics unless payment is taken earlier or the pre-pay pipeline is heavily capped.

5. The pricing is probably too low for the amount of failure handling implied. Failed masks, bad clips, re-uploads, support, and payment friction will likely eat the modeled margin fast.

6. The comparison output overclaims coaching precision. Statements like “This alone could add 5-10 km/h” are too strong and not supportable from this pipeline.

7. The international bowler database schema is inconsistent and not build-ready. It mixes partial phase keys, placeholder objects, and a flat `angle_vector` without defining exact vector order, normalization, or missing-value handling.

8. The target bowler list contains obvious taxonomy mistakes, which is a bad sign for downstream ontology quality. Examples in the spec itself show category confusion.

9. Side 1 and Side 2 are mixed together but have different truth standards. The content side can tolerate more editorial interpretation; the paid comparison side cannot. The spec should separate these products more clearly.

10. The phase model is not aligned with what current clip quality reliably supports. The spec assumes more stable phase anchors than recent 30 fps findings justify.

11. Language support is underspecified operationally. English/Tamil/Hindi are listed, but there is no review policy, fallback behavior, or quality threshold for multilingual coaching text.

12. Camera angle variation is treated too lightly. It is not a small mitigation issue; it is one of the core validity risks for angle-based comparison.

13. The spec has no explicit clip acceptance contract. There is no minimum input standard for frame rate, camera angle, body visibility, final steps, lighting, or camera stability.

14. “Manual override to any bowler” weakens the credibility of the match system unless the product clearly distinguishes system-ranked nearest match from user-forced comparison.

15. The cost model is optimistic and omits moderation, retries, failed jobs, storage, and support.

Overall verdict: good direction, but not ready as a paid product spec. The biggest problem is that it jumps from a promising content/comparison concept to an overconfident paid measurement product without tightening the claims, ontology, input contract, and matching model first.
