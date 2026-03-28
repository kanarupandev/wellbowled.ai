# SAM 2 Large — Mac Setup Spec

## Decision
Use SAM 2 with `sam2.1_hiera_large` checkpoint — same model as Meta's demo site.
Run locally on Mac (24GB RAM, Apple Silicon MPS acceleration).

## Setup

```bash
# 1. Create dedicated environment
conda create -n sam2 python=3.11
conda activate sam2

# 2. Install PyTorch with MPS support
pip install torch torchvision

# 3. Clone and install SAM 2
git clone https://github.com/facebookresearch/sam2.git
cd sam2
pip install -e .

# 4. Download the large checkpoint
cd checkpoints
./download_ckpts.sh
# This downloads all checkpoints. The one we want:
# sam2.1_hiera_large.pt (224 MB)
```

## Usage for Bowler Isolation

```python
import torch
from sam2.build_sam import build_sam2_video_predictor

# Use MPS on Mac (Apple Silicon GPU acceleration)
device = torch.device("mps")

predictor = build_sam2_video_predictor(
    "configs/sam2.1/sam2.1_hiera_l.yaml",
    "checkpoints/sam2.1_hiera_large.pt",
    device=device,
)

# Initialize with video
state = predictor.init_state(video_path="bowling_clip.mp4")

# Add prompt: click on the bowler in frame 0
# (x, y) from Gemini Flash or manual selection
predictor.add_new_points_or_box(
    state,
    frame_idx=0,
    obj_id=1,
    points=[[bowler_x, bowler_y]],
    labels=[1],  # 1 = foreground
)

# Propagate through all frames
masks = {}
for frame_idx, obj_ids, mask_logits in predictor.propagate_in_video(state):
    masks[frame_idx] = (mask_logits[0] > 0.0).cpu().numpy()

# Apply masks: bowler on black background
import cv2
cap = cv2.VideoCapture("bowling_clip.mp4")
writer = cv2.VideoWriter("bowler_isolated.mp4", ...)
for idx in range(len(masks)):
    ok, frame = cap.read()
    mask = masks[idx]
    isolated = frame * mask[:, :, None]  # black everything except bowler
    writer.write(isolated)
```

## Workflow

```
Mac (SAM 2):
  Input:  any bowling clip (broadcast, nets, any angle)
  Step 1: Gemini Flash → bowler center point (x, y) in first frame
  Step 2: SAM 2 large → per-frame mask → isolated bowler on black
  Output: bowler_isolated.mp4 + masks/

Linux (analysis):
  Input:  bowler_isolated.mp4
  Step 1: MediaPipe pose → perfect single-person detection
  Step 2: Velocity computation → energy flow
  Step 3: Render → final video
  Output: upload-ready content
```

## Expected Performance on Mac (24GB RAM, Apple Silicon)

| Clip length | Frames (30fps) | Estimated time (MPS) |
|-------------|----------------|---------------------|
| 3 seconds | 90 | ~30 sec - 2 min |
| 10 seconds | 300 | ~2-5 min |
| 30 seconds | 900 | ~5-15 min |
| 1 minute | 1800 | ~15-30 min |

## Hardware Requirements

- RAM: 12 GB minimum, 24 GB comfortable ✓
- Disk: ~3 GB (PyTorch + SAM 2 + checkpoints)
- Python: 3.10+ ✓
- macOS: 12.3+ for MPS support

## Quality

Same model as https://sam2.metademolab.com/demo
Best segmentation quality available. No compromise.
