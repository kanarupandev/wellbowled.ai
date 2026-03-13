# Prompting Techniques — wellBowled

**Research status**: Synthesized Feb 2026 from training data + existing wellBowled codebase analysis. Web search was partially blocked — findings marked VERIFIED (from codebase/docs) or TRAINING-DATA (from model knowledge, needs validation against latest Gemini 3 docs).

---

## 1. Gemini Video Fundamentals

### How Gemini Processes Video (TRAINING-DATA)

| Property | Value | Impact |
|----------|-------|--------|
| Frame sampling | ~1 fps internal | 5 frames for a 5s clip |
| Tokens per frame | 258 (fixed, regardless of resolution) | 5s clip = ~1,290 visual tokens |
| Audio tokens | 32/second | Adds ~160 tokens for 5s |
| Temporal precision | ~0.5s native | **Cannot hit 0.2s target alone** |
| Context window | ~1M tokens (Gemini 1.5/2.0) | ~1 hour of video |

**Critical implication**: Gemini's 1fps sampling means it sees ~1-2 frames of the actual delivery action (which lasts ~1.5s). Phase detection precision requires the **dual-track approach**: MediaPipe timestamps (33ms at 30fps) + Gemini semantic reasoning.

### Input Methods

| Method | Use When | Latency |
|--------|----------|---------|
| Inline bytes (<5MB) | Short clips, detection | Lowest (~no upload overhead) |
| File API (>5MB) | Long sessions, deep analysis | Upload + polling overhead |
| Multimodal Live API | Real-time streaming detection | Rolling context, no go-back |

**Existing architecture** (from wellBowled v1): Scout uses inline bytes for 120s chunks at 640x480. Expert uses inline for 5s clips. This is correct — no change needed.

---

## 2. Five Prompt Types

### 2A. Delivery Detection (Scout)

**Purpose**: Find all bowling deliveries in a video clip (3s to 5min). Ultra-low latency.

**Key technique**: Count-first-then-locate with state machine reasoning.

```
Watch the entire video. Track the bowler's state:
- IDLE: Standing, walking, not bowling
- RUN_UP: Moving toward crease with intent to bowl
- DELIVERY: Arm swing through release
- FOLLOW_THROUGH: Post-release deceleration

A delivery = transition from RUN_UP → DELIVERY.
The release point = arm at highest vertical point.

STEP 1: Count total deliveries. Output the number.
STEP 2: For each delivery, locate the release timestamp.

PHANTOM DETECTION: If a person runs up but does NOT rotate
the arm over the head AND release a ball, this is NOT a delivery.
Mark as phantom only if the run-up pattern was detected.

Output JSON:
{
  "scan_summary": "Brief description of video content",
  "candidates_considered": N,
  "confirmed_deliveries": N,
  "phantom_deliveries": N,
  "deliveries": [
    {"id": 1, "release_ts": float, "confidence": 0.0-1.0}
  ]
}
```

**Why count-first works**: Forces Gemini to commit to a number before locating. Prevents lazy scanning that skips later deliveries. The `candidates_considered` field forces narration of the search process.

**Phantom delivery detection**: The key discriminator is the arm deceleration pattern. When a ball is released, the arm decelerates differently (suddenly lighter). Gemini can usually see "ball released and traveling" vs "arm went through motion only."

### 2B. Biomechanical Deep Analysis (Expert)

**Purpose**: Per-delivery phase analysis with joint angles, feedback, and coaching.

**Key technique**: Visual landmark anchoring + reference comparison.

