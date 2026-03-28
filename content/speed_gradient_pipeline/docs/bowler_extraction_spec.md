# Bowler Extraction — Optimization Problem

## Objective

Given a broadcast cricket bowling clip, extract ONLY the bowler across ALL frames. Everything else — pitch, crowd, umpire, batsman, fielders, graphics — blacked out.

## Input → Output

| | Spec |
|---|------|
| **Input** | Broadcast MP4, 640×360 to 1920×1080, 30fps, 0.5-5s. May contain camera cuts (close-up run-up → wide delivery shot). Multiple people visible. |
| **Output** | Same resolution MP4, same fps, same frame count. Only bowler pixels visible. All other pixels = black (0,0,0). Smooth mask edges (soft alpha, not jagged binary). |

## The Core Challenge

Broadcast clips have **camera cuts**. The run-up is often a close-up (bowler fills frame → easy). The delivery is a wide shot (bowler is 50-100px tall, 6+ people visible → hard).

MediaPipe segmentation works perfectly on close-ups. Fails on wide shots because the bowler is too small.

## Tech Stack (Optimal Arrangement)

```
┌──────────────────────────────────────────────────┐
│  GEMINI PRO 3 (1 call)                           │
│  Input: contact sheet (8 frames spanning clip)   │
│  Output: JSON with everything we need            │
│                                                  │
│  ┌─────────────────────────────────────────────┐ │
│  │ {                                           │ │
│  │   "camera_cuts": [                          │ │
│  │     {"frame": 25, "from": "closeup",        │ │
│  │      "to": "wide"}                          │ │
│  │   ],                                        │ │
│  │   "bowler_roi_per_angle": {                  │ │
│  │     "closeup": {"x":.3,"y":.1,"w":.4,"h":.8}│ │
│  │     "wide":    {"x":.1,"y":.2,"w":.15,"h":.5│ │
│  │   },                                        │ │
│  │   "phases": {                               │ │
│  │     "runup_start": 0.0,                     │ │
│  │     "back_foot_contact": 2.1,               │ │
│  │     "front_foot_contact": 2.4,              │ │
│  │     "release": 2.6,                         │ │
│  │     "follow_through": 3.0                   │ │
│  │   },                                        │ │
│  │   "bowling_arm": "right",                   │ │
│  │   "bowler_description": "..."               │ │
│  │ }                                           │ │
│  └─────────────────────────────────────────────┘ │
└──────────────────────┬───────────────────────────┘
                       │
                       ▼
┌──────────────────────────────────────────────────┐
│  PER-FRAME PROCESSING                            │
│                                                  │
│  For each frame:                                 │
│    1. Determine camera angle (from cut list)     │
│    2. Crop to bowler ROI for that angle           │
│    3. Upscale crop to ≥400px tall (bicubic)      │
│    4. MediaPipe PoseLandmarker                   │
│       + output_segmentation_masks=True           │
│       + IoU bowler tracking (pick right person)  │
│    5. Map mask back to full-frame coordinates    │
│    6. Apply soft mask → bowler only              │
│                                                  │
│  Fallback chain (if MediaPipe fails):            │
│    A. Use previous frame's mask (shifted by ROI) │
│    B. Use GrabCut with ROI as foreground seed    │
│    C. Hard crop to ROI (last resort)             │
└──────────────────────┬───────────────────────────┘
                       │
                       ▼
┌──────────────────────────────────────────────────┐
│  FFMPEG ENCODE                                   │
│  H.264, CRF 18, same fps, same resolution       │
└──────────────────────────────────────────────────┘
```

## Why This Arrangement Is Optimal

