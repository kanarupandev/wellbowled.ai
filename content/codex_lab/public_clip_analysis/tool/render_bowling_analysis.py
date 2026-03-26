from __future__ import annotations

import argparse
import base64
import json
import math
import os
from pathlib import Path
import urllib.request

import cv2
import mediapipe as mp
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

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
MODEL_NAME = "gemini-3-pro-preview"


def repo_root() -> Path:
    return Path(__file__).resolve().parents[4]


def load_api_key() -> str | None:
    env_key = os.environ.get("GEMINI_API_KEY")
    if env_key:
        return env_key
    env_path = repo_root() / ".env"
    if env_path.exists():
        for line in env_path.read_text().splitlines():
            if line.startswith("GEMINI_API_KEY="):
                return line.split("=", 1)[1].strip()
    return None


def load_font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    candidates = []
    if bold:
        candidates.extend([
            "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
            "/System/Library/Fonts/Supplemental/Helvetica.ttc",
            "/System/Library/Fonts/Supplemental/Arial.ttf",
        ])
    else:
        candidates.extend([
            "/System/Library/Fonts/Supplemental/Arial.ttf",
            "/System/Library/Fonts/Supplemental/Helvetica.ttc",
        ])
    for candidate in candidates:
        if os.path.exists(candidate):
            try:
                return ImageFont.truetype(candidate, size=size)
            except OSError:
                continue
    return ImageFont.load_default()


def wrap_text(draw: ImageDraw.ImageDraw, text: str, font, max_width: int) -> list[str]:
    words = text.split()
    if not words:
        return []
    lines = [words[0]]
    for word in words[1:]:
        trial = f"{lines[-1]} {word}"
        box = draw.textbbox((0, 0), trial, font=font)
        if box[2] - box[0] <= max_width:
            lines[-1] = trial
        else:
            lines.append(word)
    return lines


def rounded_panel(draw: ImageDraw.ImageDraw, box, fill, outline=None, width=1, radius=18):
    draw.rounded_rectangle(box, radius=radius, fill=fill, outline=outline, width=width)


def write_segment(input_video: str, start_s: float, end_s: float, output_video: str) -> dict:
    cap = cv2.VideoCapture(input_video)
    fps = cap.get(cv2.CAP_PROP_FPS)
    width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    start_frame = max(0, int(start_s * fps))
    end_frame = min(total - 1, int(end_s * fps))

    writer = cv2.VideoWriter(output_video, cv2.VideoWriter_fourcc(*"mp4v"), fps, (width, height))
    cap.set(cv2.CAP_PROP_POS_FRAMES, start_frame)

    count = 0
    for _ in range(start_frame, end_frame + 1):
        ok, frame = cap.read()
        if not ok:
            break
        writer.write(frame)
        count += 1

    cap.release()
    writer.release()
    return {"fps": fps, "width": width, "height": height, "frames": count}


def call_gemini(video_path: str, draft_path: str) -> dict | None:
    api_key = load_api_key()
    if not api_key:
        return None

    with open(video_path, "rb") as f:
        video_b64 = base64.b64encode(f.read()).decode("utf-8")

    prompt = (
        "Analyze this cricket bowling clip for a short-form coaching breakdown. "
        "Return strict JSON with keys: headline, primary_insight, coaching_takeaway, release_note, finish_note. "
        "Keep headline under 5 words, primary_insight under 16 words, coaching_takeaway under 12 words, "
        "release_note under 14 words, finish_note under 14 words. Focus on visible mechanics only."
    )

    payload = {
        "contents": [{"parts": [
            {"inlineData": {"mimeType": "video/mp4", "data": video_b64}},
            {"text": prompt}
        ]}],
        "generationConfig": {
            "temperature": 0.2,
            "responseMimeType": "application/json"
        }
    }

    url = f"https://generativelanguage.googleapis.com/v1beta/models/{MODEL_NAME}:generateContent?key={load_api_key()}"
    req = urllib.request.Request(url, data=json.dumps(payload).encode("utf-8"), headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=180) as resp:
        response = json.loads(resp.read().decode("utf-8"))

    text = response["candidates"][0]["content"]["parts"][0]["text"]
    draft = json.loads(text)
    with open(draft_path, "w") as f:
        json.dump({"draft": draft, "raw": response}, f, indent=2)
    return draft


