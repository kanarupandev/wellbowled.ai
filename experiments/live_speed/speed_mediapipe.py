"""
Wrist Velocity Analysis via MediaPipe
=======================================
Tracks bowler's wrist landmark velocity through the delivery to
estimate release speed. Uses MediaPipe Tasks API (v0.10+).

Usage:
  python speed_mediapipe.py [--clip-dir DIR]
"""

import argparse
import glob
import json
import math
import os
import cv2
import mediapipe as mp
import numpy as np

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
MODEL_PATH = os.path.join(SCRIPT_DIR, "../../resources/pose_landmarker_heavy.task")

# PoseLandmark indices
RIGHT_WRIST = 16
LEFT_WRIST = 15
RIGHT_SHOULDER = 12
LEFT_SHOULDER = 11
RIGHT_ELBOW = 14
LEFT_ELBOW = 13


def analyze_clip(clip_path):
    """Track wrist velocity through delivery clip using MediaPipe Tasks API."""
    BaseOptions = mp.tasks.BaseOptions
    PoseLandmarker = mp.tasks.vision.PoseLandmarker
    PoseLandmarkerOptions = mp.tasks.vision.PoseLandmarkerOptions
    RunningMode = mp.tasks.vision.RunningMode

    options = PoseLandmarkerOptions(
        base_options=BaseOptions(model_asset_path=MODEL_PATH),
        running_mode=RunningMode.VIDEO,
        num_poses=1,
        min_pose_detection_confidence=0.5,
        min_tracking_confidence=0.5,
    )

    cap = cv2.VideoCapture(clip_path)
    fps = cap.get(cv2.CAP_PROP_FPS)
    width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))

    frames_data = []
    frame_idx = 0

    with PoseLandmarker.create_from_options(options) as landmarker:
        while True:
            ret, frame = cap.read()
            if not ret:
                break

            rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)
            timestamp_ms = int(frame_idx * 1000 / fps)

            result = landmarker.detect_for_video(mp_image, timestamp_ms)

            entry = {"frame": frame_idx, "time": frame_idx / fps}

            if result.pose_landmarks and len(result.pose_landmarks) > 0:
                lm = result.pose_landmarks[0]

                for name, idx in [("right_wrist", RIGHT_WRIST), ("left_wrist", LEFT_WRIST),
                                  ("right_shoulder", RIGHT_SHOULDER), ("left_shoulder", LEFT_SHOULDER),
                                  ("right_elbow", RIGHT_ELBOW), ("left_elbow", LEFT_ELBOW)]:
                    l = lm[idx]
                    entry[name] = {
                        "x": l.x * width, "y": l.y * height,
                        "z": l.z, "visibility": l.visibility,
                    }

            frames_data.append(entry)
            frame_idx += 1

    cap.release()
    return frames_data, fps, frame_idx


def compute_wrist_velocity(frames_data, fps, side="right"):
    """Compute wrist velocity (pixels/sec) and find peak."""
    wrist_key = f"{side}_wrist"
    velocities = []

    for i in range(1, len(frames_data)):
        prev = frames_data[i - 1].get(wrist_key)
        curr = frames_data[i].get(wrist_key)

        if prev and curr and prev.get("visibility", 0) > 0.3 and curr.get("visibility", 0) > 0.3:
            dx = curr["x"] - prev["x"]
            dy = curr["y"] - prev["y"]
            vel_px = math.sqrt(dx * dx + dy * dy)
            vel_px_per_sec = vel_px * fps
            velocities.append({
                "frame": frames_data[i]["frame"],
                "time": round(frames_data[i]["time"], 3),
                "velocity_px_frame": round(vel_px, 1),
                "velocity_px_sec": round(vel_px_per_sec, 0),
                "visibility": round(curr["visibility"], 2),
            })

    return velocities


