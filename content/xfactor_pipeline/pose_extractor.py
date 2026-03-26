"""Stage 3: MediaPipe pose extraction — 33 landmarks per frame."""
from __future__ import annotations

import json
import sys
import urllib.request
from pathlib import Path

import cv2
import mediapipe as mp
import numpy as np

OUTPUT_DIR = Path(__file__).resolve().parent / "output"
FRAMES_DIR = OUTPUT_DIR / "frames"
PLAN_FILE = OUTPUT_DIR / "flash_plan.json"
POSE_FILE = OUTPUT_DIR / "pose_data.json"
MODEL_PATH = Path(__file__).resolve().parent / "pose_landmarker_heavy.task"
MODEL_URL = "https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_heavy/float16/latest/pose_landmarker_heavy.task"


def ensure_model():
    if not MODEL_PATH.exists():
        print(f"  Downloading pose model...")
        urllib.request.urlretrieve(MODEL_URL, MODEL_PATH)
        print(f"  Model saved: {MODEL_PATH.name}")


def run() -> list[dict]:
    ensure_model()

    # Load flash plan for ROI
    plan = {}
    if PLAN_FILE.exists():
        plan = json.loads(PLAN_FILE.read_text())

    roi = plan.get("bowler_roi", {"x1": 0.0, "y1": 0.0, "x2": 1.0, "y2": 1.0})

    frames = sorted(FRAMES_DIR.glob("frame_*.jpg"))
    if not frames:
        raise FileNotFoundError(f"No frames found in {FRAMES_DIR}")

    # Set up PoseLandmarker with tasks API
    BaseOptions = mp.tasks.BaseOptions
    PoseLandmarker = mp.tasks.vision.PoseLandmarker
    PoseLandmarkerOptions = mp.tasks.vision.PoseLandmarkerOptions

    options = PoseLandmarkerOptions(
        base_options=BaseOptions(model_asset_path=str(MODEL_PATH)),
        num_poses=1,
        min_pose_detection_confidence=0.5,
        min_tracking_confidence=0.5,
    )

    all_landmarks = []
    detected_count = 0

    with PoseLandmarker.create_from_options(options) as landmarker:
        for frame_path in frames:
            img = cv2.imread(str(frame_path))
            h, w = img.shape[:2]

            # Crop to ROI
            x1 = int(roi["x1"] * w)
            y1 = int(roi["y1"] * h)
            x2 = int(roi["x2"] * w)
            y2 = int(roi["y2"] * h)
            cropped = img[y1:y2, x1:x2]

            # Convert to RGB for MediaPipe
            rgb = cv2.cvtColor(cropped, cv2.COLOR_BGR2RGB)
            mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)

            result = landmarker.detect(mp_image)

            frame_data = {
                "frame": frame_path.name,
                "landmarks": None,
                "roi": {"x1": roi["x1"], "y1": roi["y1"], "x2": roi["x2"], "y2": roi["y2"]},
            }

            if result.pose_landmarks and len(result.pose_landmarks) > 0:
                detected_count += 1
                ch, cw = cropped.shape[:2]
                lms = []
                for lm in result.pose_landmarks[0]:
                    # Convert back to full-frame coordinates
                    abs_x = (lm.x * cw + x1) / w
                    abs_y = (lm.y * ch + y1) / h
                    lms.append({
                        "x": round(abs_x, 5),
                        "y": round(abs_y, 5),
                        "z": round(lm.z, 5),
                        "visibility": round(lm.visibility, 3),
                    })
                frame_data["landmarks"] = lms

            all_landmarks.append(frame_data)

    print(f"  Pose detected in {detected_count}/{len(frames)} frames")

    with open(POSE_FILE, "w") as f:
        json.dump(all_landmarks, f, indent=2)

    return all_landmarks


if __name__ == "__main__":
    result = run()
    detected = sum(1 for f in result if f["landmarks"] is not None)
    print(f"Detected: {detected}/{len(result)} frames")
    if result and result[0]["landmarks"]:
        lm = result[0]["landmarks"]
        print(f"Landmarks per frame: {len(lm)}")
        print(f"  L-hip(23): x={lm[23]['x']:.3f} y={lm[23]['y']:.3f}")
        print(f"  R-hip(24): x={lm[24]['x']:.3f} y={lm[24]['y']:.3f}")
        print(f"  L-shldr(11): x={lm[11]['x']:.3f} y={lm[11]['y']:.3f}")
        print(f"  R-shldr(12): x={lm[12]['x']:.3f} y={lm[12]['y']:.3f}")