def crop_region(frame: np.ndarray, crop_hint: dict | None) -> tuple[np.ndarray, tuple[float, float, float, float]]:
    if not crop_hint:
        return frame, (0.0, 0.0, 1.0, 1.0)
    height, width = frame.shape[:2]
    x0 = max(0, min(width - 1, int(crop_hint["x"] * width)))
    y0 = max(0, min(height - 1, int(crop_hint["y"] * height)))
    x1 = max(x0 + 1, min(width, int((crop_hint["x"] + crop_hint["w"]) * width)))
    y1 = max(y0 + 1, min(height, int((crop_hint["y"] + crop_hint["h"]) * height)))
    return frame[y0:y1, x0:x1], (x0 / width, y0 / height, (x1 - x0) / width, (y1 - y0) / height)


def crop_pil_image(image: Image.Image, crop_hint: dict | None) -> Image.Image:
    if not crop_hint:
        return image
    width, height = image.size
    x0 = max(0, min(width - 1, int(crop_hint["x"] * width)))
    y0 = max(0, min(height - 1, int(crop_hint["y"] * height)))
    x1 = max(x0 + 1, min(width, int((crop_hint["x"] + crop_hint["w"]) * width)))
    y1 = max(y0 + 1, min(height, int((crop_hint["y"] + crop_hint["h"]) * height)))
    return image.crop((x0, y0, x1, y1)).resize((width, height), Image.Resampling.LANCZOS)


def dynamic_crop_for_time(base_crop: dict | None, flash_analysis: dict | None, time_s: float) -> dict | None:
    if not flash_analysis:
        return base_crop
    frame_analysis = flash_analysis.get("frame_analysis")
    if not isinstance(frame_analysis, list):
        return base_crop
    candidates = [
        entry for entry in frame_analysis
        if isinstance(entry, dict) and isinstance(entry.get("primary_subject_bbox"), dict) and entry.get("timestamp_s") is not None
    ]
    if not candidates:
        return base_crop
    nearest = min(candidates, key=lambda entry: abs(float(entry["timestamp_s"]) - time_s))
    if abs(float(nearest["timestamp_s"]) - time_s) > 0.45:
        return base_crop
    bbox = nearest["primary_subject_bbox"]
    padding = 0.0
    subject_strategy = flash_analysis.get("subject_strategy")
    if isinstance(subject_strategy, dict):
        try:
            padding = float(subject_strategy.get("frame_crop_padding", 0.05))
        except (TypeError, ValueError):
            padding = 0.05
    dynamic = {
        "x": max(0.0, float(bbox.get("x", 0.0)) - padding),
        "y": max(0.0, float(bbox.get("y", 0.0)) - padding),
        "w": min(1.0, float(bbox.get("w", 1.0)) + padding * 2),
        "h": min(1.0, float(bbox.get("h", 1.0)) + padding * 2),
    }
    if base_crop:
        dynamic["x"] = max(0.0, min(dynamic["x"], float(base_crop.get("x", 0.0))))
        dynamic["y"] = max(0.0, min(dynamic["y"], float(base_crop.get("y", 0.0))))
        base_x2 = float(base_crop.get("x", 0.0)) + float(base_crop.get("w", 1.0))
        base_y2 = float(base_crop.get("y", 0.0)) + float(base_crop.get("h", 1.0))
        dyn_x2 = dynamic["x"] + dynamic["w"]
        dyn_y2 = dynamic["y"] + dynamic["h"]
        x2 = min(1.0, max(dyn_x2, base_x2))
        y2 = min(1.0, max(dyn_y2, base_y2))
        dynamic["w"] = max(0.05, x2 - dynamic["x"])
        dynamic["h"] = max(0.05, y2 - dynamic["y"])
    return dynamic


def analyze_pose(segment_video: str, arm_hint: str, crop_hint: dict | None = None, flash_analysis: dict | None = None) -> tuple[list[dict], float, tuple[int, int]]:
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

    cap = cv2.VideoCapture(segment_video)
    fps = cap.get(cv2.CAP_PROP_FPS)
    width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    frames = []

    wrist_idx = 16 if arm_hint == "right" else 15
    shoulder_idx = 12 if arm_hint == "right" else 11

    with PoseLandmarker.create_from_options(options) as landmarker:
        frame_idx = 0
        while True:
            ok, frame = cap.read()
            if not ok:
                break
            active_crop = dynamic_crop_for_time(crop_hint, flash_analysis, frame_idx / fps)
            pose_frame, crop_box = crop_region(frame, active_crop)
            rgb = cv2.cvtColor(pose_frame, cv2.COLOR_BGR2RGB)
            res = landmarker.detect(mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb))
            entry = {
                "frame_index": frame_idx,
                "time": frame_idx / fps,
                "frame": frame,
                "crop_box": crop_box,
                "points": None,
                "wrist_y": None,
                "shoulder_y": None,
                "pose_quality": 0.0,
            }
            if res.pose_landmarks:
                points = []
                for p in res.pose_landmarks[0]:
                    points.append((
                        crop_box[0] + p.x * crop_box[2],
                        crop_box[1] + p.y * crop_box[3],
                        p.visibility,
                    ))
                entry["points"] = points
                entry["wrist_y"] = points[wrist_idx][1]
                entry["shoulder_y"] = points[shoulder_idx][1]
                entry["pose_quality"] = sum(points[idx][2] for idx in PRIMARY_JOINTS) / len(PRIMARY_JOINTS)
            frames.append(entry)
            frame_idx += 1

    cap.release()
    return frames, fps, (width, height)


