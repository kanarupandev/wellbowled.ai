from __future__ import annotations

import argparse
import json
import math
from pathlib import Path

import cv2
import mediapipe as mp
import numpy as np
from PIL import Image, ImageDraw, ImageFont

from extract_bowler_frame import (
    PRIMARY_JOINTS,
    POSE_CONNECTIONS,
    clean_mask,
    expand_bbox,
    load_config,
    run_grabcut,
    segment_path_for_config,
    to_px,
)


def repo_root() -> Path:
    return Path(__file__).resolve().parents[4]


def load_font(size: int, bold: bool = False):
    candidates = []
    if bold:
        candidates.extend([
            "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
            "/System/Library/Fonts/Supplemental/Helvetica.ttc",
        ])
    else:
        candidates.extend([
            "/System/Library/Fonts/Supplemental/Arial.ttf",
            "/System/Library/Fonts/Supplemental/Helvetica.ttc",
        ])
    for candidate in candidates:
        path = Path(candidate)
        if path.exists():
            try:
                return ImageFont.truetype(str(path), size=size)
            except OSError:
                pass
    return ImageFont.load_default()


def nearest_flash_entry(flash_analysis: dict, time_s: float, max_delta: float = 0.5) -> dict | None:
    entries = []
    for entry in flash_analysis.get("frame_analysis", []):
        if not isinstance(entry, dict):
            continue
        bbox = entry.get("primary_subject_bbox")
        ts = entry.get("timestamp_s")
        if bbox and ts is not None:
            entries.append(entry)
    if not entries:
        return None
    best = min(entries, key=lambda e: abs(float(e["timestamp_s"]) - time_s))
    if abs(float(best["timestamp_s"]) - time_s) > max_delta:
        return None
    return best


def bbox_iou(a: dict, b: dict) -> float:
    ax1, ay1 = float(a["x"]), float(a["y"])
    ax2, ay2 = ax1 + float(a["w"]), ay1 + float(a["h"])
    bx1, by1 = float(b["x"]), float(b["y"])
    bx2, by2 = bx1 + float(b["w"]), by1 + float(b["h"])
    ix1, iy1 = max(ax1, bx1), max(ay1, by1)
    ix2, iy2 = min(ax2, bx2), min(ay2, by2)
    iw, ih = max(0.0, ix2 - ix1), max(0.0, iy2 - iy1)
    inter = iw * ih
    if inter <= 0:
        return 0.0
    area_a = (ax2 - ax1) * (ay2 - ay1)
    area_b = (bx2 - bx1) * (by2 - by1)
    return inter / max(1e-6, area_a + area_b - inter)


def center_distance(a: dict, b: dict) -> float:
    ax = float(a["x"]) + float(a["w"]) / 2
    ay = float(a["y"]) + float(a["h"]) / 2
    bx = float(b["x"]) + float(b["w"]) / 2
    by = float(b["y"]) + float(b["h"]) / 2
    return math.hypot(ax - bx, ay - by)


def detect_pose_candidates(landmarker, frame_bgr: np.ndarray) -> list[dict]:
    rgb = cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2RGB)
    res = landmarker.detect(mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb))
    candidates = []
    for pose in res.pose_landmarks or []:
        pts = [(p.x, p.y, p.visibility) for p in pose]
        xs = [pts[idx][0] for idx in PRIMARY_JOINTS if pts[idx][2] > 0.3]
        ys = [pts[idx][1] for idx in PRIMARY_JOINTS if pts[idx][2] > 0.3]
        if len(xs) < 5 or len(ys) < 5:
            continue
        bbox = {
            "x": max(0.0, min(xs)),
            "y": max(0.0, min(ys)),
            "w": min(1.0, max(xs)) - max(0.0, min(xs)),
            "h": min(1.0, max(ys)) - max(0.0, min(ys)),
        }
        area = bbox["w"] * bbox["h"]
        cy = bbox["y"] + bbox["h"] / 2
        vis = sum(pts[idx][2] for idx in PRIMARY_JOINTS) / len(PRIMARY_JOINTS)
        candidates.append({
            "bbox": bbox,
            "points": pts,
            "area": area,
            "center_y": cy,
            "visibility": vis,
        })
    return candidates


