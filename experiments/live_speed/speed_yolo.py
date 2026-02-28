"""
Speed Estimation via YOLO Ball Tracking
========================================
Uses YOLOv8 to detect cricket ball in clip frames, tracks trajectory,
estimates speed from pixel displacement.

Usage:
  python speed_yolo.py [--clip-dir DIR]
"""

import argparse
import glob
import json
import math
import os
import cv2
import numpy as np
from ultralytics import YOLO

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))

# COCO class 32 = "sports ball"
BALL_CLASS = 32

# Approximate bowler height in pixels (used for scale estimation)
# Average male height ~1.75m. We estimate pixels-per-meter from this.
BOWLER_HEIGHT_M = 1.75


def estimate_scale(frame):
    """Rough scale estimation: assume frame height covers ~3m of scene."""
    return frame.shape[0] / 3.0  # pixels per meter (rough)


def track_ball(clip_path, model, conf_threshold=0.15):
    """Detect and track ball across frames. Returns list of (frame_idx, cx, cy, conf)."""
    cap = cv2.VideoCapture(clip_path)
    fps = cap.get(cv2.CAP_PROP_FPS)
    detections = []
    frame_idx = 0

    while True:
        ret, frame = cap.read()
        if not ret:
            break

        results = model(frame, conf=conf_threshold, verbose=False)

        for r in results:
            for box in r.boxes:
                cls = int(box.cls[0])
                conf = float(box.conf[0])
                if cls == BALL_CLASS:
                    x1, y1, x2, y2 = box.xyxy[0].tolist()
                    cx = (x1 + x2) / 2
                    cy = (y1 + y2) / 2
                    detections.append({
                        "frame": frame_idx,
                        "cx": cx, "cy": cy,
                        "conf": conf,
                        "w": x2 - x1, "h": y2 - y1,
                    })

        frame_idx += 1

    cap.release()
    return detections, fps, frame_idx


def compute_speed(detections, fps, pixels_per_meter):
    """Compute speed from consecutive ball detections. Returns list of speed dicts."""
    if len(detections) < 2:
        return []

    # Sort by frame
    dets = sorted(detections, key=lambda d: d["frame"])

    speeds = []
    for i in range(1, len(dets)):
        d0, d1 = dets[i - 1], dets[i]
        frame_diff = d1["frame"] - d0["frame"]
        if frame_diff == 0 or frame_diff > 5:  # skip if too far apart
            continue

        dx = d1["cx"] - d0["cx"]
        dy = d1["cy"] - d0["cy"]
        pixel_dist = math.sqrt(dx * dx + dy * dy)
        meter_dist = pixel_dist / pixels_per_meter
        time_diff = frame_diff / fps
        speed_ms = meter_dist / time_diff
        speed_kph = speed_ms * 3.6

        speeds.append({
            "frames": [d0["frame"], d1["frame"]],
            "pixel_dist": pixel_dist,
            "meter_dist": meter_dist,
            "time_s": time_diff,
            "speed_kph": speed_kph,
        })

    return speeds


def main():
    parser = argparse.ArgumentParser(description="YOLO ball tracking speed estimation")
    parser.add_argument("--clip-dir", "-d", default=os.path.join(SCRIPT_DIR, "clips"))
    parser.add_argument("--model", "-m", default="yolov8n.pt", help="YOLO model")
    args = parser.parse_args()

    clips = sorted(glob.glob(os.path.join(args.clip_dir, "gt_delivery_*.mp4")))
    if not clips:
        print("No GT clips found.")
        return

    print(f"Loading YOLO model: {args.model}")
    model = YOLO(args.model)
    print(f"Clips: {len(clips)}")
    print()

    all_results = {}

    for clip_path in clips:
        clip_name = os.path.basename(clip_path)
        print(f"--- {clip_name} ---")

        detections, fps, total_frames = track_ball(clip_path, model)
        print(f"  Frames: {total_frames}, FPS: {fps:.0f}")
        print(f"  Ball detections: {len(detections)}")

        if detections:
            for d in detections[:10]:  # show first 10
                print(f"    Frame {d['frame']}: ({d['cx']:.0f},{d['cy']:.0f}) "
                      f"conf={d['conf']:.2f} size={d['w']:.0f}x{d['h']:.0f}")
            if len(detections) > 10:
                print(f"    ... and {len(detections) - 10} more")

            # Estimate scale from first frame
            cap = cv2.VideoCapture(clip_path)
            ret, frame = cap.read()
            cap.release()
            ppm = estimate_scale(frame)
            print(f"  Scale estimate: {ppm:.0f} px/m")

            speeds = compute_speed(detections, fps, ppm)
            if speeds:
                speed_values = [s["speed_kph"] for s in speeds]
                avg_speed = sum(speed_values) / len(speed_values)
                print(f"  Speed estimates: {[f'{s:.0f}' for s in speed_values]} kph")
                print(f"  Average: {avg_speed:.0f} kph")
            else:
                print("  Could not compute speed (detections too sparse)")
                speeds = []
        else:
            print("  No ball detected in any frame")
            speeds = []

        all_results[clip_name] = {
            "total_frames": total_frames,
            "fps": fps,
            "ball_detections": len(detections),
            "detections": detections[:20],  # save first 20
            "speeds": speeds,
        }
        print()

    # Save
    result_path = os.path.join(SCRIPT_DIR, "result_speed_yolo.json")
    with open(result_path, "w") as f:
        json.dump({"model": args.model, "results": all_results}, f, indent=2)
    print(f"Saved: {result_path}")


if __name__ == "__main__":
    main()