def nearest_frame(frames: list[dict], target_time: float) -> dict:
    return min(frames, key=lambda f: abs(f["time"] - target_time))


def select_phase_frame(frames: list[dict], hint_time: float, window: float = 0.20, require_pose: bool = False) -> dict:
    candidates = [
        f for f in frames
        if abs(f["time"] - hint_time) <= window and (f["points"] is not None or not require_pose)
    ]
    if not candidates:
        if require_pose:
            pose_frames = [f for f in frames if f["points"] is not None]
            if pose_frames:
                return min(pose_frames, key=lambda f: (abs(f["time"] - hint_time), -f["pose_quality"]))
        return nearest_frame(frames, hint_time)
    return min(candidates, key=lambda f: (abs(f["time"] - hint_time), -f["pose_quality"]))


def wrist_trail(frames: list[dict], anchor_frame: dict, arm_hint: str, count: int = 10) -> list[tuple[float, float]]:
    wrist_idx = 16 if arm_hint == "right" else 15
    start = max(0, anchor_frame["frame_index"] - count)
    trail = []
    for frame in frames[start: anchor_frame["frame_index"] + 1]:
        if frame["points"] is None:
            continue
        trail.append(frame["points"][wrist_idx][:2])
    return trail


def bgr_to_rgba(frame: np.ndarray) -> Image.Image:
    return Image.fromarray(cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)).convert("RGBA")


def xy(point, size) -> tuple[float, float]:
    width, height = size
    return point[0] * width, point[1] * height


def midpoint(a, b):
    return ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2)


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


def pose_metrics(points, arm_hint: str) -> dict[str, int]:
    bowl_shoulder = 12 if arm_hint == "right" else 11
    bowl_wrist = 16 if arm_hint == "right" else 15
    arm_slot = int(round(abs(math.degrees(math.atan2(points[bowl_wrist][1] - points[bowl_shoulder][1], points[bowl_wrist][0] - points[bowl_shoulder][0])))))
    shoulder_mid = midpoint(points[11], points[12])
    hip_mid = midpoint(points[23], points[24])
    torso_lean = int(round(abs(math.degrees(math.atan2(hip_mid[0] - shoulder_mid[0], hip_mid[1] - shoulder_mid[1])))))
    front = (23, 25, 27) if arm_hint == "right" else (24, 26, 28)
    knee_angle = angle_deg(points[front[0]], points[front[1]], points[front[2]])
    return {
        "arm_slot": arm_slot,
        "torso": torso_lean,
        "front_knee": knee_angle,
    }


def draw_labeled_line(draw: ImageDraw.ImageDraw, a, b, size, color, label: str, font, offset=(0, 0), width=6):
    ax, ay = xy(a, size)
    bx, by = xy(b, size)
    draw.line((ax, ay, bx, by), fill=color, width=width)
    lx = (ax + bx) / 2 + offset[0]
    ly = (ay + by) / 2 + offset[1]
    label_box = (lx - 42, ly - 16, lx + 42, ly + 16)
    draw.rounded_rectangle(label_box, radius=12, fill=(10, 14, 20, 230))
    draw.text((lx - 30, ly - 10), label, font=font, fill=(248, 250, 252, 255))


def draw_metric_chip(draw: ImageDraw.ImageDraw, x: int, y: int, label: str, value: int, color, font, small_font):
    box = (x, y, x + 126, y + 58)
    draw.rounded_rectangle(box, radius=18, fill=(10, 14, 20, 222), outline=color, width=2)
    draw.text((x + 14, y + 10), label, font=small_font, fill=(202, 212, 224, 255))
    draw.text((x + 14, y + 28), f"{value}deg", font=font, fill=(248, 250, 252, 255))


