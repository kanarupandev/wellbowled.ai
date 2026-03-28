# Standalone Bowling Video Annotation Prototype

## Goal

Build an isolated, human-in-the-loop bowling video annotation and analysis tool that can turn a raw clip into:

- an annotated vertical analysis video
- a polished freeze-frame hero image
- a storyboard preview for review

This prototype is optimized for reliability over full automation. The intended workflow is that a human can spend 10-20 minutes shaping timestamps, crop bounds, and cue text per clip.

The current direction is now a two-call architecture:

- `Flash` for rough shaping decisions
- `Pro` only if a second pass is worth spending
- local rendering remains deterministic

## Why this clip

Input clip:

- `/Users/kanarupan/workspace/wellbowled.ai/resources/samples/3_sec_1_delivery_nets.mp4`

Reasoning:

- `bumrah_bairstow_swing.mp4` looked more premium, but full-frame pose tracking drifted onto the umpire and batsman at key moments.
- `umran_malik_150kph.mp4` already had baked-in social overlays and watermark noise.
- `3_sec_1_delivery_nets.mp4` gave the cleanest single-bowler geometry once a bowler ROI crop was applied.

## What the tool does

Config:

- `/Users/kanarupan/workspace/wellbowled.ai/content/codex_lab/public_clip_analysis/tool/story_nets_release.json`

Renderer:

- `/Users/kanarupan/workspace/wellbowled.ai/content/codex_lab/public_clip_analysis/tool/render_bowling_analysis.py`

Flash planner:

- `/Users/kanarupan/workspace/wellbowled.ai/content/codex_lab/public_clip_analysis/tool/plan_with_flash.py`

Current pipeline:

1. Trim a short segment from the source clip.
2. Extract a timestamped storyboard for a Gemini Flash planning pass.
3. Run MediaPipe pose per frame on a bowler ROI crop.
4. Use the planned or fallback phase hints for `load`, `release`, `freeze`, and `finish`.
5. Build a vertical draft with:
   - intro panel
   - quarter-speed live analysis phase frames
   - color-coded pose guides and metric chips
   - freeze-frame hero overlay
   - end card
6. Export a review storyboard image alongside the MP4.

## Key reliability decisions

- Manual timestamps beat pose confidence.
- Bowler-only ROI crop beats full-frame pose estimation for this type of clip.
- Per-frame image detection was more reliable than MediaPipe video tracking in the follow-through window.
- The renderer now slows the sequence to `0.25x` using frame holds rather than lowering analysis density.
- Gemini should replace shaping decisions first, not just write nicer copy.
- The system is designed to be shaped, not blindly trusted.

## Final artifacts

Output directory:

- `/Users/kanarupan/workspace/wellbowled.ai/content/codex_lab/public_clip_analysis/output/nets_release_window`

Main deliverables:

- Video: `/Users/kanarupan/workspace/wellbowled.ai/content/codex_lab/public_clip_analysis/output/nets_release_window/annotated_analysis.mp4`
- Hero frame: `/Users/kanarupan/workspace/wellbowled.ai/content/codex_lab/public_clip_analysis/output/nets_release_window/hero_release_frame.jpg`
- Storyboard: `/Users/kanarupan/workspace/wellbowled.ai/content/codex_lab/public_clip_analysis/output/nets_release_window/storyboard.jpg`
- Manifest: `/Users/kanarupan/workspace/wellbowled.ai/content/codex_lab/public_clip_analysis/output/nets_release_window/artifact_manifest.json`
- Flash planning board: `/Users/kanarupan/workspace/wellbowled.ai/content/codex_lab/public_clip_analysis/output/nets_release_window/flash_storyboard_prompt.jpg`

## Verification summary

- Export metadata:
  - 30 fps
  - 480 x 848
  - 73 frames in the trimmed segment
- Final shaped timings:
  - release: `1.0s`
  - freeze: `1.5s`
  - finish: `1.7s`
- Verified visually:
  - the slow-motion sequence now includes color-coded arm / shoulder / torso / front-leg guides
  - the freeze-frame skeleton now lands on the bowler, not the background observer
  - the hero card and storyboard export successfully
  - the MP4 export completes successfully

## Gemini usage

- Planned architecture:
  - Call 1: Gemini Flash for storyboard-based shaping
  - Call 2: Gemini Pro only for final coaching copy if needed
- Actual run status:
  - One Gemini Flash call was attempted from `plan_with_flash.py`
  - Result: invalid local API key
  - Error returned: `API Key not found. Please pass a valid API key.`
  - Because the credential is invalid, the final export uses deterministic fallback hints and local copy
- Related files:
  - `/Users/kanarupan/workspace/wellbowled.ai/content/codex_lab/public_clip_analysis/output/nets_release_window/gemini_flash_plan.json` is not present because the call failed before a plan could be written
  - `/Users/kanarupan/workspace/wellbowled.ai/content/codex_lab/public_clip_analysis/output/nets_release_window/gemini_draft.json` contains the earlier failed draft attempt

## How to rerun

```bash
source /Users/kanarupan/workspace/wellbowled.ai/content/codex_lab/public_clip_analysis/.venv/bin/activate
python /Users/kanarupan/workspace/wellbowled.ai/content/codex_lab/public_clip_analysis/tool/plan_with_flash.py \
  /Users/kanarupan/workspace/wellbowled.ai/content/codex_lab/public_clip_analysis/tool/story_nets_release.json

python /Users/kanarupan/workspace/wellbowled.ai/content/codex_lab/public_clip_analysis/tool/render_bowling_analysis.py \
  /Users/kanarupan/workspace/wellbowled.ai/content/codex_lab/public_clip_analysis/tool/story_nets_release.json \
  --skip-gemini
```

## Next improvements

1. Fix the local Gemini credential so the Flash planning stage can actually replace rough shaping.
2. Add a UI for drawing or confirming the bowler ROI and phase timestamps on top of the video.
3. Add a per-frame release-point detector so freeze selection can be suggested automatically.
4. Export editable overlay metadata for CapCut or DaVinci refinement.