def choose_bowler_candidate(candidates: list[dict], prev_bbox: dict | None, flash_entry: dict | None, global_crop: dict | None) -> dict | None:
    if not candidates:
        return None
    flash_bbox = flash_entry.get("primary_subject_bbox") if flash_entry else None
    best = None
    best_score = None
    for cand in candidates:
        bbox = cand["bbox"]
        score = cand["area"] * 2.2 + cand["center_y"] * 0.9 + cand["visibility"] * 0.5
        if global_crop:
            gy = float(global_crop.get("y", 0.0))
            if bbox["y"] + bbox["h"] / 2 < gy:
                score -= 1.0
        if prev_bbox:
            score += bbox_iou(bbox, prev_bbox) * 3.0
            score += max(0.0, 1.0 - center_distance(bbox, prev_bbox) * 2.0)
        if flash_bbox:
            score += bbox_iou(bbox, flash_bbox) * 2.0
            score += max(0.0, 0.7 - center_distance(bbox, flash_bbox))
        if best_score is None or score > best_score:
            best_score = score
            best = cand
    return best


def compose_cutout_on_dark(frame: np.ndarray, crop_rect_px: tuple[int, int, int, int], mask: np.ndarray) -> np.ndarray:
    bg = np.zeros_like(frame)
    bg[:] = (20, 14, 10)
    x, y, w, h = crop_rect_px
    crop = frame[y:y + h, x:x + w].copy()
    alpha = (mask.astype(np.float32) / 255.0)[:, :, None]
    region = bg[y:y + h, x:x + w].astype(np.float32)
    composite = crop.astype(np.float32) * alpha + region * (1.0 - alpha)
    bg[y:y + h, x:x + w] = np.clip(composite, 0, 255).astype(np.uint8)
    return bg


def draw_pose_canvas(size: tuple[int, int], points) -> np.ndarray:
    width, height = size
    image = Image.new("RGB", size, (10, 14, 20))
    draw = ImageDraw.Draw(image)
    accent = (75, 224, 255)
    accent_secondary = (255, 186, 64)
    for a, b in POSE_CONNECTIONS:
        pa = points[a]
        pb = points[b]
        if pa[2] < 0.3 or pb[2] < 0.3:
            continue
        xa, ya = pa[0] * width, pa[1] * height
        xb, yb = pb[0] * width, pb[1] * height
        draw.line((xa, ya, xb, yb), fill=accent, width=6)
    for idx in PRIMARY_JOINTS:
        p = points[idx]
        if p[2] < 0.3:
            continue
        x, y = p[0] * width, p[1] * height
        draw.ellipse((x - 5, y - 5, x + 5, y + 5), fill=accent_secondary)
    return cv2.cvtColor(np.array(image), cv2.COLOR_RGB2BGR)


def angle_deg(a, b, c) -> int:
    ab = (a[0] - b[0], a[1] - b[1])
    cb = (c[0] - b[0], c[1] - b[1])
    mag_ab = math.hypot(*ab)
    mag_cb = math.hypot(*cb)
    if mag_ab == 0 or mag_cb == 0:
        return 0
    dot = ab[0] * cb[0] + ab[1] * cb[1]
    cos_theta = max(-1.0, min(1.0, dot / (mag_ab * mag_cb)))
    return int(round(math.degrees(math.acos(cos_theta))))


def choose_brace_leg(points) -> dict | None:
    legs = {
        "left": (23, 25, 27),
        "right": (24, 26, 28),
    }
    scored = []
    for side, triplet in legs.items():
        hip_idx, knee_idx, ankle_idx = triplet
        triplet_points = [points[idx] for idx in triplet]
        if any(p[2] < 0.25 for p in triplet_points):
            continue
        knee_angle = angle_deg(points[hip_idx], points[knee_idx], points[ankle_idx])
        ankle_y = points[ankle_idx][1]
        score = (knee_angle / 180.0) * 0.7 + ankle_y * 0.3
        scored.append((score, side, triplet, knee_angle))
    if not scored:
        return None
    scored.sort(reverse=True)
    _, side, brace_triplet, knee_angle = scored[0]
    trail_side = "right" if side == "left" else "left"
    return {
        "brace_side": side,
        "brace_triplet": brace_triplet,
        "trail_triplet": legs[trail_side],
        "brace_knee_angle": knee_angle,
    }


def draw_marker(draw: ImageDraw.ImageDraw, point_xy, color, label: str, font, dx: int, dy: int):
    x, y = point_xy
    draw.ellipse((x - 7, y - 7, x + 7, y + 7), fill=color)
    text_box = draw.textbbox((0, 0), label, font=font)
    box_w = max(112, text_box[2] - text_box[0] + 24)
    box_h = 30
    left = x + dx
    top = y + dy
    max_w, max_h = draw.im.size
    left = max(10, min(left, max_w - box_w - 10))
    top = max(10, min(top, max_h - box_h - 10))
    box = (left, top, left + box_w, top + box_h)
    draw.rounded_rectangle(box, radius=12, fill=(10, 14, 20, 220))
    draw.text((box[0] + 12, box[1] + 7), label, font=font, fill=(245, 247, 250, 255))