def estimate_arm_angle(frame_data, side="right"):
    """Compute angle between shoulder-elbow-wrist (arm extension)."""
    shoulder = frame_data.get(f"{side}_shoulder")
    elbow = frame_data.get(f"{side}_elbow")
    wrist = frame_data.get(f"{side}_wrist")

    if not all([shoulder, elbow, wrist]):
        return None
    if any(p.get("visibility", 0) < 0.3 for p in [shoulder, elbow, wrist]):
        return None

    v1 = (shoulder["x"] - elbow["x"], shoulder["y"] - elbow["y"])
    v2 = (wrist["x"] - elbow["x"], wrist["y"] - elbow["y"])

    dot = v1[0] * v2[0] + v1[1] * v2[1]
    mag1 = math.sqrt(v1[0]**2 + v1[1]**2)
    mag2 = math.sqrt(v2[0]**2 + v2[1]**2)

    if mag1 == 0 or mag2 == 0:
        return None

    cos_angle = max(-1, min(1, dot / (mag1 * mag2)))
    return math.degrees(math.acos(cos_angle))


def main():
    parser = argparse.ArgumentParser(description="MediaPipe wrist velocity analysis")
    parser.add_argument("--clip-dir", "-d", default=os.path.join(SCRIPT_DIR, "clips"))
    args = parser.parse_args()

    clips = sorted(glob.glob(os.path.join(args.clip_dir, "gt_delivery_*.mp4")))
    if not clips:
        print("No GT clips found.")
        return

    print(f"MediaPipe Pose wrist velocity analysis")
    print(f"Model: {MODEL_PATH}")
    print(f"Clips: {len(clips)}")
    print()

    all_results = {}

    for clip_path in clips:
        clip_name = os.path.basename(clip_path)
        print(f"--- {clip_name} ---")

        frames_data, fps, total_frames = analyze_clip(clip_path)
        print(f"  Frames: {total_frames}, FPS: {fps:.0f}")

        best_side = None
        best_peak = 0

        for side in ["right", "left"]:
            velocities = compute_wrist_velocity(frames_data, fps, side)

            if velocities:
                peak = max(velocities, key=lambda v: v["velocity_px_sec"])
                avg_vel = sum(v["velocity_px_sec"] for v in velocities) / len(velocities)

                print(f"  {side.capitalize()} wrist:")
                print(f"    Tracked: {len(velocities)}/{total_frames} frames")
                print(f"    Peak: {peak['velocity_px_sec']:.0f} px/s at {peak['time']:.2f}s (frame {peak['frame']})")
                print(f"    Average: {avg_vel:.0f} px/s")

                if peak["velocity_px_sec"] > best_peak:
                    best_peak = peak["velocity_px_sec"]
                    best_side = side

                # Profile around peak
                peak_frame = peak["frame"]
                nearby = [v for v in velocities if abs(v["frame"] - peak_frame) <= 5]
                profile = [(v["frame"], f"{v['velocity_px_sec']:.0f}") for v in nearby]
                print(f"    Profile: {profile}")
            else:
                print(f"  {side.capitalize()} wrist: insufficient visibility")

        # Arm angles
        angles = []
        for fd in frames_data:
            for side in ["right", "left"]:
                angle = estimate_arm_angle(fd, side)
                if angle is not None:
                    angles.append({"frame": fd["frame"], "time": round(fd["time"], 3),
                                   "side": side, "angle": round(angle, 1)})

        if angles:
            most_extended = max(angles, key=lambda a: a["angle"])
            print(f"  Most extended: {most_extended['side']} arm at frame {most_extended['frame']} "
                  f"({most_extended['time']:.2f}s), angle={most_extended['angle']:.0f}deg")

        if best_side:
            print(f"  Bowling arm: likely {best_side} (highest peak velocity)")

        all_results[clip_name] = {
            "total_frames": total_frames,
            "fps": fps,
            "bowling_arm": best_side,
            "peak_wrist_velocity_px_sec": best_peak,
            "right_velocities": compute_wrist_velocity(frames_data, fps, "right"),
            "left_velocities": compute_wrist_velocity(frames_data, fps, "left"),
        }
        print()

    # Save
    result_path = os.path.join(SCRIPT_DIR, "result_speed_mediapipe.json")
    with open(result_path, "w") as f:
        json.dump({"model": MODEL_PATH, "results": all_results}, f, indent=2)
    print(f"Saved: {result_path}")


if __name__ == "__main__":
    main()
