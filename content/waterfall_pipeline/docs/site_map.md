# Velocity Waterfall Pipeline — Site Map

## Directory Structure

```
content/waterfall_pipeline/
├── run.py              # v0.0.1 (original, kept for reference)
├── run_v100.py         # v1.0.0 production pipeline
├── .gitignore
├── .venv -> ../xfactor_pipeline/.venv
├── docs/
│   ├── site_map.md           # This file
│   ├── design_spec.md        # Visual specification
│   ├── quality_gate.md       # 80-point QA checklist
│   └── broadcast_angle.md    # Camera angle assumptions
└── output/                   # .gitignored
    ├── frames/               # 10fps extracted frames
    ├── annotated/            # Per-frame rendered canvases
    ├── flash_plan.json       # Gemini Flash response (cached)
    ├── velocity_data.json    # Per-frame velocity + sequencing
    ├── waterfall.mp4         # Final video
    └── review/               # QA screenshots at key timestamps
```

## Dependencies

- Python 3.12+ (shared venv via xfactor_pipeline)
- mediapipe (pose_landmarker_heavy.task)
- opencv-python, numpy, Pillow
- scipy (savgol_filter for velocity smoothing)
- FFmpeg (system)
- Gemini Flash 2.5 (optional, for bowler ROI)

## Input

Any bowling clip (MP4, 2-10s). Standard camera angles:
- Nets: phone ~3-5m, 30-45° behind bowling arm
- Broadcast: end-on, side-on, or fine leg

## Output

9:16 Instagram Reel (1080x1920, H.264, 30fps, 15-25s)
