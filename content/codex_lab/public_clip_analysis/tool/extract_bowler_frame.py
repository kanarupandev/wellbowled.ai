from __future__ import annotations

import argparse
import json
from pathlib import Path

import cv2
import mediapipe as mp
import numpy as np
from PIL import Image, ImageDraw

POSE_CONNECTIONS = [
    (11, 12),
    (11, 13), (13, 15),
    (12, 14), (14, 16),
    (11, 23), (12, 24),
    (23, 24),
    (23, 25), (25, 27),
    (24, 26), (26, 28),
]
PRIMARY_JOINTS = [11, 12, 13, 14, 15, 16, 23, 24, 25, 26, 27, 28]
HEAD_JOINTS = [0, 2, 5, 7, 8]


def repo_root() -> Path:
    return Path(__file__).resolve().parents[4]


def load_config(path: str) -> dict:
    with open(path) as f:
        return json.load(f)


def segment_path_for_config(config: dict) -> Path:
    return Path(config["output_dir"]) / "segment.mp4"


def read_frame(video_path: str, timestamp_s: float) -> tuple[np.ndarray, float]:
    cap = cv2.VideoCapture(video_path)
    fps = cap.get(cv2.CAP_PROP_FPS)
    frame_idx = int(timestamp_s * fps)
    cap.set(cv2.CAP_PROP_POS_FRAMES, frame_idx)
    ok, frame = cap.read()
    cap.release()
    if not ok:
        raise RuntimeError(f"Could not read frame at {timestamp_s}s from {video_path}")
    return frame, fps


def expand_bbox(bbox: dict, padding: float = 0.12) -> dict:
    x = max(0.0, float(bbox["x"]) - padding)
    y = max(0.0, float(bbox["y"]) - padding)
    x2 = min(1.0, float(bbox["x"]) + float(bbox["w"]) + padding)
    y2 = min(1.0, float(bbox["y"]) + float(bbox["h"]) + padding)
    return {"x": x, "y": y, "w": x2 - x, "h": y2 - y}


def to_px(box: dict, width: int, height: int) -> tuple[int, int, int, int]:
    x = max(0, min(width - 1, int(box["x"] * width)))
    y = max(0, min(height - 1, int(box["y"] * height)))
    w = max(1, int(box["w"] * width))
    h = max(1, int(box["h"] * height))
    return x, y, w, h


def crop_from_box(frame: np.ndarray, box: dict) -> tuple[np.ndarray, tuple[int, int, int, int]]:
    h, w = frame.shape[:2]
    x, y, cw, ch = to_px(box, w, h)
    return frame[y:y + ch, x:x + cw].copy(), (x, y, cw, ch)