```
<context>
Release point is at {release_ts}s in this clip.
Setting: Any — backyard, park, indoor, net session, shadow bowling.
Camera angle: {detected_or_specified_angle}
Ball type: {ball_type_or_unknown}
Config: {junior|club|technical}
</context>

<phases>
Analyze these 6 phases around the release point:

1. Run-up: rhythm, stride consistency, approach speed
   Visual cue: body shifts from stationary to forward momentum

2. Loading/Coil: hip-shoulder separation, body alignment (side-on vs front-on)
   Visual cue: back foot plants, torso rotates away from batsman
   Reference: 30-50° hip-shoulder separation for fast bowlers

3. Release Action: arm path, elbow angle, release height
   Visual cue: bowling arm fully extended overhead, fingers opening
   Reference: Elbow extension must stay within 15° (ICC)
   IMPORTANT: Report what you SEE, not what you calculate

4. Wrist/Snap: wrist position, seam orientation
   Visual cue: wrist flexion at release, ball rotation visible

5. Head/Eyes: stability, target focus
   Visual cue: head upright vs falling away at release

6. Follow-through: arm continuation, balance, deceleration
   Visual cue: bowling arm passes opposite hip, body rotating
</phases>

<rules>
- For each phase, describe what you ACTUALLY SEE in the video
- Provide clip_ts: timestamp where each phase is best visible
- If a body part is OCCLUDED, say "NOT VISIBLE" — do not guess
- Use relative positions ("wrist above shoulder") not absolute angles
  unless pose landmark data is provided
- Confidence: HIGH/MEDIUM/LOW for each phase observation
</rules>

<output>
{
  "phases": [
    {
      "name": "Run-up",
      "status": "GOOD|NEEDS_WORK",
      "observation": "what you see",
      "tip": "one actionable point",
      "clip_ts": float,
      "confidence": "HIGH|MEDIUM|LOW"
    }
  ],
  "estimated_speed_kmh": int or "_",
  "effort": "Low|Medium|High|Max",
  "summary": "one sentence: biggest strength + priority fix",
  "legality_flag": null or "REVIEW: [reason]",
  "release_timestamp": float
}
</output>
```

**Why visual landmarks matter**: Requiring "describe what you see" before giving timestamps reduces hallucination. Gemini must ground its output in observable evidence.

### 2C. Live Gemini Prompt (Combined Good-Enough)

**Purpose**: Real-time conversational mode via Multimodal Live API. Balances detection + basic analysis in one pass.

**Key technique**: Streaming state machine + incremental output.

```
<persona>
You are a cricket bowling research partner. You observe and explore —
you do NOT coach or prescribe.

Use: "The data shows", "What if", "Worth exploring"
Never use: "You should", "Fix your", "Try to"
</persona>

<mode>
LIVE STREAMING MODE. You are receiving frames in real-time.

When you detect a bowling delivery:
1. Immediately output: {"event": "delivery_detected", "confidence": float}
2. After follow-through completes (~1s later), output quick assessment:
   {
     "event": "quick_analysis",
     "delivery_id": int,
     "top_observation": "one sentence on what stood out",
     "energy_level": "Low|Medium|High|Max",
     "notable": "one thing worth exploring deeper"
   }

Between deliveries: stay silent unless asked.

When the user asks a question:
- Reference the most recent delivery
- Use exploratory language
- End with an open question
</mode>
```

**Live API limitation**: No go-back capability. It processes frames as they arrive in a rolling context. This mode is for awareness, not precision. Deep analysis must happen post-session via the batch API.

### 2D. Legality Check (Gentle Flags)

**Purpose**: Flag potential elbow extension concerns. NOT conclusive — always framed as observation.

**Key technique**: Observation-only language + mandatory disclaimer.

```
<legality_assessment>
Observe the bowling arm from back-foot contact through release.

ICC REFERENCE: The bowling arm must not extend more than 15°
during the delivery stride. This is measured as the change in
elbow angle from BFC to release — not the absolute angle.

WHAT TO LOOK FOR:
- Does the elbow appear to straighten significantly during delivery?
- Is there visible "jerking" (rapid flex-then-extend)?
- Compare elbow angle at BFC vs at release — is there visible change?

CAMERA ANGLE WARNING:
- Side-on view: elbow extension is visible and assessable
- Front-on view: elbow angle is heavily foreshortened — FLAG AS UNRELIABLE
- Behind view: cannot assess elbow extension — FLAG AS NOT ASSESSABLE

OUTPUT:
If no concern: legality_flag = null
If potential concern: legality_flag = "REVIEW: [specific observation]"

MANDATORY FRAMING:
- "The bowling arm APPEARS to [observation]"
- "This is a visual observation from 2D video — NOT an official assessment"
- "ICC testing requires 3D motion capture in controlled conditions"
- "Consider having this reviewed by a qualified coach"

NEVER use: "illegal", "chucking", "throwing", "no-ball"
ALWAYS use: "apparent extension", "worth reviewing", "consider having checked"
</legality_assessment>
```

**Additional legality checks** (simpler, higher confidence):

