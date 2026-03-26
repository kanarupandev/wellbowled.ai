"""Pose extraction with bowler isolation via IoU-based tracking.

Runs MediaPipe PoseLandmarker on every frame, optionally cropped to a
Gemini-Flash-provided ROI. Multi-pose detection + scoring ensures we lock
onto the bowler and reject background people.
"""
from __future__ import annotations

from pathlib import Path

import cv2
import mediapipe as mp
import numpy as np

REPO_ROOT = Path(__file__).resolve().parents[2]
MODEL_PATH = REPO_ROOT / "resources" / "pose_landmarker_heavy.task"

# Upper-body + lower-body joints we track
PRIMARY_JOINTS = [11, 12, 13, 14, 15, 16, 23, 24, 25, 26, 27, 28]

LEFT_SHOULDER = 11
RIGHT_SHOULDER = 12
LEFT_HIP = 23
RIGHT_HIP = 24


# ---------------------------------------------------------------------------
# Bowler tracking helpers
# ---------------------------------------------------------------------------
def _bbox_from_pts(pts: list[tuple[float, float, float]]) -> dict | None:
    """Bounding box + center from visible primary joints."""
    xs = [pts[i][0] for i in PRIMARY_JOINTS if pts[i][2] > 0.3]
    ys = [pts[i][1] for i in PRIMARY_JOINTS if pts[i][2] > 0.3]
    if len(xs) < 6:
        return None
    x1, x2 = min(xs), max(xs)
    y1, y2 = min(ys), max(ys)
    return {
        "x1": x1, "y1": y1, "x2": x2, "y2": y2,
        "cx": (x1 + x2) / 2, "cy": (y1 + y2) / 2,
        "area": (x2 - x1) * (y2 - y1),
    }


def _iou(a: dict, b: dict) -> float:
    ix1 = max(a["x1"], b["x1"])
    iy1 = max(a["y1"], b["y1"])
    ix2 = min(a["x2"], b["x2"])
    iy2 = min(a["y2"], b["y2"])
    inter = max(0, ix2 - ix1) * max(0, iy2 - iy1)
    union = a["area"] + b["area"] - inter
    return inter / max(1e-6, union)


def _score_candidate(
    pts: list[tuple[float, float, float]],
    prev_bbox: dict | None,
    bowler_size: float | None,
) -> float:
    """Score a pose candidate. Lock to the bowler, reject background people."""
    bbox = _bbox_from_pts(pts)
    if bbox is None:
        return -1.0

    vis = sum(pts[i][2] for i in PRIMARY_JOINTS) / len(PRIMARY_JOINTS)

    if prev_bbox is None:
        # First detection: prefer largest person (bowler closest to camera)
        return bbox["area"] * 5.0 + vis * 1.0

    dist = ((bbox["cx"] - prev_bbox["cx"]) ** 2 +
            (bbox["cy"] - prev_bbox["cy"]) ** 2) ** 0.5
    iou = _iou(bbox, prev_bbox)

    # Reject if center jumped > 50% of frame
    if dist > 0.50:
        return -1.0

    # Reject if candidate is much smaller than established bowler
    if bowler_size is not None and bbox["area"] < bowler_size * 0.3:
        return -1.0

    return iou * 12.0 + max(0, 3.0 - dist * 6.0) + vis * 0.5 + bbox["area"] * 1.0


# ---------------------------------------------------------------------------
# Main extraction
# ---------------------------------------------------------------------------
def extract_poses(video_path: str, bowler_roi: dict | None = None) -> dict:
    """Extract per-frame pose landmarks from the primary bowler.

    Args:
        video_path: path to video file.
        bowler_roi: optional dict with x, y, w, h (normalized 0-1) from Flash.

    Returns dict with:
        frames: list of per-frame dicts (index, time, landmarks, frame_bgr)
        fps: float
        width, height: int
    """
    if not MODEL_PATH.exists():
        raise FileNotFoundError(
            f"Pose model not found at {MODEL_PATH}. "
            "Download pose_landmarker_heavy.task to resources/."
        )

    cap = cv2.VideoCapture(video_path)
    fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
    width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))

    PoseLandmarker = mp.tasks.vision.PoseLandmarker
    PoseLandmarkerOptions = mp.tasks.vision.PoseLandmarkerOptions
    BaseOptions = mp.tasks.BaseOptions

    options = PoseLandmarkerOptions(
        base_options=BaseOptions(model_asset_path=str(MODEL_PATH)),
        running_mode=mp.tasks.vision.RunningMode.IMAGE,
        num_poses=4,                       # detect multiple, pick best
        min_pose_detection_confidence=0.4,
        min_tracking_confidence=0.4,
    )

    frames: list[dict] = []
    prev_bbox: dict | None = None
    bowler_size: float | None = None

    with PoseLandmarker.create_from_options(options) as landmarker:
        idx = 0
        while True:
            ok, frame_bgr = cap.read()
            if not ok:
                break
            time_s = idx / fps

            # Crop to bowler ROI if available
            if bowler_roi:
                rx = max(0, int(bowler_roi["x"] * width))
                ry = max(0, int(bowler_roi["y"] * height))
                rw = min(width - rx, int(bowler_roi["w"] * width))
                rh = min(height - ry, int(bowler_roi["h"] * height))
                crop_bgr = frame_bgr[ry:ry + rh, rx:rx + rw]
                rgb = cv2.cvtColor(crop_bgr, cv2.COLOR_BGR2RGB)
            else:
                rx, ry, rw, rh = 0, 0, width, height
                rgb = cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2RGB)

            result = landmarker.detect(
                mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb),
            )

            chosen_pts = None
            if result.pose_landmarks:
                best_score = -1.0
                for pose in result.pose_landmarks:
                    pts = []
                    for p in pose:
                        # Remap crop-space (0-1) to full-frame space
                        fx = (rx + p.x * rw) / width
                        fy = (ry + p.y * rh) / height
                        pts.append((fx, fy, p.visibility))
                    s = _score_candidate(pts, prev_bbox, bowler_size)
                    if s > best_score:
                        best_score = s
                        chosen_pts = pts

            if chosen_pts is not None:
                bbox = _bbox_from_pts(chosen_pts)
                if bbox is not None:
                    prev_bbox = bbox
                    if bowler_size is None:
                        bowler_size = bbox["area"]
                    else:
                        bowler_size = bowler_size * 0.85 + bbox["area"] * 0.15

            frames.append({
                "index": idx,
                "time": round(time_s, 4),
                "landmarks": chosen_pts,
                "frame_bgr": frame_bgr,
            })
            idx += 1

    cap.release()
    print(f"       [pose] {idx} frames, "
          f"{sum(1 for f in frames if f['landmarks'] is not None)} with detections")
    return {"frames": frames, "fps": fps, "width": width, "height": height}
