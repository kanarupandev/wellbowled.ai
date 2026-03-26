# X-Factor Production Plan

> Input: 3-10 second clip of a bowling action
> Output: 20-60 second Instagram Reel showing hip-shoulder separation
> Budget: Max 2 Gemini calls (1 Flash, 1 Pro Preview)

---

## What We're Making

A video that shows **two colored lines** — one through the hips, one through the shoulders — rotating through a bowling delivery. The moment they diverge IS the X-factor. The moment they snap together IS the release. The viewer sees where pace comes from in 2 seconds.

Final output:
- 9:16 MP4, 20-60s
- Full speed → 0.25x slow-mo with overlays → freeze at peak separation → verdict
- Hip line (pink/magenta), shoulder line (cyan)
- Separation angle number on screen ("47°")
- Phase labels + grade

---

## Pipeline Overview

```
INPUT                          LOCAL PROCESSING                    GEMINI                         OUTPUT
─────                          ────────────────                    ──────                         ──────

[Raw Clip]
    │
    ├─► [1. Extract Contact Sheet]  ──────────────►  [2. Gemini Flash]
    │   (FFmpeg: 5-8 key frames)                     (phase timing +
    │                                                 bowler ROI +
    │                                                 insight seed)
    │                                                     │
    │                                                     ▼
    ├─► [3. MediaPipe Pose]  ◄─── uses ROI hint ─── [Flash JSON]
    │   (33 landmarks per frame)
    │        │
    │        ▼
    ├─► [4. Compute X-Factor]
    │   (hip midpoint, shoulder midpoint,
    │    hip-line angle, shoulder-line angle,
    │    separation = |hip_angle - shoulder_angle|)
    │        │
    │        ▼
    ├─► [5. Render Overlays]
    │   (OpenCV: hip line, shoulder line,
    │    separation arc, angle number,
    │    phase label, skeleton)
    │        │
    │        ▼
    ├─► [6. Compose Video]
    │   (FFmpeg: intro → slo-mo → freeze → verdict)
    │        │
    │        ├──────────────────────────────────────►  [7. Gemini Pro Preview]
    │        │                                         (coaching insight text
    │        │                                          from peak separation
    │        │                                          frame + angle data)
    │        │                                              │
    │        ◄──────────────────────────────────────────────┘
    │
    └─► [8. Final Assembly]  ──────────────────────────────────────►  [9:16 MP4]
        (burn in text overlays,
         captions, watermark,
         export)
```

---

## Stage-by-Stage Detail

### Stage 1: Extract Contact Sheet
**Tool:** FFmpeg
**Input:** Raw clip (3-10s, any resolution)
**Output:** 5-8 JPEG frames at uniform intervals + 1 composite contact sheet image

```bash
# Extract frames at ~3fps
ffmpeg -i input.mp4 -vf "fps=3" -q:v 2 frame_%03d.jpg

# Composite into contact sheet (2x4 grid)
ffmpeg -i input.mp4 -vf "fps=3,tile=2x4" -frames:v 1 contact_sheet.jpg
```

**Why:** Gemini Flash works on images. A contact sheet gives it the full action in one image. Cheaper than sending video.

---

### Stage 2: Gemini Flash Call (Call 1 of 2)
**Model:** gemini-3-flash-preview
**Input:** Contact sheet image + prompt
**Output:** JSON with phase timing, bowler ROI, annotation hints

**Prompt:**
```
You are a cricket bowling biomechanics analyst.

This contact sheet shows frames from a bowling delivery clip.
Frames are left-to-right, top-to-bottom, at ~3fps intervals.

Return JSON only:
{
  "bowler_roi": {"x1": 0.0, "y1": 0.0, "x2": 1.0, "y2": 1.0},
  "phases": {
    "back_foot_contact": <seconds>,
    "front_foot_contact": <seconds>,
    "release": <seconds>,
    "follow_through": <seconds>
  },
  "action_type": "side-on" | "front-on" | "semi-open" | "mixed",
  "insight_seed": "<one sentence about what's notable in this action>"
}
```

**Cost:** ~0.002 USD (single image, short response)
**Latency:** ~1-2s

---

### Stage 3: MediaPipe Pose Extraction
**Tool:** MediaPipe Pose Landmarker (Python)
**Input:** Every frame of clip (cropped to bowler ROI from Flash)
**Output:** 33 landmarks per frame with (x, y, z, visibility)

```python
import mediapipe as mp

landmarker = mp.tasks.vision.PoseLandmarker.create_from_options(options)
# For each frame:
result = landmarker.detect(mp_image)
landmarks = result.pose_landmarks[0]  # 33 points
```