def run_grabcut(frame: np.ndarray, crop_rect_px: tuple[int, int, int, int], subject_box_px: tuple[int, int, int, int], body_part_points: dict, ignore_regions: list[dict], pose_points=None) -> np.ndarray:
    crop_x, crop_y, crop_w, crop_h = crop_rect_px
    crop = frame[crop_y:crop_y + crop_h, crop_x:crop_x + crop_w].copy()
    mask = np.full(crop.shape[:2], cv2.GC_PR_BGD, dtype=np.uint8)

    sx, sy, sw, sh = subject_box_px
    local_rect = (
        max(1, sx - crop_x),
        max(1, sy - crop_y),
        max(1, min(sw, crop_w - 2)),
        max(1, min(sh, crop_h - 2)),
    )
    border = max(8, min(crop_w, crop_h) // 18)
    mask[:border, :] = cv2.GC_BGD
    mask[-border:, :] = cv2.GC_BGD
    mask[:, :border] = cv2.GC_BGD
    mask[:, -border:] = cv2.GC_BGD
    mask[local_rect[1]:local_rect[1] + local_rect[3], local_rect[0]:local_rect[0] + local_rect[2]] = cv2.GC_PR_FGD

    for point in body_part_points.values():
        if not isinstance(point, dict):
            continue
        px = int(point["x"] * frame.shape[1]) - crop_x
        py = int(point["y"] * frame.shape[0]) - crop_y
        if 0 <= px < crop_w and 0 <= py < crop_h:
            cv2.circle(mask, (px, py), 12, cv2.GC_FGD, -1)

    if pose_points:
        for idx in PRIMARY_JOINTS:
            p = pose_points[idx]
            if p[2] < 0.3:
                continue
            px = int(p[0] * frame.shape[1]) - crop_x
            py = int(p[1] * frame.shape[0]) - crop_y
            if 0 <= px < crop_w and 0 <= py < crop_h:
                cv2.circle(mask, (px, py), 10, cv2.GC_FGD, -1)
        for a, b in POSE_CONNECTIONS:
            pa = pose_points[a]
            pb = pose_points[b]
            if pa[2] < 0.3 or pb[2] < 0.3:
                continue
            ax = int(pa[0] * frame.shape[1]) - crop_x
            ay = int(pa[1] * frame.shape[0]) - crop_y
            bx = int(pb[0] * frame.shape[1]) - crop_x
            by = int(pb[1] * frame.shape[0]) - crop_y
            cv2.line(mask, (ax, ay), (bx, by), cv2.GC_FGD, 8)

    for region in ignore_regions:
        rx = int(region["x"] * frame.shape[1]) - crop_x
        ry = int(region["y"] * frame.shape[0]) - crop_y
        rw = max(1, int(region["w"] * frame.shape[1]))
        rh = max(1, int(region["h"] * frame.shape[0]))
        x1 = max(0, rx)
        y1 = max(0, ry)
        x2 = min(crop_w, rx + rw)
        y2 = min(crop_h, ry + rh)
        if x2 > x1 and y2 > y1:
            mask[y1:y2, x1:x2] = cv2.GC_BGD

    bgd_model = np.zeros((1, 65), np.float64)
    fgd_model = np.zeros((1, 65), np.float64)
    cv2.grabCut(crop, mask, local_rect, bgd_model, fgd_model, 5, cv2.GC_INIT_WITH_MASK)
    foreground = np.where((mask == cv2.GC_FGD) | (mask == cv2.GC_PR_FGD), 255, 0).astype("uint8")
    return foreground


def build_pose_support_mask(mask_shape: tuple[int, int], pose_points, frame_shape: tuple[int, int], crop_rect_px: tuple[int, int, int, int]) -> np.ndarray:
    crop_x, crop_y, crop_w, crop_h = crop_rect_px
    frame_h, frame_w = frame_shape
    support = np.zeros(mask_shape, dtype=np.uint8)

    def local_point(idx: int):
        p = pose_points[idx]
        if p[2] < 0.25:
            return None
        px = int(p[0] * frame_w) - crop_x
        py = int(p[1] * frame_h) - crop_y
        if not (0 <= px < crop_w and 0 <= py < crop_h):
            return None
        return px, py

    support_points = []
    for idx in PRIMARY_JOINTS + HEAD_JOINTS:
        pt = local_point(idx)
        if pt is None:
            continue
        radius = 12 if idx in HEAD_JOINTS else 16
        cv2.circle(support, pt, radius, 255, -1)
        support_points.append(pt)

    head_links = [(0, 11), (0, 12), (2, 11), (5, 12)]
    for a, b in POSE_CONNECTIONS + head_links:
        pa = local_point(a)
        pb = local_point(b)
        if pa is None or pb is None:
            continue
        cv2.line(support, pa, pb, 255, 16)

    torso_ids = [11, 12, 24, 23]
    torso_points = [local_point(idx) for idx in torso_ids]
    if all(pt is not None for pt in torso_points):
        cv2.fillConvexPoly(support, np.array(torso_points, dtype=np.int32), 255)

    support = cv2.dilate(support, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (23, 23)), iterations=1)
    return support