def draw_phase_progress(draw: ImageDraw.ImageDraw, width: int, y: int, current_time: float, hints: dict, style: dict):
    accent = tuple(style["accent"])
    accent_secondary = tuple(style["accent_secondary"])
    accent_tertiary = tuple(style.get("accent_tertiary", [142, 242, 92]))
    accent_quaternary = tuple(style.get("accent_quaternary", [255, 102, 163]))
    phases = [
        ("load", hints["load"], accent_secondary),
        ("release", hints["release"], accent),
        ("freeze", hints.get("freeze", hints["release"]), accent_tertiary),
        ("finish", hints["finish"], accent_quaternary),
    ]
    start = hints["load"]
    end = max(hints["finish"], hints.get("freeze", hints["finish"])) + 0.01
    draw.line((42, y, width - 42, y), fill=(72, 82, 94, 255), width=4)
    chip_font = load_font(16, bold=True)
    for label, ts, color in phases:
        norm = 0 if end == start else (ts - start) / (end - start)
        x = 42 + int((width - 84) * max(0.0, min(1.0, norm)))
        draw.ellipse((x - 8, y - 8, x + 8, y + 8), fill=(*color, 255))
        draw.text((x - 24, y + 14), label.upper(), font=chip_font, fill=(226, 232, 240, 255))
    now_norm = 0 if end == start else (current_time - start) / (end - start)
    now_x = 42 + int((width - 84) * max(0.0, min(1.0, now_norm)))
    draw.rounded_rectangle((now_x - 3, y - 14, now_x + 3, y + 14), radius=3, fill=(248, 250, 252, 255))


def draw_skeleton(draw: ImageDraw.ImageDraw, points, size, accent, accent_secondary):
    width, height = size
    for a, b in POSE_CONNECTIONS:
        pa = points[a]
        pb = points[b]
        xa, ya = pa[0] * width, pa[1] * height
        xb, yb = pb[0] * width, pb[1] * height
        draw.line((xa, ya, xb, yb), fill=(*accent, 235), width=5)
    for idx in PRIMARY_JOINTS:
        p = points[idx]
        x, y = p[0] * width, p[1] * height
        draw.ellipse((x - 5, y - 5, x + 5, y + 5), fill=(*accent_secondary, 255))


def draw_trail(draw: ImageDraw.ImageDraw, trail, size, accent):
    width, height = size
    for i, point in enumerate(trail):
        x = point[0] * width
        y = point[1] * height
        radius = max(4, 11 - i)
        alpha = max(70, 230 - i * 16)
        draw.ellipse((x - radius, y - radius, x + radius, y + radius), fill=(*accent, alpha))


def overlay_live_frame(base_img: Image.Image, title: str, subtitle: str, phase: str, style: dict) -> Image.Image:
    img = base_img.copy().convert("RGBA")
    width, height = img.size
    overlay = Image.new("RGBA", img.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)

    bg = tuple(style["background"])
    accent = tuple(style["accent"])

    font_chip = load_font(24, bold=True)
    font_title = load_font(32, bold=True)
    font_sub = load_font(20, bold=False)
    font_phase = load_font(24, bold=True)

    title_lines = wrap_text(draw, title, font_title, width - 80)[:2]
    subtitle_lines = wrap_text(draw, subtitle, font_sub, width - 80)[:2]
    panel_bottom = 58 + len(title_lines) * 34 + len(subtitle_lines) * 24 + 26

    rounded_panel(draw, (20, 20, width - 20, panel_bottom), fill=(*bg, 186), outline=(*accent, 105), width=2, radius=28)
    rounded_panel(draw, (20, height - 110, 230, height - 32), fill=(*bg, 208), radius=24)

    draw.text((40, 32), "AUTO SHAPED DRAFT", font=font_chip, fill=(*accent, 255))
    for idx, line in enumerate(title_lines):
        draw.text((40, 60 + idx * 34), line, font=font_title, fill=(245, 247, 250, 255))
    sub_top = 60 + len(title_lines) * 34 + 8
    for idx, line in enumerate(subtitle_lines):
        draw.text((40, sub_top + idx * 24), line, font=font_sub, fill=(205, 213, 224, 255))
    draw.text((42, height - 88), phase.upper(), font=font_phase, fill=(245, 247, 250, 255))

    return Image.alpha_composite(img, overlay)