| Decision | Rationale |
|----------|-----------|
| Gemini Pro 3, not Flash | Higher accuracy for ROI on small bowlers in wide shots. 1 call = ~$0.02. |
| 1 call, not 2+ | Contact sheet with 8 frames covers all camera angles. One JSON response has everything. |
| MediaPipe segmentation, not SAM 2 | Already installed. No PyTorch GPU needed. Quality is excellent when bowler is ≥150px tall. |
| Crop before MediaPipe | Transforms the "bowler too small" problem into "bowler fills frame" — the scenario where MediaPipe already works. |
| Upscale to 400px | Below 150px, MediaPipe fails. At 400px, reliable detection + clean mask edges. Bicubic is sufficient (no AI upscaler needed). |
| Soft mask (float 0-1) | Smooth edges, no jagged binary cutouts. Looks professional. |
| Fallback chain | Never output a black frame. Always have something — previous mask, GrabCut, or hard crop. |

## Gemini Call Budget

| Call | Purpose | Model | Cost |
|------|---------|-------|------|
| 1 | Scene analysis: cuts, ROI per angle, phases, arm | gemini-2.5-pro | ~$0.02 |
| Total | | | ~$0.02 per clip |

---

## Quality Gate (40 Checks)

### A. Bowler Isolation (10)

- [ ] A1. Bowler visible in EVERY frame (no black frames)
- [ ] A2. No other person's pixels visible in any frame
- [ ] A3. No umpire visible
- [ ] A4. No batsman visible
- [ ] A5. No fielder visible
- [ ] A6. No crowd/spectator pixels
- [ ] A7. No pitch/ground visible outside bowler's feet contact area
- [ ] A8. No broadcast graphics/watermarks visible
- [ ] A9. No stumps/equipment visible (unless bowler is touching them)
- [ ] A10. Bowler is the CORRECT person (not a random fielder)

### B. Mask Quality (8)

- [ ] B1. Smooth mask edges (no jagged pixelation)
- [ ] B2. Soft alpha blending at edges (not hard binary cutoff)
- [ ] B3. Full body captured — head to feet, no limb cutoffs
- [ ] B4. Bowling arm fully captured during delivery (not clipped)
- [ ] B5. Fingers/hand visible during release (not lost to motion blur masking)
- [ ] B6. No halo artifacts around bowler edges
- [ ] B7. No mask flicker between frames (temporal consistency)
- [ ] B8. Mask tracks correctly across camera cuts

### C. Temporal Continuity (6)

- [ ] C1. No black frames in the middle of the clip
- [ ] C2. Bowler doesn't teleport between frames
- [ ] C3. Smooth mask transition at camera cut boundaries
- [ ] C4. Mask size changes smoothly (no sudden jumps)
- [ ] C5. Run-up → delivery → follow-through all captured
- [ ] C6. Frame count identical to input (no dropped frames)

### D. Camera Cut Handling (4)

- [ ] D1. Camera cuts correctly detected
- [ ] D2. Correct ROI used for each camera angle
- [ ] D3. Bowler re-acquired after cut (not lost)
- [ ] D4. No cross-fade artifacts at cut points

### E. Video Technical (6)

- [ ] E1. Output resolution matches input
- [ ] E2. Output fps matches input
- [ ] E3. Output frame count matches input
- [ ] E4. H.264 codec, MP4 container
- [ ] E5. Plays in QuickTime, VLC, browser
- [ ] E6. Background is pure black (0,0,0), not dark grey

### F. Edge Cases (6)

- [ ] F1. Works when bowler is partially off-screen
- [ ] F2. Works when bowler overlaps with umpire at crease
- [ ] F3. Works on both close-up and wide-angle shots
- [ ] F4. Works when bowler is < 100px tall (wide shot)
- [ ] F5. Graceful fallback when MediaPipe fails (not black frame)
- [ ] F6. Works on clips without camera cuts (single angle)

---

## Scoring

| Score | Meaning |
|-------|---------|
| 40/40 | Production ready |
| 35-39 | Minor issues, usable |
| 25-34 | Visible artifacts, needs work |
| < 25 | Not usable |

**Target: 35+/40 before integrating into speed gradient pipeline.**
