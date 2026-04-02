"""Stage 1: Extract frames from bowling clip at ~10fps + contact sheet."""
from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

INPUT_CLIP = Path(__file__).resolve().parents[2] / "resources" / "samples" / "3_sec_1_delivery_nets.mp4"
OUTPUT_DIR = Path(__file__).resolve().parent / "output"
FRAMES_DIR = OUTPUT_DIR / "frames"
CONTACT_SHEET = OUTPUT_DIR / "contact_sheet.jpg"
METADATA_FILE = OUTPUT_DIR / "clip_metadata.json"


def run(input_clip: Path | None = None) -> dict:
    clip = input_clip or INPUT_CLIP
    if not clip.exists():
        raise FileNotFoundError(f"Input clip not found: {clip}")

    FRAMES_DIR.mkdir(parents=True, exist_ok=True)

    # Get clip metadata
    probe = subprocess.run(
        ["ffprobe", "-v", "quiet", "-print_format", "json", "-show_streams", str(clip)],
        capture_output=True, text=True, check=True,
    )
    streams = json.loads(probe.stdout)["streams"]
    video_stream = next(s for s in streams if s["codec_type"] == "video")

    w, h = int(video_stream["width"]), int(video_stream["height"])
    fps = eval(video_stream["r_frame_rate"])  # e.g. "30/1"
    duration = float(video_stream["duration"])
    nb_frames = int(video_stream["nb_frames"])

    # Check for rotation (phone videos store 848x480 with rotation=-90 → actual 480x848)
    rotation = 0
    for sd in video_stream.get("side_data_list", []):
        if "rotation" in sd:
            rotation = int(sd["rotation"])

    if abs(rotation) == 90:
        actual_w, actual_h = h, w
    else:
        actual_w, actual_h = w, h

    metadata = {
        "width": actual_w,
        "height": actual_h,
        "stored_width": w,
        "stored_height": h,
        "fps": fps,
        "duration": duration,
        "nb_frames": nb_frames,
        "rotation": rotation,
        "input_clip": str(clip),
    }

    # Extract frames at 10fps with auto-rotation applied
    subprocess.run(
        [
            "ffmpeg", "-y", "-i", str(clip),
            "-vf", "fps=10",
            "-q:v", "2",
            str(FRAMES_DIR / "frame_%04d.jpg"),
        ],
        capture_output=True, check=True,
    )

    # Count extracted frames
    extracted = sorted(FRAMES_DIR.glob("frame_*.jpg"))
    metadata["extracted_frames"] = len(extracted)
    print(f"  Extracted {len(extracted)} frames at 10fps")

    # Build contact sheet (2x4 grid)
    subprocess.run(
        [
            "ffmpeg", "-y", "-i", str(clip),
            "-vf", "fps=3,tile=2x4",
            "-frames:v", "1",
            "-q:v", "2",
            str(CONTACT_SHEET),
        ],
        capture_output=True, check=True,
    )
    print(f"  Contact sheet: {CONTACT_SHEET}")

    # Save metadata
    with open(METADATA_FILE, "w") as f:
        json.dump(metadata, f, indent=2)

    return metadata


if __name__ == "__main__":
    clip = Path(sys.argv[1]) if len(sys.argv) > 1 else None
    result = run(clip)
    print(json.dumps(result, indent=2))
