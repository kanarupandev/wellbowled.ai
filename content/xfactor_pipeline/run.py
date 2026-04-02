#!/usr/bin/env python3
"""X-Factor v1.0.0 Pipeline -- single entry point.

Produces a YouTube-upload-ready 9:16 video from any bowling clip.

Usage:
    python run.py <input_clip>

Example:
    python run.py ../../resources/samples/3_sec_1_delivery_nets.mp4
"""
from __future__ import annotations

import json
import sys
import time
from pathlib import Path

# Resolve paths relative to this file
PIPELINE_DIR = Path(__file__).resolve().parent
REPO_ROOT = PIPELINE_DIR.parents[1]
OUTPUT_DIR = PIPELINE_DIR / "output"

# Ensure content/ is on sys.path so 'from xfactor_pipeline.X import Y' works
_content_dir = str(PIPELINE_DIR.parent)
if _content_dir not in sys.path:
    sys.path.insert(0, _content_dir)


def main(input_clip: str) -> str:
    start = time.time()

    clip_path = Path(input_clip).resolve()
    if not clip_path.exists():
        print(f"ERROR: Input clip not found: {clip_path}")
        sys.exit(1)

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    output_path = str(OUTPUT_DIR / "final.mp4")

    print("=" * 56)
    print("  X-FACTOR v1.0.0 PIPELINE")
    print("=" * 56)
    print(f"  Input:  {clip_path}")
    print(f"  Output: {output_path}")
    print()

    # ------------------------------------------------------------------
    # Stage 1: Gemini Flash -- identify bowler ROI + phases (max 1 call)
    # ------------------------------------------------------------------
    print("[1/5] Gemini Flash planner...")
    from xfactor_pipeline.flash_planner import call_flash
    flash_result = call_flash(
        str(clip_path),
        output_dir=str(OUTPUT_DIR),
    )

    bowler_roi = None
    flash_phases = None
    if flash_result:
        bowler_roi = flash_result.get("bowler_roi")
        flash_phases = flash_result.get("phases")
        print(f"       ROI: {bowler_roi}")
        print(f"       Phases: {flash_phases}")
    else:
        print("       Using heuristic fallback (no Flash result)")

    # ------------------------------------------------------------------
    # Stage 2: MediaPipe pose extraction (cropped to bowler ROI)
    # ------------------------------------------------------------------
    print("\n[2/5] Pose extraction (MediaPipe Heavy)...")
    from xfactor_pipeline.pose_extractor import extract_poses
    pose_data = extract_poses(str(clip_path), bowler_roi=bowler_roi)

    frames = pose_data["frames"]
    src_fps = pose_data["fps"]
    print(f"       Source: {pose_data['width']}x{pose_data['height']} @ {src_fps}fps, "
          f"{len(frames)} frames")

    # ------------------------------------------------------------------
    # Stage 3: X-factor computation (smoothing + side-on noise rejection)
    # ------------------------------------------------------------------
    print("\n[3/5] X-factor computation...")
    from xfactor_pipeline.xfactor_compute import (
        compute_xfactor,
        detect_phases_heuristic,
        find_peak_separation,
    )
    frames = compute_xfactor(frames)
    peak_frame = find_peak_separation(frames)

    # Use Flash phases if available, otherwise heuristic
    if flash_phases:
        phases = flash_phases
        print("       Using Gemini Flash phase timing")
    else:
        phases = detect_phases_heuristic(frames)
        print("       Using heuristic phase timing")

    if peak_frame:
        print(f"       Peak separation: {peak_frame['separation']:.1f} deg "
              f"at t={peak_frame['time']:.3f}s (frame {peak_frame['index']})")
    else:
        print("       WARNING: No valid separation detected")

    print(f"       Phases: {phases}")

    # Dump x-factor data for debugging
    xf_debug = {
        "peak_separation": peak_frame["separation"] if peak_frame else None,
        "peak_time": peak_frame["time"] if peak_frame else None,
        "peak_index": peak_frame["index"] if peak_frame else None,
        "phases": phases,
        "per_frame": [
            {
                "index": f["index"],
                "time": f["time"],
                "separation": f.get("separation"),
                "separation_raw": f.get("separation_raw"),
            }
            for f in frames
        ],
    }
    with open(OUTPUT_DIR / "xfactor_debug.json", "w") as fh:
        json.dump(xf_debug, fh, indent=2)

    # ------------------------------------------------------------------
    # Stage 4: Generate coaching insight (heuristic, no extra API call)
    # ------------------------------------------------------------------
    print("\n[4/5] Generating insight...")
    peak_sep = peak_frame["separation"] if peak_frame else 0
    if peak_sep >= 45:
        insight_lines = [
            "Elite hip-shoulder separation.",
            "This is where express pace comes from -- the trunk stores elastic energy.",
            "Maintain this with core and hip mobility work.",
        ]
    elif peak_sep >= 35:
        insight_lines = [
            "Strong rotational mechanics.",
            f"At {peak_sep:.0f} degrees the hips lead well. Delaying the shoulders more would unlock extra speed.",
            "Work on thoracic mobility and delayed shoulder rotation.",
        ]
    elif peak_sep >= 28:
        insight_lines = [
            "Good foundation to build on.",
            f"{peak_sep:.0f} degrees of separation shows the hips are starting to lead.",
            "Focus on driving the front hip through earlier in the delivery stride.",
        ]
    else:
        insight_lines = [
            "Limited separation -- hips and shoulders move together.",
            f"Only {peak_sep:.0f} degrees means the trunk is not storing energy efficiently.",
            "Hip mobility drills and delayed shoulder rotation are the keys.",
        ]
    for line in insight_lines:
        print(f"       {line}")

    # ------------------------------------------------------------------
    # Stage 5: Compose final video
    # ------------------------------------------------------------------
    print("\n[5/5] Composing video...")
    from xfactor_pipeline.video_composer import compose_video
    final = compose_video(
        frames=frames,
        peak_frame=peak_frame,
        phases=phases,
        output_path=output_path,
        fps=src_fps,
        insight_lines=insight_lines,
    )

    elapsed = time.time() - start
    print()
    print("=" * 56)
    print(f"  DONE in {elapsed:.1f}s")
    print(f"  Output: {final}")
    if peak_frame:
        print(f"  Peak X-Factor: {peak_frame['separation']:.1f} deg")
    print("=" * 56)

    return final


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python run.py <input_clip>")
        print("Example: python run.py ../../resources/samples/3_sec_1_delivery_nets.mp4")
        sys.exit(1)
    main(sys.argv[1])