**Key landmarks for X-Factor:**
- Left hip (23), Right hip (24) → hip line
- Left shoulder (11), Right shoulder (12) → shoulder line

**Why local:** Deterministic. No API cost. ~30fps on M-series Mac.

---

### Stage 4: Compute X-Factor
**Tool:** NumPy
**Input:** Per-frame hip and shoulder landmarks
**Output:** Per-frame separation angle + peak separation timestamp

```python
import numpy as np

def compute_xfactor(landmarks):
    # Hip line angle (from horizontal)
    lh, rh = landmarks[23], landmarks[24]
    hip_angle = np.degrees(np.arctan2(rh.y - lh.y, rh.x - lh.x))

    # Shoulder line angle (from horizontal)
    ls, rs = landmarks[11], landmarks[12]
    shoulder_angle = np.degrees(np.arctan2(rs.y - ls.y, rs.x - ls.x))

    # Separation = absolute difference
    separation = abs(hip_angle - shoulder_angle)
    return hip_angle, shoulder_angle, separation
```

**Data produced per frame:**
- `hip_angle` (degrees)
- `shoulder_angle` (degrees)
- `separation` (degrees) — THIS is the X-factor
- `peak_separation_frame` — frame index where separation is maximum
- `peak_separation_angle` — the peak number (e.g., "47°")

---

### Stage 5: Render Overlays
**Tool:** OpenCV + NumPy
**Input:** Original frames + landmarks + X-factor data
**Output:** Annotated frames with overlays

**What gets drawn per frame:**

1. **Skeleton** (optional, faded — not the star here)
   - SkeletonRenderer connections, white, 50% opacity

2. **Hip line** (THE star, left)
   - Line through left hip → right hip, extended 30% beyond joints
   - Color: `#FF69B4` (hot pink), 4px width
   - Small dot at each hip joint

3. **Shoulder line** (THE star, right)
   - Line through left shoulder → right shoulder, extended 30%
   - Color: `#00CED1` (dark turquoise/cyan), 4px width
   - Small dot at each shoulder joint

4. **Separation arc**
   - Arc between the two lines at the spine midpoint
   - Color: white when small, transitions to green/yellow/red as separation increases
   - Angle number inside the arc: "47°"

5. **Phase label pill**
   - Current phase from Flash timing: "BACK FOOT CONTACT" → "FRONT FOOT CONTACT" → "RELEASE"
   - Top-center, black pill with white text

6. **Peak marker**
   - At peak separation frame: flash/pulse effect + "PEAK X-FACTOR" badge

```python
def draw_xfactor_overlay(frame, landmarks, hip_angle, shoulder_angle, separation, phase_label):
    h, w = frame.shape[:2]

    # Hip line (pink)
    lh = (int(landmarks[23].x * w), int(landmarks[23].y * h))
    rh = (int(landmarks[24].x * w), int(landmarks[24].y * h))
    cv2.line(frame, extend_line(lh, rh, 0.3), extend_line(rh, lh, 0.3), (180, 105, 255), 4)

    # Shoulder line (cyan)
    ls = (int(landmarks[11].x * w), int(landmarks[11].y * h))
    rs = (int(landmarks[12].x * w), int(landmarks[12].y * h))
    cv2.line(frame, extend_line(ls, rs, 0.3), extend_line(rs, ls, 0.3), (209, 206, 0), 4)

    # Separation angle text
    midpoint = ((lh[0]+rh[0]+ls[0]+rs[0])//4, (lh[1]+rh[1]+ls[1]+rs[1])//4)
    cv2.putText(frame, f"{separation:.0f}°", midpoint, cv2.FONT_HERSHEY_SIMPLEX, 1.2, (255,255,255), 3)

    # Phase label
    draw_pill(frame, phase_label, (w//2, 50))
```

---

### Stage 6: Compose Video Structure
**Tool:** FFmpeg
**Input:** Annotated frames from Stage 5
**Output:** Structured video with tempo changes

**Video structure:**

| Segment | Duration | Speed | What's Shown |
|---------|----------|-------|-------------|
| Cold open | 1-2s | 1x | Raw delivery, no overlay. "Watch this." |
| Replay with overlay | 3-6s | 0.25x | Full skeleton + hip/shoulder lines + separation angle building |
| Freeze at peak | 2-3s | 0x (still) | Peak separation frame. "PEAK X-FACTOR: 47°" badge. Lines maximally diverged. |
| Resume to release | 2-3s | 0.25x | Lines snap together as shoulders catch up to hips. Release moment. |
| Verdict card | 2-3s | static | Phase grades + insight text from Gemini Pro |
| End card | 1-2s | static | wellBowled.ai watermark + QR code |