def clean_mask(mask: np.ndarray, pose_points=None, frame_shape: tuple[int, int] | None = None, crop_rect_px: tuple[int, int, int, int] | None = None) -> np.ndarray:
    kernel = np.ones((5, 5), np.uint8)
    cleaned = cv2.morphologyEx(mask, cv2.MORPH_OPEN, kernel)
    cleaned = cv2.morphologyEx(cleaned, cv2.MORPH_CLOSE, kernel)

    support = None
    if pose_points is not None and frame_shape is not None and crop_rect_px is not None:
        support = build_pose_support_mask(cleaned.shape, pose_points, frame_shape, crop_rect_px)
        num_labels, labels, _, _ = cv2.connectedComponentsWithStats((cleaned > 0).astype(np.uint8), connectivity=8)
        keep = []
        for label_idx in range(1, num_labels):
            region = (labels == label_idx)
            if np.any(region & (support > 0)):
                keep.append(label_idx)
        if keep:
            cleaned = np.where(np.isin(labels, keep), 255, 0).astype(np.uint8)
            cleaned = cv2.bitwise_and(cleaned, support)

    num_labels, labels, stats, _ = cv2.connectedComponentsWithStats((cleaned > 0).astype(np.uint8), connectivity=8)
    if num_labels > 1:
        largest = 1 + np.argmax(stats[1:, cv2.CC_STAT_AREA])
        cleaned = np.where(labels == largest, 255, 0).astype(np.uint8)

    cleaned = cv2.morphologyEx(cleaned, cv2.MORPH_CLOSE, np.ones((7, 7), np.uint8))
    if support is not None:
        cleaned = cv2.dilate(cleaned, np.ones((3, 3), np.uint8), iterations=1)
        cleaned = cv2.bitwise_and(cleaned, support)
    cleaned = cv2.GaussianBlur(cleaned, (5, 5), 0)
    return cleaned


def save_cutout(crop: np.ndarray, mask: np.ndarray, output_path: str):
    rgba = cv2.cvtColor(crop, cv2.COLOR_BGR2RGBA)
    rgba[:, :, 3] = mask
    Image.fromarray(rgba).save(output_path)


def detect_pose(crop_rgb: np.ndarray):
    PoseLandmarker = mp.tasks.vision.PoseLandmarker
    PoseLandmarkerOptions = mp.tasks.vision.PoseLandmarkerOptions
    BaseOptions = mp.tasks.BaseOptions
    RunningMode = mp.tasks.vision.RunningMode

    options = PoseLandmarkerOptions(
        base_options=BaseOptions(model_asset_path=str(repo_root() / "resources/pose_landmarker_heavy.task")),
        running_mode=RunningMode.IMAGE,
        num_poses=1,
        min_pose_detection_confidence=0.5,
        min_tracking_confidence=0.5,
    )
    with PoseLandmarker.create_from_options(options) as landmarker:
        image = mp.Image(image_format=mp.ImageFormat.SRGB, data=crop_rgb)
        res = landmarker.detect(image)
    if not res.pose_landmarks:
        return None
    return [(p.x, p.y, p.visibility) for p in res.pose_landmarks[0]]


def detect_best_pose_bbox(frame_bgr: np.ndarray) -> dict | None:
    PoseLandmarker = mp.tasks.vision.PoseLandmarker
    PoseLandmarkerOptions = mp.tasks.vision.PoseLandmarkerOptions
    BaseOptions = mp.tasks.BaseOptions
    RunningMode = mp.tasks.vision.RunningMode

    options = PoseLandmarkerOptions(
        base_options=BaseOptions(model_asset_path=str(repo_root() / "resources/pose_landmarker_heavy.task")),
        running_mode=RunningMode.IMAGE,
        num_poses=4,
        min_pose_detection_confidence=0.4,
        min_tracking_confidence=0.4,
    )

    rgb = cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2RGB)
    with PoseLandmarker.create_from_options(options) as landmarker:
        res = landmarker.detect(mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb))
    if not res.pose_landmarks:
        return None

    best = None
    best_score = None
    for pose in res.pose_landmarks:
        pts = [(p.x, p.y, p.visibility) for p in pose]
        xs = [pts[idx][0] for idx in PRIMARY_JOINTS if pts[idx][2] > 0.3]
        ys = [pts[idx][1] for idx in PRIMARY_JOINTS if pts[idx][2] > 0.3]
        if len(xs) < 4 or len(ys) < 4:
            continue
        x1, x2 = max(0.0, min(xs)), min(1.0, max(xs))
        y1, y2 = max(0.0, min(ys)), min(1.0, max(ys))
        area = (x2 - x1) * (y2 - y1)
        cy = (y1 + y2) / 2
        visibility = sum(pts[idx][2] for idx in PRIMARY_JOINTS) / len(PRIMARY_JOINTS)
        score = area * 2.0 + cy * 0.8 + visibility * 0.4
        if best_score is None or score > best_score:
            best_score = score
            best = {
                "bbox": {"x": x1, "y": y1, "w": x2 - x1, "h": y2 - y1},
                "points": pts,
            }
    return best


