# Content Pipeline v1 — Overview (FINALIZED)

## Performance Target

**1 hour accepted latency for a 10-second clip.** Quality over speed.

## Pipeline Flow

```
STAGE 0: INPUT VALIDATION
  Raw MP4 → verify format, extract metadata, generate contact sheet
  Out: clip_metadata.json + contact_sheet.jpg

STAGE 1: SCENE UNDERSTANDING (Gemini 3 Preview Pro)
  Contact sheet → 1 Gemini call → bowler ID, timestamps, quality gate
  Out: scene_report.json → feeds ALL downstream stages
  GATE: clip_quality < 5 → STOP

STAGE 2: BOWLER ISOLATION (SAM 2 Large)
  Raw clip + bowler center point from Stage 1 → segment bowler
  Out: masks/ (per-frame binary PNGs) + isolation_report.json
  GATE: mask coverage < 90% → STOP
  Runs on: Mac (MPS) or Linux (CPU, slower but viable within 1hr for 10s clip)

STAGE 3: ENHANCEMENT (conditional)
  Masked frames → Real-ESRGAN upscale (if low-res) + RIFE interpolation (if ultra-slo-mo)
  Out: enhanced_metadata.json (or passthrough if skipped)
  NOTE: timestamps from Stage 1 are remapped if RIFE changes frame count

STAGE 4: POSE EXTRACTION (MediaPipe Heavy)
  Masked frames → 33 landmarks per frame, single person guaranteed
  Out: poses.json
  GATE: detection_rate < 80% → STOP
  GATE: two runs must produce IDENTICAL results

STAGE 5: ANALYSIS
  poses.json + scene_report.json → velocity, transfer ratios, peaks
  Out: analysis.json
  GATE: wrist must be fastest joint, all ratios 0.5-5.0

STAGE 6: INSIGHT + VALIDATION (Gemini 3 Preview Pro, optional)
  analysis.json + peak frame + isolated frame sample → validate + generate
  Out: insight.json
  Validates: "Is analysis plausible? Is bowler correctly isolated?"
  Generates: coaching text, social caption

STAGE 7: RENDER (technique-specific)
  masks/ + original frames + poses.json + analysis.json + insight.json
  → title card + slo-mo with overlay + pauses + verdict + end card
  Out: rendered_frames/
  Rendering applies masks to original video (chooses background per technique)
  GATE: visual spot check at 0%, 25%, 50%, 75%, 95%

STAGE 8: ENCODE (FFmpeg)
  rendered_frames/ → H.264, 1080x1920, 30fps, CRF 17
  Out: upload_ready.mp4
  GATE: ffprobe verification (codec, resolution, bitrate, duration)
```

## Technique Selection

User specifies technique at invocation:
```bash
python pipeline.py input.mp4 --technique speed_gradient
python pipeline.py input.mp4 --technique xfactor
python pipeline.py input.mp4 --technique all  # runs all applicable techniques
```

Stages 0-5 are SHARED (run once). Stage 7 branches per technique.
Gemini's `recommended_techniques` from Stage 1 suggests what works for this camera angle.

## Gemini Model Choice

**Model: gemini-3-pro-preview** for both calls.

Rationale: Stage 1 scene_report feeds every downstream stage. Wrong timestamps = wrong isolation = wrong pose = wrong analysis. Errors compound. The $0.01 cost is irrelevant. Get Stage 1 right.

## Data Flow: scene_report.json feeds forward

```
scene_report.json (from Stage 1)
│
├─→ Stage 2: bowler_center_points → SAM 2 initial prompt
├─→ Stage 3: resolution + camera_angle → upscale/interpolation decision
│             original_fps → RIFE frame count calculation
├─→ Stage 4: timestamps → window pose extraction to delivery stride
│             (remapped if RIFE changed frame count in Stage 3)
├─→ Stage 5: bowling_arm → which arm's joints to track
│             timestamps → window velocity computation
│             bowler_id → height/pace lookup for calibration
├─→ Stage 6: bowler_id + camera_angle → contextualize validation
├─→ Stage 7: bowler_id → name on title card
│             camera_angle → overlay positioning
│             recommended_techniques → visualization style
└─→ All stages: clip_quality score for logging/debugging
```

## Mac ↔ Linux Handoff

Stage 2 (SAM 2) runs on Mac. All other stages run on Linux.

Transfer method: shared directory (rsync, NFS, or manual copy).

```
Mac produces:  /shared/project_name/masks/*.png
               /shared/project_name/isolation_report.json
Linux reads:   /shared/project_name/masks/*.png
               + original clip (already on Linux)
```

Alternative: run SAM 2 on Linux CPU. For a 10-second clip (300 frames):
~15 sec/frame × 300 = ~75 min. Within the 1-hour budget (tight but viable).
SAM 2 tiny on Linux CPU: ~5 sec/frame × 300 = ~25 min. Comfortable.

## Key Principles

1. **Validated gates** — each stage validates output before next proceeds
2. **Independently optimizable** — swap any tool, same input/output contract
3. **Cacheable** — masks/ and poses.json reused across ALL techniques
4. **Gemini 3 Preview Pro** — best model, cost negligible at our volume
5. **2 calls max** — Stage 1 (scout) + Stage 6 (validate + insight)
6. **Masks only from Stage 2** — rendering stage decides background
7. **Technique branches at Stage 7** — shared foundation, specific rendering
8. **RIFE timestamp remapping** — if interpolation changes frame count, all downstream timestamps are remapped

## Cost Per Clip

| Item | Cost |
|------|------|
| Gemini 3 Pro (Stage 1) | ~$0.01 |
| Gemini 3 Pro (Stage 6, optional) | ~$0.01 |
| SAM 2, MediaPipe, ESRGAN, RIFE, FFmpeg | Free |
| **Total** | **~$0.02** |

## Processing Time (10-second clip, 300 frames)

| Stage | Where | Time |
|-------|-------|------|
| 0: Input validation | Linux | <1 sec |
| 1: Gemini Pro | API | ~30 sec |
| 2: SAM 2 Large | Mac MPS | ~5 min |
| 2: SAM 2 Tiny (alt) | Linux CPU | ~25 min |
| 3: Enhancement | Linux | ~2 min (if needed) |
| 4: Pose extraction | Linux | ~1 min |
| 5: Analysis | Linux | <1 sec |
| 6: Insight | API | ~10 sec |
| 7: Render | Linux | ~3 min |
| 8: Encode | Linux | ~15 sec |
| **Total (Mac MPS)** | | **~12 min** |
| **Total (Linux CPU)** | | **~32 min** |
| **Budget** | | **60 min** |
