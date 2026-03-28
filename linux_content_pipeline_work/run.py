#!/usr/bin/env python3
"""X-Factor Content Pipeline — Main Orchestrator.

Usage:
    ./run.py <input_clip.mp4> [--output-dir <dir>]

Takes a raw bowling clip, produces a YouTube-upload-ready annotated analysis video
showing hip-shoulder separation (the X-Factor).
"""
from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

# Ensure src is importable
sys.path.insert(0, str(Path(__file__).resolve().parent))

from src.flash_planner import call_flash
from src.pose_extractor import extract_poses
from src.xfactor_compute import compute_xfactor, detect_phases_heuristic, find_peak_separation
from src.video_composer import compose_video


def main():
    parser = argparse.ArgumentParser(description="X-Factor bowling analysis pipeline")
    parser.add_argument("input", help="Path to input bowling clip (MP4)")
    parser.add_argument("--output-dir", default=None, help="Output directory (default: ./output/<clip_name>)")
    parser.add_argument("--skip-gemini", action="store_true", help="Skip Gemini calls (use heuristics only)")
    args = parser.parse_args()

    input_path = Path(args.input).resolve()
    if not input_path.exists():
        print(f"Error: {input_path} not found")
        sys.exit(1)

    clip_name = input_path.stem
    output_dir = Path(args.output_dir) if args.output_dir else Path(__file__).resolve().parent / "output" / clip_name
    output_dir.mkdir(parents=True, exist_ok=True)

    print(f"=== X-Factor Pipeline ===")
    print(f"Input:  {input_path}")
    print(f"Output: {output_dir}")
    print()

    # Stage 1: Gemini Flash — identify the bowler (Call 1 of 2)
    bowler_roi = None
    flash_phases = None
    if not args.skip_gemini:
        t0 = time.time()
        print("[1/5] Calling Gemini Flash to identify the bowler...")
        flash_result = call_flash(str(input_path), str(output_dir))
        if flash_result:
            bowler_roi = flash_result.get("bowler_roi")
            flash_phases = flash_result.get("phases")
            print(f"       ({time.time() - t0:.1f}s)")
        else:
            print("       Skipped — using full frame")
        print()

    # Stage 3: Pose extraction (cropped to bowler ROI if available)
    t0 = time.time()
    print("[2/5] Extracting poses with MediaPipe...")
    pose_data = extract_poses(str(input_path), bowler_roi=bowler_roi)
    frames = pose_data["frames"]
    fps = pose_data["fps"]
    print(f"       {len(frames)} frames @ {fps:.1f}fps ({time.time() - t0:.1f}s)")

    poses_with_landmarks = sum(1 for f in frames if f["landmarks"] is not None)
    print(f"       Bowler detected in {poses_with_landmarks}/{len(frames)} frames")
    print()

    # Stage 4: X-factor computation
    t0 = time.time()
    print("[3/5] Computing X-factor per frame...")
    frames = compute_xfactor(frames)
    peak = find_peak_separation(frames)

    # Use Flash phases if available, otherwise heuristic
    if flash_phases:
        phases = flash_phases
        print(f"       Using Gemini Flash phase timing")
    else:
        phases = detect_phases_heuristic(frames)

    if peak:
        print(f"       Peak separation: {peak['separation']:.1f}\u00b0 at {peak['time']:.2f}s")
    else:
        print("       WARNING: No valid separation detected")
    print(f"       Phases: {json.dumps({k: round(v, 2) for k, v in phases.items()})}")
    print(f"       ({time.time() - t0:.2f}s)")
    print()

    # Stage 6+8: Video composition
    t0 = time.time()
    output_video = str(output_dir / "xfactor_analysis.mp4")
    print("[4/5] Composing video...")
    compose_video(
        frames=frames,
        peak_frame=peak,
        phases=phases,
        output_path=output_video,
        fps=fps,
    )
    print(f"       ({time.time() - t0:.1f}s)")
    print()

    # Save metadata
    manifest = {
        "input": str(input_path),
        "output_video": output_video,
        "fps": fps,
        "total_frames": len(frames),
        "poses_detected": poses_with_landmarks,
        "peak_separation": round(peak["separation"], 1) if peak else None,
        "peak_time": round(peak["time"], 3) if peak else None,
        "phases": {k: round(v, 3) for k, v in phases.items()},
        "bowler_roi": bowler_roi,
    }
    manifest_path = output_dir / "manifest.json"
    with manifest_path.open("w") as f:
        json.dump(manifest, f, indent=2)

    print(f"[5/5] Done!")
    print(f"       Video: {output_video}")
    print(f"       Manifest: {manifest_path}")


if __name__ == "__main__":
    main()