def overlay_sequence_frame(base_img: Image.Image, frame_entry: dict, frames: list[dict], title: str, note: str, phase: str, style: dict, arm_hint: str, phase_hints: dict) -> Image.Image:
    img = base_img.copy().convert("RGBA")
    width, height = img.size
    overlay = Image.new("RGBA", img.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)

    bg = tuple(style["background"])
    accent = tuple(style["accent"])
    accent_secondary = tuple(style["accent_secondary"])
    accent_tertiary = tuple(style.get("accent_tertiary", [142, 242, 92]))
    accent_quaternary = tuple(style.get("accent_quaternary", [255, 102, 163]))

    points = frame_entry.get("points")
    trail = wrist_trail(frames, frame_entry, arm_hint, count=8) if points is not None else []
    if points is not None:
        draw_skeleton(draw, points, (width, height), accent, accent_secondary)
        if trail:
            draw_trail(draw, trail, (width, height), accent_secondary)
        bowl_arm = (12, 14, 16) if arm_hint == "right" else (11, 13, 15)
        front_leg = (23, 25, 27) if arm_hint == "right" else (24, 26, 28)
        shoulder_mid = midpoint(points[11], points[12])
        hip_mid = midpoint(points[23], points[24])
        label_font = load_font(14, bold=True)
        draw_labeled_line(draw, points[bowl_arm[0]], points[bowl_arm[2]], (width, height), (*accent, 255), "arm", label_font, offset=(0, -24), width=8)
        draw_labeled_line(draw, shoulder_mid, hip_mid, (width, height), (*accent_quaternary, 255), "torso", label_font, offset=(42, 0), width=6)
        draw_labeled_line(draw, points[front_leg[1]], points[front_leg[2]], (width, height), (*accent_tertiary, 255), "brace", label_font, offset=(44, 14), width=8)

    chip_font = load_font(18, bold=True)
    title_font = load_font(28, bold=True)
    body_font = load_font(20, bold=False)
    metric_font = load_font(20, bold=True)
    small_font = load_font(16, bold=False)

    title_lines = wrap_text(draw, title, title_font, width - 76)[:2]
    note_lines = wrap_text(draw, note, body_font, width - 76)[:2]
    panel_bottom = 56 + len(title_lines) * 32 + len(note_lines) * 22 + 24

    rounded_panel(draw, (20, 20, width - 20, panel_bottom), fill=(*bg, 192), outline=(*accent, 105), width=2, radius=26)
    rounded_panel(draw, (20, height - 128, width - 20, height - 22), fill=(*bg, 204), radius=26)
    draw_phase_progress(draw, width, 154, frame_entry["time"], phase_hints, style)

    draw.text((38, 34), "0.25X ANALYSIS", font=chip_font, fill=(*accent_secondary, 255))
    for idx, line in enumerate(title_lines):
        draw.text((38, 56 + idx * 32), line, font=title_font, fill=(248, 250, 252, 255))
    note_top = 56 + len(title_lines) * 32 + 6
    for idx, line in enumerate(note_lines):
        draw.text((38, note_top + idx * 22), line, font=body_font, fill=(214, 220, 230, 255))

    phase_box = (32, height - 112, 164, height - 48)
    draw.rounded_rectangle(phase_box, radius=18, fill=(*accent, 220))
    draw.text((52, height - 92), phase.upper(), font=chip_font, fill=(10, 14, 20, 255))
    draw.text((184, height - 90), f"{frame_entry['time']:.2f}s", font=chip_font, fill=(235, 241, 248, 255))

    if points is not None:
        metrics = pose_metrics(points, arm_hint)
        draw_metric_chip(draw, width - 146, height - 118, "ARM", metrics["arm_slot"], (*accent, 255), metric_font, small_font)
        draw_metric_chip(draw, width - 146, height - 58, "TORSO", metrics["torso"], (*accent_quaternary, 255), metric_font, small_font)
        draw_metric_chip(draw, width - 282, height - 58, "BRACE", metrics["front_knee"], (*accent_tertiary, 255), metric_font, small_font)

    legend_y = height - 124
    legend_items = [
        ((*accent, 255), "arm"),
        ((*accent_tertiary, 255), "brace"),
        ((*accent_quaternary, 255), "torso"),
    ]
    lx = 32
    for color, label in legend_items:
        draw.ellipse((lx, legend_y - 18, lx + 12, legend_y - 6), fill=color)
        draw.text((lx + 18, legend_y - 24), label, font=small_font, fill=(203, 211, 221, 255))
        lx += 90

    return Image.alpha_composite(img, overlay)


