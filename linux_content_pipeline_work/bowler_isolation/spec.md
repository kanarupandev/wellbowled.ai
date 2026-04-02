# Bowler Isolation — Spec for Other Agent

## WHY

Every content pipeline (X-Factor, Speed Gradient, Kinogram, all 6) fails when there are multiple people in frame. The bowler gets confused with umpire, batsman, fielders, background people. This is the #1 blocker across ALL techniques.

Solving bowler isolation solves it for everything. Build once, use everywhere.

## WHAT

**Input:** Any bowling video clip (3-60 seconds, any camera angle, any number of people)

**Output:** Same video with ONLY the bowler visible. Everything else is black.

The output video is then fed into any analysis pipeline (X-Factor, Speed Gradient, etc.) and MediaPipe will only ever see one person.

## FUNCTIONAL REQUIREMENTS

1. Given a video, identify which person is the bowler
2. Segment the bowler from background across ALL frames
3. Maintain temporal consistency (no flickering, no jumping between people)
4. Handle: broadcast wide shots, nets sessions, close-ups, side-on, behind-bowler
5. Handle: multiple people (umpire, batsman, keeper, fielders, spectators)
6. Output: MP4 with bowler on black background, same resolution and fps as input
7. Also output: per-frame binary mask (for compositing later)

## HOW TO IDENTIFY THE BOWLER

Two-step process:

### Step 1: Gemini Flash (1 call)
Send contact sheet → get bowler's approximate bounding box in the first frame where they're visible. Also get: bowling arm (left/right), action start/end timestamps.

This gives us the INITIAL point to click on.

### Step 2: SAM 2 (local, CPU)
- Load the video
- Use Gemini's bounding box center as the initial prompt point
- SAM 2 propagates the segmentation through all frames
- Output: per-frame mask

### Fallback (no Gemini):
- Use MediaPipe to detect all poses in first few frames
- Pick the person who moves the most (the bowler is running)
- Use their center as SAM 2 initial point

## PERFORMANCE BUDGET

- 1-minute clip (1800 frames at 30fps): up to 10 hours on CPU is acceptable
- 3-second clip: should complete in under 30 minutes
- Can run overnight for longer clips

## SAM 2 SETUP

```bash
# Clone and install
git clone https://github.com/facebookresearch/sam2.git
cd sam2
pip install -e .

# Download model checkpoint (smallest for CPU)
# sam2.1_hiera_tiny.pt — smallest, fastest
# sam2.1_hiera_small.pt — better quality
# sam2.1_hiera_base_plus.pt — best quality (recommended for overnight runs)
```

Requires: Python >= 3.10, torch >= 2.5.1

### CPU usage
```python
import torch
# Force CPU
device = torch.device("cpu")
predictor = SAM2VideoPredictor.from_pretrained("facebook/sam2.1-hiera-base-plus", device=device)
```

## OUTPUT FORMAT

```
output/
├── isolated_bowler.mp4      # Bowler on black background
├── masks/                    # Per-frame binary masks (PNG)
│   ├── frame_0000.png
│   ├── frame_0001.png
│   └── ...
└── metadata.json            # Bowler bbox, confidence, frame count
```

## USAGE IN DOWNSTREAM PIPELINES

```python
# Any pipeline can now do:
isolated_clip = "output/isolated_bowler.mp4"
# MediaPipe will ONLY see the bowler — no confusion possible
poses = extract_poses(isolated_clip)  # guaranteed single-person detection
```

## QUALITY CHECKLIST

- [ ] Only the bowler is visible in every frame
- [ ] No flickering/jumping between frames
- [ ] Bowler's full body is preserved (not clipped at edges)
- [ ] Arms and legs fully segmented (not cut off during delivery stride)
- [ ] Works on broadcast footage (small bowler in wide shot)
- [ ] Works on nets footage (multiple people nearby)
- [ ] Consistent mask even when bowler overlaps with umpire
- [ ] Black background is truly black (0,0,0) — no artifacts

## EXISTING WORK IN OTHER DOMAINS

- **Golf biomechanics**: Common to isolate the golfer from background for swing analysis
- **Baseball**: Sequence Biomechanics Performance Lab does pitcher isolation
- **Film/VFX**: SAM 2 is already used for video cutouts and compositing (CineD, Adobe)
- **Sports broadcast**: AI-powered graphics overlay systems isolate players routinely

## REFERENCES

- SAM 2 repo: https://github.com/facebookresearch/sam2
- Video background removal tutorial: https://www.adwaitx.com/how-to-use-meta-sam-2-remove-video-background/
- SAM 2 on Replicate (API alternative): https://replicate.com/meta/sam-2-video