| Check | Detection Method | Confidence |
|-------|-----------------|------------|
| Front-foot no-ball | Front foot position relative to crease line (if visible) | Medium — depends on camera angle |
| Beamer | Ball trajectory toward batsman's head height without bouncing | Low — hard from side-on |
| Action type | Side-on vs front-on vs mixed body alignment | Medium — detectable from hip-shoulder angles |

### 2E. Speed Estimation

**Purpose**: Produce pace outputs that align with product policy:
1. Pace Score (primary, relative)
2. Rough Speed Bucket (secondary)
3. Estimated Speed only when calibration + confidence gate passes.

Reference:
- `/Users/kanarupan/workspace/wellbowled.ai/docs/pace_score_metric_model.md`

**Three approaches, ranked by reliability:**

**Approach 1: Gemini qualitative estimation (lowest accuracy, easiest)**
```
Estimate the delivery speed category:
- Slow (<100 km/h): Spin bowler pace, looping trajectory
- Medium (100-125 km/h): Medium pace, visible ball flight
- Fast (125-145 km/h): Quick, flattish trajectory
- Express (>145 km/h): Very fast, minimal ball visibility

If ball is not visible or shadow bowling: speed = "_"

Provide: {"speed_category": "...", "estimated_kmh": int or "_", "basis": "ball_flight|arm_speed|not_assessable"}
```

**Approach 2: Biomechanical inference (medium accuracy, needs pose data)**

Arm speed correlates with delivery speed. From sports science literature:
- Run-up speed contributes ~20% of delivery speed
- Hip-shoulder separation at BFC contributes ~15%
- Shoulder rotation velocity contributes ~30%
- Arm angular velocity contributes ~25%
- Wrist snap contributes ~10%

With MediaPipe wrist velocity data, a rough regression:
```
estimated_speed ≈ wrist_angular_velocity × calibration_factor
```
Calibration factor varies by bowler build and ball type. Accuracy: +/- 15-20 km/h.

**Approach 3: Ball tracking (highest accuracy, hardest)**

Track ball position across frames with known reference distance (pitch = 20.12m).
- Requires 60fps+ for meaningful estimates (ball moves 2+ meters between 30fps frames at 140 km/h)
- 240fps (iPhone slow-mo) gives ~6cm per frame at 140 km/h — trackable
- Ball detection needs YOLO or similar, not MediaPipe
- Accuracy: +/- 5-10 km/h at 240fps with visible ball

**Recommendation**: Use Approach 1 + 2 to generate `Pace Score` and `Rough Speed Bucket`. Show `Estimated Speed` only when calibration confidence is sufficient. Approach 3 is future work requiring custom ball detection model.

**User-facing honesty**:
```
"Speed estimates are approximate, derived from visual analysis of your
bowling action. For accurate measurements, use a speed gun. These
estimates help you understand relative effort levels across deliveries,
not absolute speed."
```

---

## 3. Cross-Cutting Techniques

### 3A. Multi-Delivery Batching (Long Clips)

For clips with multiple deliveries (e.g., 70s clip with 4 deliveries):

**Best approach**: XML tagging with forced enumeration (from Section 2A), combined with a two-pass architecture:

```
Pass 1 (Scout — Gemini Flash):
  Full video → count + timestamps of all deliveries

Pass 2 (Expert — Gemini Pro per delivery):
  Extract 5s clip per delivery → deep analysis each
```

**Existing architecture does this correctly.** Scout scans chunks, Expert analyzes per-delivery clips.

**Enhancement for >5 min sessions**: Add a Level 0 pre-scan:
```
Level 0: "How many minutes of active bowling vs idle time?"
→ Skip idle regions entirely
→ Send only active regions to Scout
```

### 3B. Temporal Anchoring

All analysis uses relative timing with Release = T=0:

```
MediaPipe provides: RELEASE_FRAME (highest wrist angular velocity)
Gemini receives: "Release is at {release_ts}s. Express all phases as offsets."

Output:
  BFC = T-0.3s
  FFC = T-0.12s
  Release = T=0
  Follow-through = T+0.4s
```

**Gemini does NOT determine timestamps.** MediaPipe does. Gemini provides semantic labels.

### 3C. Self-Correction / Validation

Prompt Gemini to check biomechanical impossibilities:

```
<validation>
After completing your analysis, verify:
1. Phases are in correct temporal order: Run-up < BFC < FFC < Release < Follow-through
2. No phase duration is impossibly short (<0.05s) or long (>3s for a single phase)
3. Front knee angle at release >= front knee angle at FFC (knee doesn't flex MORE under load)
4. Release happens AFTER front-foot contact (never before)

If any check fails, flag it:
{"validation_warning": "Release timestamp appears before FFC — re-check timestamps"}
</validation>
```

### 3D. Environment Robustness

```
<environment>
This is from an UNCONTROLLED environment. Expect:
- Fences, nets, bystanders, uneven surfaces, variable lighting
- Focus EXCLUSIVELY on the subject with the bowling action
- If multiple people are visible, the bowler is the one with
  the overarm rotating motion
- If landmark confidence < 0.6 for a phase-critical joint,
  report "LOW_CONFIDENCE" rather than guessing
</environment>
```

**Camera angle detection** (prompt the user or auto-detect):

| Angle | Detection Heuristic | Analysis Quality |
|-------|-------------------|-----------------|
| Side-on | Shoulders appear wide relative to frame | Best — gold standard |
| Front-on | Shoulders appear narrow, head centered | Limited — self-occlusion |
| Behind | Back visible, shoulders wide | Poor — depth compression |

### 3E. Expert Buddy Persona (Not Coach)

All prompts use this framing:

```
Frame every insight as: Observe → Compare → Hypothesize → Ask

Example output:
"Your front knee flexion at FFC is ~22°. Bowlers with stiffer
front legs (10-15°) tend to generate 4-8% more pace at the
cost of higher tibial load. Worth experimenting with in nets?"

NEVER: "Fix your front knee."
ALWAYS: "The data suggests... what happens if...?"
```

---

## 4. Reference Data

### Bowling Phase Durations (Fast Bowler Reference)

| Phase | Typical Duration | Notes |
|-------|-----------------|-------|
| Run-up | 2-5s | Varies by bowler |
| BFC to FFC | 0.1-0.2s | Very fast |
| FFC to Release | 0.08-0.15s | Fastest phase |
| Release to follow-through end | 0.3-0.8s | Deceleration |

### Joint Angle Reference Ranges (TRAINING-DATA, from Portus et al., Worthington et al.)

| Joint | Fast Bowler | Spin Bowler | Injury Threshold |
|-------|------------|-------------|------------------|
| Front knee at FFC | 160-180° | 140-165° | <140° or >175° (locked) |
| Front knee at release | 165-180° | 145-170° | Rapid extension >30° from FFC |
| Bowling arm elbow change | <15° (ICC) | <15° (ICC) | >15° = illegal |
| Hip-shoulder separation at BFC | 30-50° | 20-40° | <10° (front-on) or >50° (mixed) |
| Trunk lateral flexion | 25-40° | 15-30° | >45° (lumbar stress risk) |

### Pose Estimation Accuracy by Environment (TRAINING-DATA)

| Setting | MediaPipe Accuracy | Key Failure |
|---------|-------------------|-------------|
| Lab (motion capture) | 92-95% | Nearly none |
| Indoor gym | 85-90% | Cluttered background |
| Outdoor overcast | 78-85% | Background humans |
| Outdoor harsh sun | 68-78% | Specular highlights |
| Backyard with nets | 60-75% | Net mesh confusion |

---

## 5. Honest Limitations

| Claim | Reality |
|-------|---------|
| "Phase detection < 0.2s" | Achievable with MediaPipe timestamps, NOT with Gemini alone |
| "Elbow legality detection" | 2D video cannot reliably measure 15° — observation only, never conclusive |
| "Exact speed measurement" | Not a product claim; use Pace Score + Rough Speed Bucket, and show estimated km/h only with calibration confidence |
| "Works in any environment" | Accuracy degrades significantly in harsh sun, nets, or with multiple people |
| "Multi-delivery detection" | Good with forced enumeration, but phantom deliveries can still false-positive |

**Research gaps to fill** (needs web search when available):
- Gemini 3 Flash/Pro specific documentation (post May 2025)
- Latest Multimodal Live API capabilities
- Any new temporal grounding techniques published 2025-2026

---

*Last synced: 2026-02-24. Based on 5 parallel research agents + existing wellBowled codebase analysis.*