def overlay_brace_focus(frame: np.ndarray, points, time_s: float, phase_hints: dict) -> np.ndarray:
    if points is None:
        return frame
    release_t = float(phase_hints.get("release", 0.0))
    if time_s < release_t - 0.08 or time_s > release_t + 0.16:
        return frame

    brace = choose_brace_leg(points)
    if not brace:
        return frame

    image = Image.fromarray(cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)).convert("RGBA")
    draw = ImageDraw.Draw(image)
    width, height = image.size
    font_chip = load_font(16, bold=True)
    font_small = load_font(14, bold=False)

    accent_brace = (142, 242, 92, 255)
    accent_front = (75, 224, 255, 255)
    accent_trail = (255, 186, 64, 255)

    hip_idx, knee_idx, ankle_idx = brace["brace_triplet"]
    trail_ankle_idx = brace["trail_triplet"][2]

    hip = (points[hip_idx][0] * width, points[hip_idx][1] * height)
    knee = (points[knee_idx][0] * width, points[knee_idx][1] * height)
    ankle = (points[ankle_idx][0] * width, points[ankle_idx][1] * height)
    trail_ankle = (points[trail_ankle_idx][0] * width, points[trail_ankle_idx][1] * height)

    draw.line((hip[0], hip[1], knee[0], knee[1]), fill=accent_brace, width=7)
    draw.line((knee[0], knee[1], ankle[0], ankle[1]), fill=accent_brace, width=7)
    draw.line((ankle[0], ankle[1], trail_ankle[0], trail_ankle[1]), fill=(255, 255, 255, 95), width=2)

    draw_marker(draw, knee, accent_brace, "brace knee", font_small, 16, -16)
    draw_marker(draw, ankle, accent_front, "front ankle", font_small, 16, 10)
    draw_marker(draw, trail_ankle, accent_trail, "trail ankle", font_small, -124, -6)

    box = (24, height - 92, 170, height - 28)
    draw.rounded_rectangle(box, radius=18, fill=(10, 14, 20, 226), outline=accent_brace, width=2)
    draw.text((38, height - 82), "BRACE", font=font_chip, fill=(214, 220, 228, 255))
    draw.text((38, height - 58), f"{brace['brace_knee_angle']}deg", font=load_font(22, bold=True), fill=(248, 250, 252, 255))

    return cv2.cvtColor(np.array(image.convert("RGB")), cv2.COLOR_RGB2BGR)


def draw_tracking_debug(frame: np.ndarray, candidate: dict | None, label: str) -> Image.Image:
    image = Image.fromarray(cv2.cvtColor(frame, cv2.COLOR_BGR2RGB))
    draw = ImageDraw.Draw(image)
    font = load_font(20, bold=True)
    draw.rounded_rectangle((16, 16, 140, 52), radius=14, fill=(10, 14, 20))
    draw.text((28, 24), label, font=font, fill=(244, 247, 250))
    if candidate:
        h, w = frame.shape[:2]
        x, y, bw, bh = to_px(candidate["bbox"], w, h)
        draw.rounded_rectangle((x, y, x + bw, y + bh), radius=16, outline=(75, 224, 255), width=4)
    return image


def save_debug_sheet(images: list[tuple[str, Image.Image]], output_path: str):
    tile_w, tile_h = 240, 424
    gutter = 22
    width = len(images) * tile_w + (len(images) + 1) * gutter
    height = tile_h + 72
    canvas = Image.new("RGB", (width, height), (10, 14, 20))
    draw = ImageDraw.Draw(canvas)
    label_font = load_font(22, bold=True)
    for idx, (label, image) in enumerate(images):
        x = gutter + idx * (tile_w + gutter)
        y = gutter
        canvas.paste(image.resize((tile_w, tile_h)), (x, y))
        draw.text((x, tile_h + 34), label.upper(), font=label_font, fill=(232, 236, 242))
    canvas.save(output_path, quality=95)


