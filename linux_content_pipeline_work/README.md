# X-Factor Content Pipeline v0.0.1

Self-contained pipeline that takes a raw bowling clip and produces a YouTube-upload-ready annotated analysis video showing hip-shoulder separation (the X-Factor).

## What it does

Input: 3-10s bowling clip (any camera angle, any number of people)
Output: 9:16 YouTube/Instagram-ready MP4 (20-30s, H.264 + AAC)

### Video structure
1. **Cold open** — raw footage at 1x speed
2. **Slow-mo replay** (0.25x) — hip line (pink) + shoulder line (cyan) + separation angle
3. **Freeze frame** — peak X-Factor angle with dramatic card
4. **Verdict card** — rating + comparison bar (You vs Steyn vs Lee) + coaching insight

### Key design decisions
- Overlays ONLY appear during the delivery window (back_foot_contact → follow_through)
- Before/after delivery = raw footage, zero annotations
- This prevents annotating background people — general solution, not overfitted
- Gemini Flash (1 call) identifies the bowler ROI + phases; falls back to heuristics if unavailable
- MediaPipe runs only within the bowler ROI crop

## Usage

```bash
cd linux_content_pipeline_work
./venv/bin/python run.py <input_clip.mp4>
./venv/bin/python run.py <input_clip.mp4> --skip-gemini  # no API calls
./venv/bin/python run.py <input_clip.mp4> --output-dir ./output/custom_name
```

## Dependencies

Python 3.12 venv with: mediapipe, opencv-python-headless, numpy, Pillow
System: ffmpeg
Model: `resources/pose_landmarker_heavy.task` (MediaPipe)

## Setup

```bash
python3.12 -m venv venv
./venv/bin/pip install mediapipe opencv-python-headless numpy Pillow
```

## Gemini API

- Store key in `.env`: `GEMINI_API_KEY=your_key`
- Model: gemini-2.5-flash (cheapest, ~$0.001/call)
- Budget: max 1 Flash call per video (bowler identification)
- Call 2 (Pro insight for verdict card text) reserved for future

## File structure

```
linux_content_pipeline_work/
├── run.py                   # Main orchestrator
├── src/
│   ├── flash_planner.py     # Gemini Flash: bowler ROI + phase timing
│   ├── pose_extractor.py    # MediaPipe pose per frame, bowler tracking
│   ├── xfactor_compute.py   # Hip-shoulder separation computation
│   ├── overlay_renderer.py  # Draw lines, angle, phase label per frame
│   └── video_composer.py    # Assemble final 9:16 video + FFmpeg encode
├── config/                  # Future: per-video configs
├── output/                  # Generated videos + manifests
├── .env                     # Gemini API key (gitignored)
├── .gitignore
└── venv/                    # Python 3.12 virtual environment (gitignored)
```

## Rating calibration

| Separation | Rating | Reference |
|-----------|--------|-----------|
| 45°+ | ELITE | Brett Lee (~47°), peak Steyn |
| 35-44° | VERY GOOD | Strong rotational mechanics |
| 28-34° | DEVELOPING | Room to lead more with hip |
| <28° | WORK ON IT | Focus on hip pre-rotation drills |

Note: Angles are 2D projections. Side-on camera gives most accurate reading.

## Future technique videos (v0.0.1 each)

- [ ] Arm Slot — bowling arm angle at release
- [ ] Front Knee Brace — stiffness at front foot contact
- [ ] Speed Estimation — frame-diff kph
- [ ] DNA Match — closest famous bowler comparison