def draw_pose_only(size: tuple[int, int], points, output_path: str):
    width, height = size
    image = Image.new("RGBA", size, (10, 14, 20, 255))
    draw = ImageDraw.Draw(image)
    accent = (75, 224, 255, 255)
    accent_secondary = (255, 186, 64, 255)
    for a, b in POSE_CONNECTIONS:
        pa = points[a]
        pb = points[b]
        xa, ya = pa[0] * width, pa[1] * height
        xb, yb = pb[0] * width, pb[1] * height
        draw.line((xa, ya, xb, yb), fill=accent, width=6)
    for idx in PRIMARY_JOINTS:
        p = points[idx]
        x, y = p[0] * width, p[1] * height
        draw.ellipse((x - 5, y - 5, x + 5, y + 5), fill=accent_secondary)
    image.save(output_path)


def extract_phase_assets(config_path: str, phase: str):
    config = load_config(config_path)
    flash_analysis = config.get("flash_analysis") or {}
    output_dir = Path(config["output_dir"])
    output_dir.mkdir(parents=True, exist_ok=True)

    phase_frames = flash_analysis.get("phase_frames", {})
    frame_id = phase_frames.get(f"{phase}_frame")
    if not frame_id:
        raise RuntimeError(f"No frame id for phase={phase}")

    frame_analysis = next(
        (entry for entry in flash_analysis.get("frame_analysis", []) if entry.get("frame_id") == frame_id),
        None,
    )
    if not frame_analysis or not frame_analysis.get("primary_subject_bbox"):
        raise RuntimeError(f"No subject bbox for frame {frame_id}")

    video_path = segment_path_for_config(config)
    if not video_path.exists():
        raise RuntimeError(f"Missing segment video: {video_path}")

    frame, _ = read_frame(str(video_path), float(frame_analysis["timestamp_s"]))
    subject_box = frame_analysis["primary_subject_bbox"]
    pose_points = None
    pose_box = detect_best_pose_bbox(frame)
    if pose_box is not None:
        subject_box = pose_box["bbox"]
        pose_points = pose_box["points"]
    crop_box = expand_bbox(subject_box, padding=min(float(flash_analysis.get("subject_strategy", {}).get("frame_crop_padding", 0.1)), 0.045))
    crop, crop_rect_px = crop_from_box(frame, crop_box)
    h, w = frame.shape[:2]
    subject_box_px = to_px(subject_box, w, h)
    mask = run_grabcut(
        frame,
        crop_rect_px,
        subject_box_px,
        frame_analysis.get("body_part_points", {}),
        frame_analysis.get("ignore_regions", []),
        pose_points=pose_points,
    )

    mask = clean_mask(mask, pose_points=pose["points"], frame_shape=frame.shape[:2], crop_rect_px=crop_rect)

    cutout_path = output_dir / f"{phase}_bowler_cutout.png"
    save_cutout(crop, mask, str(cutout_path))

    pose_only_path = output_dir / f"{phase}_pose_only.png"
    crop_rgb = cv2.cvtColor(crop, cv2.COLOR_BGR2RGB)
    pose_points = detect_pose(crop_rgb)
    if pose_points is None:
        fallback = Image.new("RGBA", (crop.shape[1], crop.shape[0]), (10, 14, 20, 255))
        fallback.save(pose_only_path)
    else:
        draw_pose_only((crop.shape[1], crop.shape[0]), pose_points, str(pose_only_path))

    debug_path = output_dir / f"{phase}_subject_crop.jpg"
    Image.fromarray(cv2.cvtColor(crop, cv2.COLOR_BGR2RGB)).save(debug_path, quality=95)

    print(json.dumps({
        "phase": phase,
        "frame_id": frame_id,
        "timestamp_s": frame_analysis["timestamp_s"],
        "subject_crop": str(debug_path),
        "bowler_cutout": str(cutout_path),
        "pose_only": str(pose_only_path),
    }, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Extract a bowler-only frame asset from Flash-planned boxes.")
    parser.add_argument("config", help="Path to config JSON with flash_analysis")
    parser.add_argument("--phase", default="release", choices=["load", "release", "freeze", "finish"])
    args = parser.parse_args()
    extract_phase_assets(args.config, args.phase)
