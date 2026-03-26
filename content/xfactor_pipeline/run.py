#!/usr/bin/env python3
"""X-Factor Pipeline — Main Orchestrator.

Usage: python run.py [input_clip]
"""
from __future__ import annotations

import sys
import time
from pathlib import Path


def main(input_clip: Path | None = None):
    start = time.time()

    print("=" * 50)
    print("  X-FACTOR PIPELINE")
    print("=" * 50)

    # Stage 1: Extract frames
    print("\n[1/7] Extracting frames...")
    import extract_frames
    metadata = extract_frames.run(input_clip)

    # Stage 2: Flash planner
    print("\n[2/7] Planning with Gemini Flash...")
    import flash_planner
    plan = flash_planner.run()

    # Stage 3: Pose extraction
    print("\n[3/7] Extracting pose landmarks...")
    import pose_extractor
    pose_data = pose_extractor.run()

    # Stage 4: X-Factor computation
    print("\n[4/7] Computing X-Factor angles...")
    import xfactor_compute
    xfactor = xfactor_compute.run()

    # Stage 5: Overlay rendering
    print("\n[5/7] Rendering overlays...")
    import overlay_renderer
    overlay_renderer.run()

    # Stage 6: Pro insight (optional)
    print("\n[6/7] Getting coaching insight...")
    import pro_insight
    insight = pro_insight.run()

    # Stage 7: Video composition
    print("\n[7/7] Composing final video...")
    import video_composer
    final_path = video_composer.run()

    elapsed = time.time() - start
    print("\n" + "=" * 50)
    print(f"  DONE in {elapsed:.1f}s")
    print(f"  Output: {final_path}")
    print(f"  Peak X-Factor: {xfactor['peak_separation_angle']}°")
    print("=" * 50)


if __name__ == "__main__":
    clip = Path(sys.argv[1]) if len(sys.argv) > 1 else None
    main(clip)
