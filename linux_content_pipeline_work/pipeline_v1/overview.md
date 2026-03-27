# Content Pipeline v1 — Overview

## Pipeline Flow

```
STAGE 0: INPUT VALIDATION
  Raw MP4 → verify, extract metadata
  Out: clip_metadata.json

STAGE 1: SCENE UNDERSTANDING (Gemini 3 Preview Pro)
  Contact sheet → 1 Gemini call
  Out: scene_report.json → feeds ALL downstream stages

STAGE 2: BOWLER ISOLATION (SAM 2 Large, Mac MPS)
  Raw clip + bowler points from Stage 1 → segment bowler
  Out: masks/ (per-frame binary PNGs)

STAGE 3: ENHANCEMENT (conditional)
  Isolated frames → Real-ESRGAN + RIFE
  Out: enhanced frames (skip if not needed)

STAGE 4: POSE EXTRACTION (MediaPipe Heavy)
  Isolated frames → 33 landmarks per frame
  Out: poses.json

STAGE 5: ANALYSIS
  Poses + scene_report → velocity, transfer ratios, peaks
  Out: analysis.json

STAGE 6: INSIGHT GENERATION (Gemini 3 Preview Pro, optional)
  Analysis + peak frame → validate + coaching text
  Out: insight.json

STAGE 7: RENDER
  All inputs → technique-specific visualization
  Out: rendered_frames/

STAGE 8: ENCODE (FFmpeg)
  Rendered frames → H.264 MP4
  Out: upload_ready.mp4
```

## Gemini Model Choice

**Model: gemini-3-pro-preview** for both calls.

Rationale: Stage 1 scene_report feeds every downstream stage. Wrong timestamps = wrong isolation window = wrong pose extraction = wrong analysis. The $0.01 cost difference vs Flash is irrelevant. Accuracy at Stage 1 is worth 100x the cost because errors compound through every stage.

## Data Flow: scene_report.json feeds forward

```
scene_report.json (from Stage 1)
│
├─→ Stage 2: bowler_center_points → SAM 2 initial prompt
├─→ Stage 3: resolution + camera_angle → upscale/interpolation decision
├─→ Stage 4: timestamps → window pose extraction to delivery stride
├─→ Stage 5: bowling_arm → which joints to track
│             timestamps → window velocity computation
│             bowler_id → height/pace calibration lookup
├─→ Stage 7: bowler_id → name on title card
│             camera_angle → overlay positioning
│             recommended_techniques → visualization style
└─→ Stage 6: bowler_id + camera_angle → contextualize insight
```

## Key Principles

1. **Validated gates** — each stage validates output before next proceeds
2. **Independently optimizable** — swap any tool without affecting others
3. **Cacheable** — masks/ and poses.json reused across all techniques
4. **Gemini 3 Preview Pro** — best model for accuracy, cost negligible
5. **2 calls max** — Stage 1 (scout) + Stage 6 (insight, optional)
6. **Mac + Linux split** — SAM 2 on Mac (MPS), everything else on Linux
7. **Masks only** — Stage 2 outputs binary masks, Stage 7 decides background

## Cost Per Clip

| Item | Cost |
|------|------|
| Gemini 3 Pro (Stage 1) | ~$0.01 |
| Gemini 3 Pro (Stage 6, optional) | ~$0.01 |
| SAM 2, MediaPipe, ESRGAN, RIFE, FFmpeg | Free |
| **Total** | **~$0.02** |

## Processing Time Per 1-Min Clip

| Stage | Where | Time |
|-------|-------|------|
| 0: Input validation | Linux | <1 sec |
| 1: Gemini | API | ~30 sec |
| 2: SAM 2 Large | Mac (MPS) | ~15-30 min |
| 3: Enhancement | Linux | ~5 min (if needed) |
| 4: Pose extraction | Linux | ~2 min |
| 5: Analysis | Linux | <1 sec |
| 6: Insight | API | ~10 sec |
| 7: Render | Linux | ~5 min |
| 8: Encode | Linux | ~30 sec |
| **Total** | | **~25-45 min** |