def overlay_freeze_frame(base_img: Image.Image, freeze_points, trail, release_note: str, insight: str, editorial: dict, style: dict) -> Image.Image:
    img = base_img.copy().convert("RGBA")
    width, height = img.size
    overlay = Image.new("RGBA", img.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)

    bg = tuple(style["background"])
    accent = tuple(style["accent"])
    accent_secondary = tuple(style["accent_secondary"])

    if freeze_points is not None:
        draw_skeleton(draw, freeze_points, (width, height), accent, accent_secondary)
    if trail:
        draw_trail(draw, trail, (width, height), accent_secondary)

    rounded_panel(draw, (20, 20, width - 20, 210), fill=(*bg, 194), outline=(*accent, 110), width=2, radius=28)
    rounded_panel(draw, (20, height - 270, width - 20, height - 24), fill=(*bg, 216), radius=32)

    font_chip = load_font(22, bold=True)
    font_title = load_font(36, bold=True)
    font_small = load_font(22, bold=False)
    font_body = load_font(26, bold=False)

    draw.text((40, 34), editorial["freeze_label"], font=font_chip, fill=(*accent_secondary, 255))
    title_lines = wrap_text(draw, editorial["freeze_title"], font_title, width - 80)
    for idx, line in enumerate(title_lines):
        draw.text((40, 66 + idx * 38), line, font=font_title, fill=(248, 250, 252, 255))

    y_release = 66 + len(title_lines) * 38 + 10
    for idx, line in enumerate(wrap_text(draw, release_note, font_small, width - 80)):
        draw.text((40, y_release + idx * 24), line, font=font_small, fill=(213, 219, 228, 255))

    insight_lines = wrap_text(draw, insight, font_body, width - 80)
    for idx, line in enumerate(insight_lines):
        draw.text((40, height - 236 + idx * 32), line, font=font_body, fill=(248, 250, 252, 255))
    draw.text((40, height - 112), "Flash-planned timing. MediaPipe overlay.", font=font_small, fill=(180, 188, 200, 255))

    rounded_panel(draw, (width - 220, 220, width - 34, 292), fill=(*bg, 220), radius=22)
    draw.text((width - 198, 242), editorial["callout_right"], font=font_small, fill=(248, 250, 252, 255))
    rounded_panel(draw, (36, 300, 250, 372), fill=(*bg, 220), radius=22)
    draw.text((58, 322), editorial["callout_left"], font=font_small, fill=(248, 250, 252, 255))

    return Image.alpha_composite(img, overlay)


def overlay_end_card(frame: np.ndarray, headline: str, takeaway: str, finish_note: str, style: dict) -> Image.Image:
    img = bgr_to_rgba(frame).filter(ImageFilter.GaussianBlur(radius=4))
    width, height = img.size
    overlay = Image.new("RGBA", img.size, (*tuple(style["background"]), 228))
    draw = ImageDraw.Draw(overlay)
    accent = tuple(style["accent"])
    accent_secondary = tuple(style["accent_secondary"])

    rounded_panel(draw, (28, 156, width - 28, height - 120), fill=(16, 20, 28, 240), outline=(*accent, 110), width=2, radius=34)
    draw.rectangle((58, 198, 88, 332), fill=(*accent_secondary, 255))

    font_chip = load_font(22, bold=True)
    font_title = load_font(38, bold=True)
    font_body = load_font(26, bold=False)
    font_small = load_font(20, bold=False)

    draw.text((110, 198), "STANDALONE TOOL OUTPUT", font=font_chip, fill=(*accent, 255))
    for idx, line in enumerate(wrap_text(draw, headline, font_title, width - 160)):
        draw.text((110, 236 + idx * 42), line, font=font_title, fill=(248, 250, 252, 255))
    body_top = 236 + len(wrap_text(draw, headline, font_title, width - 160)) * 42 + 20
    for idx, line in enumerate(wrap_text(draw, takeaway, font_body, width - 160)):
        draw.text((110, body_top + idx * 30), line, font=font_body, fill=(242, 245, 248, 255))
    finish_top = body_top + len(wrap_text(draw, takeaway, font_body, width - 160)) * 30 + 20
    for idx, line in enumerate(wrap_text(draw, finish_note, font_body, width - 160)):
        draw.text((110, finish_top + idx * 30), line, font=font_body, fill=(210, 218, 228, 255))
    draw.text((110, height - 176), "MediaPipe handles pose. Gemini drafts the story. Human shapes the final cut.", font=font_small, fill=(176, 186, 198, 255))
    draw.text((110, height - 144), "This clip is the first reliable single-bowler export path.", font=font_small, fill=(176, 186, 198, 255))

    return Image.alpha_composite(img, overlay)