```bash
# Build slo-mo section (0.25x = duplicate each frame 4x)
ffmpeg -i overlay_frames/%04d.jpg -vf "setpts=4*PTS" -r 30 slomo.mp4

# Concatenate segments
ffmpeg -f concat -i segments.txt -c:v libx264 -preset fast final.mp4
```

---

### Stage 7: Gemini Pro Preview Call (Call 2 of 2)
**Model:** gemini-3-pro-preview
**Input:** Peak separation frame image + computed angles + action type from Flash
**Output:** Coaching insight text (3-4 sentences)

**Prompt:**
```
You are a cricket fast bowling biomechanics coach.

This frame shows a bowler at peak hip-shoulder separation.
- Action type: {action_type}
- Hip-shoulder separation angle: {peak_separation}°
- Phase: {phase_at_peak}

Write exactly 3 lines for a video overlay:
1. One-line hook (what the viewer should notice)
2. One-line explanation (why this matters for pace)
3. One-line verdict (good/needs work + one actionable cue)

Keep it punchy. No jargon. A 16-year-old fast bowler should understand it.
```

**Cost:** ~0.01 USD (single image + short text)
**Latency:** ~2-3s

---

### Stage 8: Final Assembly
**Tool:** FFmpeg + Pillow (for text burns)
**Input:** Composed video + Gemini Pro text + branding assets
**Output:** Final 9:16 MP4

**Burns in:**
- Gemini Pro insight text (during verdict card segment)
- Bilingual caption line (English + Tamil/Hindi)
- wellBowled.ai watermark (bottom-right, semi-transparent)
- Color legend bar (bottom: pink=hips, cyan=shoulders)

---

## Tech Stack Summary

| Stage | Tool | Cost | Time |
|-------|------|------|------|
| 1. Frame extraction | FFmpeg | Free | <1s |
| 2. Phase detection | Gemini Flash | ~$0.002 | ~2s |
| 3. Pose estimation | MediaPipe (Python) | Free | ~2s |
| 4. X-Factor compute | NumPy | Free | <0.1s |
| 5. Overlay rendering | OpenCV | Free | ~3s |
| 6. Video composition | FFmpeg | Free | ~2s |
| 7. Coaching insight | Gemini Pro Preview | ~$0.01 | ~3s |
| 8. Final assembly | FFmpeg + Pillow | Free | ~2s |
| **Total** | | **~$0.012** | **~15s compute** |

**Human time:** Review output, adjust if needed. Target: <5 min.

---

## File Structure

```
content/xfactor_pipeline/
├── run.py                  # Main orchestrator
├── extract_frames.py       # Stage 1: FFmpeg frame extraction
├── flash_planner.py        # Stage 2: Gemini Flash call
├── pose_extractor.py       # Stage 3: MediaPipe pose
├── xfactor_compute.py      # Stage 4: Angle computation
├── overlay_renderer.py     # Stage 5: OpenCV drawing
├── video_composer.py        # Stage 6+8: FFmpeg composition
├── pro_insight.py          # Stage 7: Gemini Pro call
├── config/
│   └── default.json        # Colors, line widths, font sizes
└── output/
    ├── frames/             # Extracted frames
    ├── annotated/          # Frames with overlays
    └── final.mp4           # Export
```

---

## Dependencies

```bash
pip install mediapipe opencv-python numpy Pillow google-generativeai
# FFmpeg must be installed: brew install ffmpeg
```

---

## What Already Exists (Reuse from Codex Lab)

| Component | File | Reuse? |
|-----------|------|--------|
| MediaPipe pose extraction | `codex_lab/.../tool/render_bowling_analysis.py` | Yes — pose extraction + ROI crop logic |
| Gemini Flash planning | `codex_lab/.../tool/plan_with_flash.py` | Yes — contact sheet + Flash JSON call |
| Story config format | `codex_lab/.../tool/story_nets_release.json` | Yes — phase timing JSON structure |
| Frame extraction | `codex_lab/.../tool/render_bowling_analysis.py` | Yes — FFmpeg frame extraction |

**New code needed:** X-factor angle computation (Stage 4), hip/shoulder line rendering (Stage 5), video structure composition (Stage 6).

---

## Success Criteria

1. Given a 3-10s bowling clip, pipeline produces a final MP4 in <60s total
2. Hip and shoulder lines are visually distinct and track the bowler correctly
3. Peak separation angle matches visual inspection (±5°)
4. Gemini calls total ≤ 2
5. Output plays correctly on Instagram (9:16, H.264, ≤60s)
6. A non-cricketer can understand "the gap between these lines = pace" from watching once
