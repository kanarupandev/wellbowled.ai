# Speed Gradient v1.0.0 — Production Plan

## Two-Part Architecture

### Part 1: Preprocessing (Get a Usable Clip)

Raw broadcast footage → clean, cropped, high-res bowler-only clip.

| Step | Tool | What |
|------|------|------|
| 1a | FFmpeg | Extract frames at native fps (30fps) |
| 1b | Gemini Pro 3 (call 1) | Identify bowler ROI bounding box, BFC frame, FFC frame, release frame |
| 1c | FFmpeg + OpenCV | Crop to bowler ROI, discard everything else |
| 1d | Super-resolution | Pixel upscale the cropped ROI (bicubic or Real-ESRGAN) — bigger bowler = cleaner landmarks |
| 1e | Gemini Pro 3 (call 2, optional) | Validate/refine BFC/FFC/release if first pass was uncertain |

**Output:** High-res bowler-only frames + metadata (BFC, FFC, release frame indices)

**No frame interpolation.** Only pixel-level resolution upscaling. Frame count stays the same. We work with the 10-17 real frames we have.

### Part 2: Analysis & Visualization

Clean clip → energy flow video that viewers feel in their nerves.

---

## Video Phases (What The Viewer Sees)

### Phase 1: Load (Run-Up)
- 1x speed, raw footage
- Skeleton overlay: uniform color warming blue → cyan → green
- No per-joint differentiation — whole body heats as one unit
- No text, no numbers, no badges
- Duration: 1-2s (last few strides only)

### Phase 2: Plant (BFC)
- Snap to super slo-mo
- Uniform color **fragments** — back leg goes hot, upper body still cool
- Transfer 1: BFC → FFC — stride momentum
- Leak indicator between back foot and front foot

### Phase 3: Brace (FFC)
- Still super slo-mo
- Front foot plants — the block
- Front leg goes bright, energy drives upward
- Transfer 2: FFC → Hips — ground force into pelvis
- Leak indicator between foot and hips

### Phase 4: Unwind (Hips → Trunk)
- Hips peak and cool, trunk fires hot
- Hip-shoulder separation visible as color differential
- Transfer 3: Hips → Trunk — rotation transfer
- Leak indicator between hips and shoulders

### Phase 5: Whip (Trunk → Arm)
- Trunk peaks, arm cascades shoulder → elbow → wrist
- Wrist goes maximum red at release
- Transfer 4: Trunk → Arm — the whip
- Leak indicator between shoulder and bowling hand

### Phase 6: Verdict
- Freeze at release frame
- 4 transfer points with leak levels (visual only — link thickness/brightness)
- Overall chain quality
- Duration: 2-2.5s

### Phase 7: End Card
- wellBowled.ai branding
- Duration: 1-1.5s

---

## Four Transfer Points × Three Leak Levels

| # | Transfer | Measured By |
|---|----------|------------|
| 1 | BFC → FFC | Frame gap: back foot peak → front foot contact |
| 2 | FFC → Hips | Frame gap: front foot brace → hip acceleration onset |
| 3 | Hips → Trunk | Frame gap: hip peak → trunk acceleration onset |
| 4 | Trunk → Arm | Frame gap: trunk peak → arm acceleration onset |

| Leak Level | Frame Gap | Visual |
|------------|-----------|--------|
| Minimal | 0-1 frames | Fat bright link |
| Moderate | 2-3 frames | Medium link |
| Major | 4+ frames | Thin dim link |

---

## Implementation Stages

### Stage 1: Input & ROI Extraction
- Accept broadcast MP4 (0.5-3s)
- FFmpeg extract at native 30fps
- Gemini Pro 3: bowler bounding box + BFC/FFC/release frame indices
- Crop to bowler ROI across all frames
- Super-resolution upscale (pixel interpolation only, no frame generation)
- Output: high-res bowler-only frames + delivery metadata

### Stage 2: Pose Extraction
- MediaPipe heavy model on upscaled frames
- Confidence gating: visibility > 0.3
- Output: per-frame landmark positions + confidence

### Stage 3: Velocity Computation
- Central difference per joint per frame
- Savitzky-Golay smooth (window=5, polyorder=2)
- Normalize to max wrist velocity
- Output: per-joint velocity array

### Stage 4: Transfer Point Detection
- Use Gemini Pro 3 BFC/FFC frames as primary
- Validate with velocity drop detection (ankle velocity → near zero)
- Output: BFC, FFC, hip_peak, trunk_peak, release frame indices

### Stage 5: Leak Computation
- For each of 4 transfers: measure frame gap between source peak and target onset
- Classify into 3 leak levels
- Output: 4 leak levels + frame gap values

### Stage 6: Render Frames
- Run-up: uniform skeleton color (total body velocity)
- Delivery: per-joint color (individual velocity)
- Transfer links: thickness/brightness encodes leak level
- All text via Pillow
- Output: annotated frame PNGs

### Stage 7: Compose Video
- Phase 1 (Load): 1x, last 1-2s of run-up
- Phase 2-5 (Delivery): super slo-mo, each frame held long enough to absorb
- Phase 6 (Verdict): freeze + leak summary
- Phase 7 (End card): brand
- FFmpeg: H.264, CRF 18, 1080x1920, 30fps
- Output: speed_gradient.mp4

### Stage 8: Review
- Extract frames at 0%, 15%, 30%, 50%, 70%, 85%, 95%
- Verify: bowler only, color changes across delivery, leak indicators visible, verdict plausible

---

## Dependencies

- Gemini Pro 3 (`gemini-3-pro-preview`) — ROI + delivery phase detection (1-2 calls per clip)
- MediaPipe pose_landmarker_heavy.task
- Shared venv (mediapipe, opencv, pillow, scipy)
- FFmpeg (system)
- Optional: Real-ESRGAN or similar for super-resolution (fallback: bicubic upscale)