def save_storyboard(cards: list[tuple[str, Image.Image]], output_path: str):
    if not cards:
        return
    tile_w = 240
    tile_h = 424
    gutter = 24
    cols = 2
    rows = (len(cards) + cols - 1) // cols
    canvas_w = cols * tile_w + (cols + 1) * gutter
    canvas_h = rows * (tile_h + 58) + (rows + 1) * gutter
    canvas = Image.new("RGB", (canvas_w, canvas_h), (11, 14, 20))
    draw = ImageDraw.Draw(canvas)
    label_font = load_font(22, bold=True)

    for idx, (label, image) in enumerate(cards):
        row = idx // cols
        col = idx % cols
        x = gutter + col * (tile_w + gutter)
        y = gutter + row * (tile_h + 58 + gutter)
        tile = image.convert("RGB").resize((tile_w, tile_h))
        canvas.paste(tile, (x, y))
        draw.text((x, y + tile_h + 14), label.upper(), font=label_font, fill=(232, 236, 242))

    canvas.save(output_path, quality=95)


def encode_video(frames: list[Image.Image], output_path: str, fps: float):
    if not frames:
        raise ValueError("No frames to encode")
    width, height = frames[0].size
    writer = cv2.VideoWriter(output_path, cv2.VideoWriter_fourcc(*"mp4v"), fps, (width, height))
    for image in frames:
        rgb = np.array(image.convert("RGB"))
        bgr = cv2.cvtColor(rgb, cv2.COLOR_RGB2BGR)
        writer.write(bgr)
    writer.release()


def load_auxiliary_frames(video_path: Path) -> list[np.ndarray]:
    if not video_path.exists():
        return []
    cap = cv2.VideoCapture(str(video_path))
    frames = []
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        frames.append(frame)
    cap.release()
    return frames


def pick_auxiliary_base(aux_frames: list[np.ndarray], frame_index: int, fallback_frame: np.ndarray) -> Image.Image:
    if aux_frames and 0 <= frame_index < len(aux_frames):
        return bgr_to_rgba(aux_frames[frame_index])
    return bgr_to_rgba(fallback_frame)