def render_variants(config_path: str):
    config = load_config(config_path)
    flash_analysis = config.get("flash_analysis") or {}
    output_dir = Path(config["output_dir"])
    output_dir.mkdir(parents=True, exist_ok=True)
    segment_path = segment_path_for_config(config)

    cap = cv2.VideoCapture(str(segment_path))
    fps = cap.get(cv2.CAP_PROP_FPS)
    width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))

    figure_path = output_dir / "bowler_figure_only.mp4"
    pose_path = output_dir / "bowler_pose_only.mp4"
    brace_path = output_dir / "bowler_figure_brace.mp4"
    fourcc = cv2.VideoWriter_fourcc(*"mp4v")
    figure_writer = cv2.VideoWriter(str(figure_path), fourcc, fps, (width, height))
    pose_writer = cv2.VideoWriter(str(pose_path), fourcc, fps, (width, height))
    brace_writer = cv2.VideoWriter(str(brace_path), fourcc, fps, (width, height))

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

    prev_bbox = None
    global_crop = flash_analysis.get("subject_strategy", {}).get("global_bowler_crop")
    pad = float(flash_analysis.get("subject_strategy", {}).get("frame_crop_padding", 0.1) or 0.1)
    checkpoints = {
        "load": float(config["phase_hints"]["load"]),
        "release": float(config["phase_hints"]["release"]),
        "freeze": float(config["phase_hints"].get("freeze", config["phase_hints"]["release"])),
        "finish": float(config["phase_hints"]["finish"]),
    }
    debug_images = {}
    tracking_log = []

    with PoseLandmarker.create_from_options(options) as landmarker:
        frame_idx = 0
        while True:
            ok, frame = cap.read()
            if not ok:
                break
            time_s = frame_idx / fps
            flash_entry = nearest_flash_entry(flash_analysis, time_s)
            candidates = detect_pose_candidates(landmarker, frame)
            chosen = choose_bowler_candidate(candidates, prev_bbox, flash_entry, global_crop)

            figure_frame = np.zeros_like(frame)
            figure_frame[:] = (20, 14, 10)
            pose_frame = draw_pose_canvas((width, height), []) if False else np.zeros_like(frame)
            pose_frame[:] = (20, 14, 10)
            brace_frame = figure_frame.copy()

            if chosen is not None:
                bbox = chosen["bbox"]
                prev_bbox = bbox
                crop_box = expand_bbox(bbox, padding=min(pad, 0.045))
                crop_x, crop_y, crop_w, crop_h = to_px(crop_box, width, height)
                subject_box_px = to_px(bbox, width, height)
                mask = run_grabcut(
                    frame,
                    (crop_x, crop_y, crop_w, crop_h),
                    subject_box_px,
                    flash_entry.get("body_part_points", {}) if flash_entry else {},
                    flash_entry.get("ignore_regions", []) if flash_entry else [],
                    pose_points=chosen["points"],
                )
                mask = clean_mask(mask, pose_points=chosen["points"], frame_shape=frame.shape[:2], crop_rect_px=(crop_x, crop_y, crop_w, crop_h))
                figure_frame = compose_cutout_on_dark(frame, (crop_x, crop_y, crop_w, crop_h), mask)
                pose_frame = draw_pose_canvas((width, height), chosen["points"])
                brace_frame = overlay_brace_focus(figure_frame, chosen["points"], time_s, checkpoints)
                tracking_log.append({
                    "frame_index": frame_idx,
                    "time": round(time_s, 3),
                    "bbox": bbox,
                })
            else:
                tracking_log.append({
                    "frame_index": frame_idx,
                    "time": round(time_s, 3),
                    "bbox": None,
                })
                brace_frame = figure_frame.copy()

            for label, ts in checkpoints.items():
                if label not in debug_images and abs(time_s - ts) <= (1.0 / max(1.0, fps)):
                    debug_images[label] = draw_tracking_debug(frame, chosen, label)

            figure_writer.write(figure_frame)
            pose_writer.write(pose_frame)
            brace_writer.write(brace_frame)
            frame_idx += 1

    cap.release()
    figure_writer.release()
    pose_writer.release()
    brace_writer.release()

    ordered_debug = [(label, debug_images[label]) for label in ["load", "release", "freeze", "finish"] if label in debug_images]
    debug_sheet_path = output_dir / "bowler_tracking_debug_sheet.jpg"
    if ordered_debug:
        save_debug_sheet(ordered_debug, str(debug_sheet_path))

    tracking_log_path = output_dir / "bowler_tracking_log.json"
    with tracking_log_path.open("w") as f:
        json.dump({"frames": tracking_log}, f, indent=2)

    print(json.dumps({
        "figure_video": str(figure_path),
        "pose_video": str(pose_path),
        "brace_video": str(brace_path),
        "debug_sheet": str(debug_sheet_path),
        "tracking_log": str(tracking_log_path),
    }, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Render full-video bowler-only figure and pose variants.")
    parser.add_argument("config", help="Config path with flash_analysis")
    args = parser.parse_args()
    render_variants(args.config)
