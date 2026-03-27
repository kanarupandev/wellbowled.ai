# Optimized Pipeline — Event Order & Tool Roles

## Key Insight: Gemini is BOTH validator and generator

Gemini shouldn't just be called once. It should bookend each major step:
- **Before** a step: generate instructions/config for that step
- **After** a step: validate the output before proceeding

This creates a quality feedback loop at every stage.

## Optimized Pipeline (1 call = 1 Gemini interaction)

```
INPUT: Raw bowling clip (any source, any angle, any people)

═══════════════════════════════════════════════════════
CALL 1: GEMINI FLASH — SCOUT (contact sheet)
═══════════════════════════════════════════════════════
  Input:  6-frame contact sheet from the clip
  Generates:
    - bowler identity (name if famous, description if unknown)
    - bowling arm (left/right)
    - bowler bounding box per key frame
    - bowler center point for SAM 2 prompt
    - action timestamps: run-up start, BFC, FFC, release, follow-through
    - camera angle assessment: side-on / behind / front-on / mixed
    - clip quality assessment: resolution, lighting, usability (1-10)
    - recommended technique: which analysis works best from this angle
  Cost: ~$0.001

  GATE: If clip quality < 5, STOP. Tell user to find better footage.

═══════════════════════════════════════════════════════
STEP 1: SAM 2 LARGE — BOWLER ISOLATION (Mac)
═══════════════════════════════════════════════════════
  Input:  raw clip + bowler center point from Gemini
  Process: SAM 2 segments bowler through all frames
  Output: bowler_isolated.mp4 (bowler on black) + masks/

  SELF-CHECK: mask area should be consistent (no frame with 0 pixels).
  If any frame has <100px mask area → flag for review.

═══════════════════════════════════════════════════════
STEP 2: REAL-ESRGAN — UPSCALE (if needed)
═══════════════════════════════════════════════════════
  Input:  bowler_isolated.mp4
  Condition: ONLY if source resolution < 480p OR bowler < 150px tall
  Process: 2x upscale
  Output: bowler_upscaled.mp4

  Skip for HD source clips — no point upscaling 1080p.

═══════════════════════════════════════════════════════
STEP 3: RIFE — FRAME INTERPOLATION (if needed)
═══════════════════════════════════════════════════════
  Input:  bowler_isolated.mp4 (or upscaled)
  Condition: ONLY if source fps < 60 AND we want ultra-slo-mo
  Process: 4x or 8x interpolation
  Output: bowler_smooth.mp4 (120fps or 240fps)

  Skip for clips that will be shown at 0.25x (30fps source → 7.5fps display is fine).
  Use for 0.1x slo-mo where frame jumps are visible.

═══════════════════════════════════════════════════════
STEP 4: MEDIAPIPE — POSE EXTRACTION
═══════════════════════════════════════════════════════
  Input:  isolated (+ optionally upscaled/interpolated) clip
  Process: 33 landmarks per frame, single person (guaranteed by SAM 2)
  Output: poses.json (per-frame landmarks + visibility)

  SELF-CHECK:
  - Landmarks detected in >80% of frames (else clip is unusable)
  - No sudden jumps >20% of frame between consecutive frames (else tracking failed)

═══════════════════════════════════════════════════════
STEP 5: ANALYSIS — VELOCITY + ENERGY TRANSFER
═══════════════════════════════════════════════════════
  Input:  poses.json + bowler profile (height, known pace)
  Process:
    a. Per-joint velocity (normalized to torso length)
    b. Temporal smoothing (3-frame median)
    c. Peak velocity per segment
    d. Transfer ratios between consecutive segments
    e. Peak timing sequence (proximal-to-distal check)
    f. Comparison to elite baseline (from same-angle clips)
  Output: analysis.json

═══════════════════════════════════════════════════════
CALL 2: GEMINI PRO — VALIDATE + GENERATE INSIGHT (optional)
═══════════════════════════════════════════════════════
  Input:  peak frame image + analysis.json + bowler profile
  Validates:
    - "Does the peak separation angle look correct for this frame?"
    - "Is the bowler correctly identified?"
    - "Are the transfer ratios plausible for a bowler of this level?"
  Generates:
    - 3-line coaching insight (specific to THIS bowler's data)
    - Verdict text (actionable, not generic)
    - Caption for social media post
  Cost: ~$0.01

  This call is OPTIONAL. Skip during development. Use for final output.

═══════════════════════════════════════════════════════
STEP 6: RENDER — VISUALIZATION
═══════════════════════════════════════════════════════
  Input:  isolated clip frames + analysis.json + Gemini insight
  Process:
    - Title card (technique-specific)
    - Slo-mo with energy flow overlay (pauses at transitions)
    - Freeze at peak with label
    - Verdict card with transfer ratios + coaching insight
    - End card
  Output: rendered frames

═══════════════════════════════════════════════════════
STEP 7: FFMPEG — FINAL ENCODE
═══════════════════════════════════════════════════════
  Input:  rendered frames
  Process: H.264, CRF 17, yuv420p, 1080x1920, 30fps, silent AAC, faststart
  Output: upload_ready.mp4

  SELF-CHECK: ffprobe → verify resolution, codec, bitrate, duration.

═══════════════════════════════════════════════════════
OUTPUT
═══════════════════════════════════════════════════════
  - upload_ready.mp4 (the content)
  - analysis.json (the data)
  - masks/ (reusable for other techniques)
  - metadata.json (bowler, timestamps, quality scores)
```

## Gemini Usage Budget: 2 calls max per clip

| Call | Model | Purpose | When | Cost |
|------|-------|---------|------|------|
| 1 | Flash | Scout: bowler ID + timestamps + quality gate | Before processing | ~$0.001 |
| 2 | Pro (optional) | Validate analysis + generate insight text | After analysis | ~$0.01 |

## What gets REUSED across techniques

Once SAM 2 isolates the bowler and MediaPipe extracts poses, that data feeds ALL techniques:

```
bowler_isolated.mp4 + poses.json
    ├── X-Factor pipeline       (hip-shoulder angles from poses)
    ├── Speed Gradient pipeline  (velocities from poses)
    ├── Kinogram pipeline        (frame selection from poses)
    ├── Goniogram pipeline       (joint angles from poses)
    ├── Bowling Arm Arc pipeline (wrist trajectory from poses)
    └── Any future technique     (same foundation)
```

SAM 2 + MediaPipe = shared foundation. Run once, feed all 6+ techniques.

## Optimization: What to skip

| Condition | Skip |
|-----------|------|
| Source is HD (720p+) | Skip Real-ESRGAN |
| Slo-mo speed ≥ 0.25x | Skip RIFE interpolation |
| Development iteration | Skip Gemini Call 2 |
| Nets clip with single bowler | Skip SAM 2 (MediaPipe alone is fine) |
| Famous bowler (known profile) | Skip Gemini bowler identification |

## Error handling

| Error | Action |
|-------|--------|
| Gemini says clip quality < 5 | Stop. Tell user to find better clip. |
| SAM 2 mask area drops to 0 | Flag frame. Interpolate mask from neighbors. |
| MediaPipe detects 0 poses | Clip is unusable after isolation. Stop. |
| Transfer ratio > 5x | Likely measurement error. Cap at 3x and flag. |
| Peak wrist velocity = 0 | Bowler not in delivery stride. Check timestamps. |