def render_project(config_path: str, use_gemini: bool = True):
    with open(config_path) as f:
        config = json.load(f)

    output_dir = Path(config["output_dir"])
    output_dir.mkdir(parents=True, exist_ok=True)

    segment_path = output_dir / "segment.mp4"
    metadata = write_segment(config["input_video"], config["segment"]["start"], config["segment"]["end"], str(segment_path))

    draft = None
    draft_path = output_dir / "gemini_draft.json"
    if use_gemini:
        try:
            draft = call_gemini(str(segment_path), str(draft_path))
        except Exception as exc:
            draft = {"error": str(exc)}
            with open(draft_path, "w") as f:
                json.dump(draft, f, indent=2)

    frames, fps, _ = analyze_pose(
        str(segment_path),
        config["arm_hint"],
        config.get("pose_crop"),
        config.get("flash_analysis"),
    )
    figure_variant_frames = load_auxiliary_frames(output_dir / "bowler_figure_only.mp4")
    pose_variant_frames = load_auxiliary_frames(output_dir / "bowler_pose_only.mp4")
    hints = config["phase_hints"]
    load_frame = nearest_frame(frames, hints["load"])
    release_frame = nearest_frame(frames, hints["release"])
    release_time = hints["release"]
    finish_frame = select_phase_frame(frames, hints["finish"], window=hints.get("finish_window", 0.16), require_pose=False)
    freeze_frame = select_phase_frame(
        frames,
        hints.get("freeze", hints["release"]),
        window=hints.get("freeze_window", 0.12),
        require_pose=True,
    )
    trail = wrist_trail(frames, freeze_frame, config["arm_hint"], count=10)

    editorial = config["editorial"]
    title = draft.get("headline") if draft and draft.get("headline") else editorial["title"]
    insight = draft.get("primary_insight") if draft and draft.get("primary_insight") else editorial["fallback_insight"]
    takeaway = draft.get("coaching_takeaway") if draft and draft.get("coaching_takeaway") else editorial["fallback_takeaway"]
    release_note = draft.get("release_note") if draft and draft.get("release_note") else editorial["fallback_release_note"]
    finish_note = draft.get("finish_note") if draft and draft.get("finish_note") else editorial["fallback_finish_note"]
    render_cfg = config.get("render", {})
    slow_factor = int(render_cfg.get("slow_factor", 4))
    intro_hold = int(render_cfg.get("intro_hold", 10))
    freeze_hold = int(render_cfg.get("freeze_hold", 16))
    end_hold = int(render_cfg.get("end_hold", 20))
    output_fps = max(1.0, fps / max(1, slow_factor))

    rendered = []

    intro_crop = dynamic_crop_for_time(config.get("pose_crop"), config.get("flash_analysis"), release_time)
    intro_base = crop_pil_image(bgr_to_rgba(release_frame["frame"]), intro_crop).filter(ImageFilter.GaussianBlur(radius=2))
    intro = overlay_live_frame(intro_base, title, editorial["subtitle"], editorial["series"], config["style"])
    release_preview = overlay_sequence_frame(
        pick_auxiliary_base(figure_variant_frames, release_frame["frame_index"], release_frame["frame"]),
        release_frame,
        frames,
        title,
        release_note,
        "release",
        config["style"],
        config["arm_hint"],
        hints,
    )
    load_preview = overlay_sequence_frame(
        pick_auxiliary_base(figure_variant_frames, load_frame["frame_index"], load_frame["frame"]),
        load_frame,
        frames,
        title,
        "Load into the gather before the arm whips over.",
        "load",
        config["style"],
        config["arm_hint"],
        hints,
    )
    rendered.extend([intro] * max(1, int(round(intro_hold / max(1, slow_factor)))))

    freeze_inserted = False
    hero = None
    for frame in frames:
        if frame["time"] > finish_frame["time"] + 0.25:
            break
        phase = "load" if frame["time"] < release_time - 0.12 else ("release" if frame["time"] <= release_time + 0.10 else "finish")
        note = "Build into release." if phase == "load" else (release_note if phase == "release" else finish_note)
        base_img = pick_auxiliary_base(figure_variant_frames, frame["frame_index"], frame["frame"])
        img = overlay_sequence_frame(
            base_img,
            frame,
            frames,
            title,
            note,
            phase,
            config["style"],
            config["arm_hint"],
            hints,
        )
        rendered.append(img)
        if not freeze_inserted and frame["frame_index"] >= freeze_frame["frame_index"]:
            freeze_base = pick_auxiliary_base(pose_variant_frames, freeze_frame["frame_index"], freeze_frame["frame"])
            if pose_variant_frames:
                hero = overlay_freeze_frame(freeze_base, None, [], release_note, insight, editorial, config["style"])
            elif freeze_frame["points"] is not None:
                hero = overlay_freeze_frame(freeze_base, freeze_frame["points"], trail, release_note, insight, editorial, config["style"])
            else:
                hero = overlay_live_frame(freeze_base, title, release_note, editorial["freeze_label"], config["style"])
            hero_path = output_dir / "hero_release_frame.jpg"
            hero.convert("RGB").save(hero_path, quality=95)
            rendered.extend([hero] * max(1, int(round(freeze_hold / max(1, slow_factor)))))
            freeze_inserted = True

    end_card = overlay_end_card(finish_frame["frame"], title, takeaway, finish_note, config["style"])
    rendered.extend([end_card] * max(1, int(round(end_hold / max(1, slow_factor)))))

    output_video = output_dir / "annotated_analysis.mp4"
    encode_video(rendered, str(output_video), output_fps)
    storyboard_path = output_dir / "storyboard.jpg"
    save_storyboard([
        ("Intro", intro),
        ("Load", load_preview),
        ("Release", release_preview),
        ("Freeze", hero if hero is not None else release_preview),
        ("End Card", end_card),
    ], str(storyboard_path))

    manifest = {
        "config": config_path,
        "segment": str(segment_path),
        "hero_frame": str(output_dir / "hero_release_frame.jpg"),
        "storyboard": str(storyboard_path),
        "video": str(output_video),
        "gemini_draft": str(draft_path),
        "metadata": metadata,
        "release_time_hint": round(release_time, 3),
        "freeze_time": round(freeze_frame["time"], 3),
        "finish_time": round(finish_frame["time"], 3),
    }
    with open(output_dir / "artifact_manifest.json", "w") as f:
        json.dump(manifest, f, indent=2)

    print(json.dumps(manifest, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Render a bowling analysis video from a human-shaped config.")
    parser.add_argument("config", help="Path to story config JSON")
    parser.add_argument("--skip-gemini", action="store_true", help="Disable Gemini draft call")
    args = parser.parse_args()
    render_project(args.config, use_gemini=not args.skip_gemini)
