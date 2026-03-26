#!/usr/bin/env python3
"""X-Factor v1.0.0 — Standalone pipeline.

Usage:
    python run_v100.py <input_clip.mp4> [--output <output.mp4>] [--skip-gemini]

Takes any bowling clip → produces YouTube-upload-ready 9:16 X-Factor analysis video.
Works on Mac and Linux with venv.
"""
from __future__ import annotations

import argparse
import base64
import json
import math
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

import logging

import cv2
import mediapipe as mp
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

logging.basicConfig(level=logging.INFO, format="  [%(name)s] %(message)s")
log = logging.getLogger("xfactor")

# ─── Config ──────────────────────────────────────────────────────────────────

REPO_ROOT = Path(__file__).resolve().parents[2]
MODEL_PATH = REPO_ROOT / "resources" / "pose_landmarker_heavy.task"
ENV_PATH = REPO_ROOT / "linux_content_pipeline_work" / ".env"

OUT_W, OUT_H = 1080, 1920
OUTPUT_FPS = 30.0
SLOW_FACTOR = 4  # 0.25x — slow enough to see the separation build

# Colors
HIP_COLOR = (255, 105, 180)       # #FF69B4 hot pink
SHOULDER_COLOR = (0, 206, 209)    # #00CED1 dark turquoise
DARK_BG = (10, 14, 20)            # #0A0E14
BRAND_TEAL = (0, 109, 119)        # #006D77
WHITE = (255, 255, 255)
LIGHT_GREY = (180, 190, 200)
ACCENT_RED = (255, 80, 64)        # #FF5040
SAFE_GREEN = (100, 255, 100)
WARN_YELLOW = (255, 220, 80)
WORK_ORANGE = (255, 140, 60)

# Pose
PRIMARY_JOINTS = [11, 12, 13, 14, 15, 16, 23, 24, 25, 26, 27, 28]
XFACTOR_JOINTS = [11, 12, 23, 24]  # L_SHOULDER, R_SHOULDER, L_HIP, R_HIP
POSE_CONNECTIONS = [
    (11, 12), (11, 13), (13, 15), (12, 14), (14, 16),
    (11, 23), (12, 24), (23, 24), (23, 25), (25, 27), (24, 26), (26, 28),
]
XFACTOR_VIS_THRESHOLD = 0.5
MIN_LINE_SPREAD = 0.03
MAX_SEPARATION = 60.0
SMOOTH_WINDOW = 5

# ─── Font Loading ────────────────────────────────────────────────────────────

def load_font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    candidates = []
    if bold:
        candidates = [
            "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
            "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
            "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
            "/System/Library/Fonts/Supplemental/Helvetica.ttc",
        ]
    else:
        candidates = [
            "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf",
            "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
            "/System/Library/Fonts/Supplemental/Arial.ttf",
            "/System/Library/Fonts/Supplemental/Helvetica.ttc",
        ]
    for c in candidates:
        if Path(c).exists():
            try:
                return ImageFont.truetype(c, size=size)
            except OSError:
                continue
    return ImageFont.load_default()


# ─── Gemini Flash ────────────────────────────────────────────────────────────

def load_api_key() -> str | None:
    key = os.environ.get("GEMINI_API_KEY")
    if key:
        return key
    for env in [ENV_PATH, REPO_ROOT / ".env"]:
        if env.exists():
            for line in env.read_text().splitlines():
                if line.startswith("GEMINI_API_KEY="):
                    return line.split("=", 1)[1].strip()
    return None


def call_gemini_flash(video_path: str) -> dict | None:
    """One Flash call: identify bowler ROI + phase timing. Returns dict or None."""
    api_key = load_api_key()
    if not api_key:
        log.warning("No GEMINI_API_KEY found — skipping Flash call")
        return None

    # Build contact sheet (6 frames)
    cap = cv2.VideoCapture(video_path)
    fps = cap.get(cv2.CAP_PROP_FPS)
    total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    duration = total / max(1, fps)
    frames = []
    for i in range(6):
        ts = duration * i / 5
        cap.set(cv2.CAP_PROP_POS_FRAMES, min(int(ts * fps), total - 1))
        ok, frame = cap.read()
        if ok:
            frames.append((round(ts, 2), frame))
    cap.release()

    if not frames:
        return None

    # Composite contact sheet
    cols, tile_w, tile_h = 3, 320, 240
    rows = 2
    sheet = np.zeros((rows * tile_h, cols * tile_w, 3), dtype=np.uint8)
    sheet[:] = DARK_BG
    for i, (ts, frame) in enumerate(frames):
        r, c = i // cols, i % cols
        resized = cv2.resize(frame, (tile_w, tile_h))
        sheet[r * tile_h:(r + 1) * tile_h, c * tile_w:(c + 1) * tile_w] = resized

    _, buf = cv2.imencode(".jpg", sheet, [cv2.IMWRITE_JPEG_QUALITY, 80])
    sheet_b64 = base64.b64encode(buf).decode("utf-8")

    frame_list = "\n".join(f"- F{i+1}: {ts:.2f}s" for i, (ts, _) in enumerate(frames))
    prompt = f"""You are analyzing a cricket bowling clip for X-FACTOR measurement (hip-shoulder separation angle).

This contact sheet shows 6 frames:
{frame_list}

Task: Identify the PRIMARY BOWLER (person actively delivering the ball) and provide TIGHT timing for the delivery stride only.

Return STRICT JSON:
{{
  "bowler_roi": {{"x": 0.0, "y": 0.0, "w": 1.0, "h": 1.0}},
  "bowling_arm": "right|left",
  "phases": {{
    "back_foot_contact": 0.0,
    "front_foot_contact": 0.0,
    "release": 0.0,
    "follow_through": 0.0
  }},
  "delivery_roi": {{"x": 0.0, "y": 0.0, "w": 1.0, "h": 1.0}}
}}

Rules:
- bowler_roi: bounding box containing the bowler across ALL frames (generous, 15% padding).
- delivery_roi: TIGHT bounding box containing the bowler ONLY during the delivery stride (back_foot_contact to release). Exclude bystanders, fielders, batsmen. This should be as tight as possible around the bowler's torso area during the delivery.
- Phases are timestamps in seconds. Be precise.
- back_foot_contact: when the bowler's back foot lands at the crease.
- release: when the ball leaves the hand.
- Ignore ALL other people in the frame."""

    payload = {
        "contents": [{"parts": [
            {"inlineData": {"mimeType": "image/jpeg", "data": sheet_b64}},
            {"text": prompt},
        ]}],
        "generationConfig": {"temperature": 0.1, "responseMimeType": "application/json"},
    }

    url = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key={api_key}"
    # Use Pro for better spatial reasoning if available
    # url = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-3-pro-preview:generateContent?key={api_key}"
    req = urllib.request.Request(url, data=json.dumps(payload).encode(), headers={"Content-Type": "application/json"})
    try:
        log.info("Sending contact sheet to Gemini Flash...")
        with urllib.request.urlopen(req, timeout=60) as resp:
            data = json.loads(resp.read().decode())
        text = data["candidates"][0]["content"]["parts"][0]["text"]
        result = json.loads(text)
        log.info(f"Flash response: {json.dumps(result, indent=2)[:500]}")
        return result
    except Exception as e:
        log.error(f"Flash call failed: {e}")
        return None


# ─── Pose Extraction ─────────────────────────────────────────────────────────

def extract_poses(video_path: str, bowler_roi: dict | None = None) -> dict:
    """Extract per-frame poses, tracking the bowler only."""
    cap = cv2.VideoCapture(video_path)
    fps = cap.get(cv2.CAP_PROP_FPS)
    width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))

    options = mp.tasks.vision.PoseLandmarkerOptions(
        base_options=mp.tasks.BaseOptions(model_asset_path=str(MODEL_PATH)),
        running_mode=mp.tasks.vision.RunningMode.IMAGE,
        num_poses=4,
        min_pose_detection_confidence=0.4,
        min_tracking_confidence=0.4,
    )

    frames = []
    prev_bbox = None
    bowler_size = None

    with mp.tasks.vision.PoseLandmarker.create_from_options(options) as landmarker:
        idx = 0
        while True:
            ok, frame_bgr = cap.read()
            if not ok:
                break

            # Crop to ROI if available
            if bowler_roi:
                rx = max(0, int(bowler_roi["x"] * width))
                ry = max(0, int(bowler_roi["y"] * height))
                rw = min(width - rx, int(bowler_roi["w"] * width))
                rh = min(height - ry, int(bowler_roi["h"] * height))
                crop = frame_bgr[ry:ry+rh, rx:rx+rw]
                rgb = cv2.cvtColor(crop, cv2.COLOR_BGR2RGB)
            else:
                rx, ry, rw, rh = 0, 0, width, height
                rgb = cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2RGB)

            result = landmarker.detect(mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb))

            chosen = None
            if result.pose_landmarks:
                best_score = -1.0
                for pose in result.pose_landmarks:
                    pts = [((rx + p.x * rw) / width, (ry + p.y * rh) / height, p.visibility) for p in pose]
                    score = _score_candidate(pts, prev_bbox, bowler_size)
                    if score > best_score:
                        best_score = score
                        chosen = pts

            if chosen:
                bbox = _bbox_from_pts(chosen)
                if bbox:
                    prev_bbox = bbox
                    bowler_size = bbox["area"] if bowler_size is None else bowler_size * 0.85 + bbox["area"] * 0.15

            frames.append({
                "index": idx,
                "time": round(idx / fps, 4),
                "landmarks": chosen,
                "frame_bgr": frame_bgr,
            })
            idx += 1

    cap.release()
    return {"frames": frames, "fps": fps, "width": width, "height": height}


def _bbox_from_pts(pts):
    xs = [pts[i][0] for i in PRIMARY_JOINTS if pts[i][2] > 0.3]
    ys = [pts[i][1] for i in PRIMARY_JOINTS if pts[i][2] > 0.3]
    if len(xs) < 6:
        return None
    x1, x2, y1, y2 = min(xs), max(xs), min(ys), max(ys)
    return {"x1": x1, "y1": y1, "x2": x2, "y2": y2, "cx": (x1+x2)/2, "cy": (y1+y2)/2, "area": (x2-x1)*(y2-y1)}


def _iou(a, b):
    ix1, iy1 = max(a["x1"], b["x1"]), max(a["y1"], b["y1"])
    ix2, iy2 = min(a["x2"], b["x2"]), min(a["y2"], b["y2"])
    inter = max(0, ix2-ix1) * max(0, iy2-iy1)
    return inter / max(1e-6, a["area"] + b["area"] - inter)


def _score_candidate(pts, prev_bbox, bowler_size):
    bbox = _bbox_from_pts(pts)
    if not bbox:
        return -1.0
    vis = sum(pts[i][2] for i in PRIMARY_JOINTS) / len(PRIMARY_JOINTS)
    if prev_bbox is None:
        return bbox["area"] * 5.0 + vis
    dist = ((bbox["cx"]-prev_bbox["cx"])**2 + (bbox["cy"]-prev_bbox["cy"])**2)**0.5
    if dist > 0.50:
        return -1.0
    if bowler_size and bbox["area"] < bowler_size * 0.3:
        return -1.0
    return _iou(bbox, prev_bbox) * 12.0 + max(0, 3.0 - dist * 6.0) + vis * 0.5 + bbox["area"]


# ─── X-Factor Computation ────────────────────────────────────────────────────

def compute_xfactor(frames: list[dict]) -> list[dict]:
    """Compute hip-shoulder separation per frame with smoothing."""
    for f in frames:
        pts = f.get("landmarks")
        f["hip_angle"] = f["shoulder_angle"] = f["separation"] = None
        if not pts:
            continue
        ha = _line_angle(pts[23], pts[24])
        sa = _line_angle(pts[11], pts[12])
        if ha is not None and sa is not None:
            sep = abs(ha - sa)
            if sep > 180:
                sep = 360 - sep
            f["hip_angle"], f["shoulder_angle"] = ha, sa
            f["separation"] = min(sep, MAX_SEPARATION)

    # Median smoothing
    raw = [f["separation"] for f in frames]
    hw = SMOOTH_WINDOW // 2
    for i, f in enumerate(frames):
        window = [raw[j] for j in range(max(0, i-hw), min(len(frames), i+hw+1)) if raw[j] is not None]
        f["separation"] = sorted(window)[len(window)//2] if window else None
    return frames


def _line_angle(p1, p2):
    if p1[2] < XFACTOR_VIS_THRESHOLD or p2[2] < XFACTOR_VIS_THRESHOLD:
        return None
    if abs(p2[0]-p1[0]) < MIN_LINE_SPREAD and abs(p2[1]-p1[1]) < MIN_LINE_SPREAD:
        return None
    return math.degrees(math.atan2(p2[1]-p1[1], p2[0]-p1[0]))


def find_peak(frames):
    valid = [f for f in frames if f.get("separation") is not None]
    return max(valid, key=lambda f: f["separation"]) if valid else None


def detect_phases(frames):
    peak = find_peak(frames)
    if not peak:
        t = frames[-1]["time"] if frames else 1.0
        return {"back_foot_contact": 0, "front_foot_contact": t*0.35, "release": t*0.5, "follow_through": t*0.7}
    pt = peak["time"]
    t = frames[-1]["time"]
    return {"back_foot_contact": max(0, pt-0.4), "front_foot_contact": max(0, pt-0.1), "release": pt, "follow_through": min(t, pt+0.3)}


# ─── Rendering ───────────────────────────────────────────────────────────────

def _extend_line(p1, p2, ext=0.25):
    dx, dy = p2[0]-p1[0], p2[1]-p1[1]
    return (int(p1[0]-dx*ext), int(p1[1]-dy*ext)), (int(p2[0]+dx*ext), int(p2[1]+dy*ext))


def _sep_color(sep):
    if sep < 15: return (200, 200, 200)
    if sep < 30: return WARN_YELLOW
    if sep < 45: return SAFE_GREEN
    return (80, 255, 80)


def render_overlay(frame_bgr, landmarks, separation, phase_label):
    """Render X-factor overlay on a single frame. All text via Pillow."""
    h, w = frame_bgr.shape[:2]
    out = frame_bgr.copy()

    if not landmarks:
        return out

    # Gate: all 4 x-factor joints must be visible
    if not all(landmarks[j][2] > XFACTOR_VIS_THRESHOLD for j in XFACTOR_JOINTS):
        return out

    def px(idx):
        p = landmarks[idx]
        return (int(p[0]*w), int(p[1]*h)) if p[2] > 0.3 else None

    # Subtle skeleton (35% opacity)
    skel = out.copy()
    for a, b in POSE_CONNECTIONS:
        pa, pb = px(a), px(b)
        if pa and pb:
            cv2.line(skel, pa, pb, (180, 180, 180), 1, cv2.LINE_AA)
    cv2.addWeighted(skel, 0.35, out, 0.65, 0, out)

    # Hip line
    lh, rh = px(23), px(24)
    if lh and rh:
        ea, eb = _extend_line(lh, rh)
        cv2.line(out, ea, eb, HIP_COLOR[::-1], 4, cv2.LINE_AA)
        for p in [lh, rh]:
            cv2.circle(out, p, 7, WHITE, 2, cv2.LINE_AA)
            cv2.circle(out, p, 5, HIP_COLOR[::-1], -1, cv2.LINE_AA)

    # Shoulder line
    ls, rs = px(11), px(12)
    if ls and rs:
        ea, eb = _extend_line(ls, rs)
        cv2.line(out, ea, eb, SHOULDER_COLOR[::-1], 4, cv2.LINE_AA)
        for p in [ls, rs]:
            cv2.circle(out, p, 7, WHITE, 2, cv2.LINE_AA)
            cv2.circle(out, p, 5, SHOULDER_COLOR[::-1], -1, cv2.LINE_AA)

    # Now switch to Pillow for anti-aliased text
    pil = Image.fromarray(cv2.cvtColor(out, cv2.COLOR_BGR2RGB))
    draw = ImageDraw.Draw(pil)

    # Angle pill near torso
    if separation is not None and lh and rh and ls and rs:
        mx = (lh[0]+rh[0]+ls[0]+rs[0]) // 4
        my = (lh[1]+rh[1]+ls[1]+rs[1]) // 4
        font_num = load_font(32, bold=True)
        font_deg = load_font(18)
        txt = f"{separation:.0f}"
        tw = draw.textlength(txt, font=font_num)
        pw, ph = int(tw + 36), 44
        pill_x, pill_y = mx - pw//2, my - ph//2
        draw.rounded_rectangle((pill_x, pill_y, pill_x+pw, pill_y+ph), radius=14, fill=(*DARK_BG, 200))
        draw.text((pill_x+10, pill_y+6), txt, font=font_num, fill=_sep_color(separation))
        draw.text((pill_x+10+int(tw)+2, pill_y+14), "°", font=font_deg, fill=_sep_color(separation))

    # Phase label top-center
    font_phase = load_font(18, bold=True)
    label = phase_label.upper()
    tw = draw.textlength(label, font=font_phase)
    pw, ph = int(tw+28), 32
    pill_x = w//2 - pw//2
    draw.rounded_rectangle((pill_x, 16, pill_x+pw, 48), radius=12, fill=(*DARK_BG, 190))
    draw.text((pill_x+14, 23), label, font=font_phase, fill=WHITE)

    # Legend bar bottom
    font_leg = load_font(14, bold=True)
    ly = h - 34
    draw.rounded_rectangle((20, ly, 110, ly+22), radius=8, fill=(*DARK_BG, 170))
    draw.ellipse((26, ly+5, 38, ly+17), fill=HIP_COLOR)
    draw.text((44, ly+3), "HIPS", font=font_leg, fill=WHITE)
    draw.rounded_rectangle((120, ly, 240, ly+22), radius=8, fill=(*DARK_BG, 170))
    draw.ellipse((126, ly+5, 138, ly+17), fill=SHOULDER_COLOR)
    draw.text((144, ly+3), "SHOULDERS", font=font_leg, fill=WHITE)

    return cv2.cvtColor(np.array(pil), cv2.COLOR_RGB2BGR)


def fit_to_canvas(frame_bgr, watermark=True):
    """Fit frame to 1080x1920 canvas, letterboxed, with brand watermark."""
    h, w = frame_bgr.shape[:2]
    scale = OUT_W / w
    nw, nh = OUT_W, int(h * scale)
    resized = cv2.resize(frame_bgr, (nw, nh), interpolation=cv2.INTER_LANCZOS4)
    canvas = np.zeros((OUT_H, OUT_W, 3), dtype=np.uint8)
    canvas[:] = DARK_BG
    y = (OUT_H - nh) // 2
    canvas[y:y+nh, 0:nw] = resized

    if watermark:
        pil = Image.fromarray(cv2.cvtColor(canvas, cv2.COLOR_BGR2RGB))
        draw = ImageDraw.Draw(pil)
        font_wm = load_font(22, bold=True)
        wm = "wellBowled.ai"
        ww = draw.textlength(wm, font=font_wm)
        wx, wy = OUT_W - ww - 24, OUT_H - 36
        # Glow effect
        for dx, dy in [(-1, -1), (-1, 1), (1, -1), (1, 1)]:
            draw.text((wx + dx, wy + dy), wm, font=font_wm, fill=(0, 60, 65))
        draw.text((wx, wy), wm, font=font_wm, fill=BRAND_TEAL)
        canvas = cv2.cvtColor(np.array(pil), cv2.COLOR_RGB2BGR)

    return canvas


def make_freeze_card(frame_bgr, peak_sep):
    """Dramatic freeze card at peak separation."""
    canvas = fit_to_canvas(frame_bgr)
    # Darken 65%
    dark = np.zeros_like(canvas)
    dark[:] = DARK_BG
    canvas = cv2.addWeighted(dark, 0.65, canvas, 0.35, 0)

    pil = Image.fromarray(cv2.cvtColor(canvas, cv2.COLOR_BGR2RGB))
    draw = ImageDraw.Draw(pil)
    cx, cy = OUT_W//2, OUT_H//2 - 60

    font_label = load_font(28, bold=True)
    font_big = load_font(72, bold=True)
    font_sub = load_font(22)

    draw.text((cx - draw.textlength("PEAK X-FACTOR", font=font_label)//2, cy-50), "PEAK X-FACTOR", font=font_label, fill=WHITE)
    angle_txt = f"{peak_sep:.0f}°"
    draw.text((cx - draw.textlength(angle_txt, font=font_big)//2, cy), angle_txt, font=font_big, fill=ACCENT_RED)
    sub = "Hip-shoulder separation at maximum"
    draw.text((cx - draw.textlength(sub, font=font_sub)//2, cy+80), sub, font=font_sub, fill=LIGHT_GREY)

    # Legend
    font_leg = load_font(18)
    ly = OUT_H - 60
    draw.ellipse((cx-110, ly, cx-96, ly+14), fill=HIP_COLOR)
    draw.text((cx-88, ly-1), "hips", font=font_leg, fill=LIGHT_GREY)
    draw.ellipse((cx+20, ly, cx+34, ly+14), fill=SHOULDER_COLOR)
    draw.text((cx+42, ly-1), "shoulders", font=font_leg, fill=LIGHT_GREY)

    return cv2.cvtColor(np.array(pil), cv2.COLOR_RGB2BGR)


def _draw_skeleton_frame(landmarks, frame_bgr):
    """Render skeleton dots+lines on dark background for animation."""
    canvas = np.zeros((OUT_H, OUT_W, 3), dtype=np.uint8)
    canvas[:] = DARK_BG
    if not landmarks:
        return canvas
    h, w = frame_bgr.shape[:2]
    scale = OUT_W / w
    y_off = (OUT_H - int(h * scale)) // 2
    for a, b in POSE_CONNECTIONS:
        if landmarks[a][2] > 0.3 and landmarks[b][2] > 0.3:
            x1 = int(landmarks[a][0] * w * scale)
            y1 = int(landmarks[a][1] * h * scale) + y_off
            x2 = int(landmarks[b][0] * w * scale)
            y2 = int(landmarks[b][1] * h * scale) + y_off
            cv2.line(canvas, (x1, y1), (x2, y2), (50, 60, 75), 3, cv2.LINE_AA)
    for idx in PRIMARY_JOINTS:
        if landmarks[idx][2] > 0.3:
            x = int(landmarks[idx][0] * w * scale)
            y = int(landmarks[idx][1] * h * scale) + y_off
            cv2.circle(canvas, (x, y), 5, (70, 85, 100), -1, cv2.LINE_AA)
    return canvas


def _draw_verdict_overlay(base_bgr, peak_sep):
    """Full-screen frosted glass verdict over animated skeleton background."""
    # Frosted glass: blur + darken the skeleton background
    blurred = cv2.GaussianBlur(base_bgr, (31, 31), 12)

    pil = Image.fromarray(cv2.cvtColor(blurred, cv2.COLOR_BGR2RGB)).convert("RGBA")
    # Full-screen semi-transparent dark overlay
    glass = Image.new("RGBA", (OUT_W, OUT_H), (10, 14, 20, 170))
    pil = Image.alpha_composite(pil, glass)

    draw = ImageDraw.Draw(pil)
    cx = OUT_W // 2

    # Rating
    if peak_sep >= 45:
        rating, color, note = "ELITE", SAFE_GREEN, "Elite-level rotational mechanics"
    elif peak_sep >= 35:
        rating, color, note = "VERY GOOD", (130, 230, 130), "Strong hip pre-rotation"
    elif peak_sep >= 28:
        rating, color, note = "DEVELOPING", WARN_YELLOW, "Room to lead more with the hip"
    else:
        rating, color, note = "WORK ON IT", WORK_ORANGE, "Focus on hip pre-rotation drills"

    # Vertically centered — all content occupies middle third
    y = OUT_H // 2 - 280

    # Title
    f_title = load_font(36, bold=True)
    t = "X-FACTOR"
    draw.text((cx - draw.textlength(t, font=f_title) // 2, y), t, font=f_title, fill=(200, 208, 220))
    y += 55

    # Big angle — hero
    f_angle = load_font(140, bold=True)
    f_deg = load_font(52)
    angle_txt = f"{peak_sep:.0f}"
    aw = draw.textlength(angle_txt, font=f_angle)
    dw = draw.textlength("°", font=f_deg)
    draw.text((cx - (aw + dw) // 2, y), angle_txt, font=f_angle, fill=ACCENT_RED)
    draw.text((cx - (aw + dw) // 2 + aw + 4, y + 30), "°", font=f_deg, fill=ACCENT_RED)
    y += 160

    # Rating word
    f_rating = load_font(52, bold=True)
    draw.text((cx - draw.textlength(rating, font=f_rating) // 2, y), rating, font=f_rating, fill=color)
    y += 80

    # Comparison bar — full width
    bar_x, bar_w, bar_h = 40, OUT_W - 80, 50
    draw.rounded_rectangle((bar_x, y, bar_x + bar_w, y + bar_h), radius=10, fill=(20, 25, 35, 200))

    def a2x(angle):
        return bar_x + int((min(55, max(0, angle)) / 55) * bar_w)

    f_ref = load_font(18, bold=True)
    for label, angle, clr in [("Untrained", 12, (90, 90, 90)), ("Amateur", 20, (140, 140, 140)), ("Good", 30, WARN_YELLOW), ("Elite", 42, SAFE_GREEN), ("Peak", 50, (80, 255, 80))]:
        x = a2x(angle)
        draw.line((x, y + 4, x, y + bar_h - 4), fill=clr, width=3)
        lw = draw.textlength(label, font=f_ref)
        draw.text((x - lw // 2, y + bar_h + 8), label, font=f_ref, fill=clr)

    you_x = a2x(peak_sep)
    draw.line((you_x, y - 6, you_x, y + bar_h + 6), fill=WHITE, width=5)
    f_you = load_font(20, bold=True)
    yw = draw.textlength("You", font=f_you)
    draw.text((you_x - yw // 2, y - 28), "You", font=f_you, fill=WHITE)
    y += bar_h + 45

    # Note
    f_note = load_font(24)
    draw.text((cx - draw.textlength(note, font=f_note) // 2, y), note, font=f_note, fill=LIGHT_GREY)
    y += 50

    # Insight
    f_body = load_font(22)
    for line in ["Lead with the hip. Let the shoulder lag.", "The bigger the gap, the more pace."]:
        lw = draw.textlength(line, font=f_body)
        draw.text((cx - lw // 2, y), line, font=f_body, fill=(170, 178, 190))
        y += 32

    # Brand
    f_brand = load_font(22, bold=True)
    draw.text((cx - draw.textlength("wellBowled.ai", font=f_brand) // 2, OUT_H - 80), "wellBowled.ai", font=f_brand, fill=(*BRAND_TEAL, 200))

    return cv2.cvtColor(np.array(pil.convert("RGB")), cv2.COLOR_RGB2BGR)


def make_verdict_frames(bowling_frames, peak_sep, duration_s=5.0):
    """Generate animated verdict: skeleton plays in slo-mo behind frosted glass panel.

    Returns list of BGR frames.
    """
    target_count = int(OUTPUT_FPS * duration_s)
    frames_with_landmarks = [f for f in bowling_frames if f.get("landmarks")]
    if not frames_with_landmarks:
        frames_with_landmarks = bowling_frames

    result = []
    for i in range(target_count):
        # Loop through bowling frames slowly
        src_idx = i % len(frames_with_landmarks)
        f = frames_with_landmarks[src_idx]
        # Render skeleton on dark bg
        skel_frame = _draw_skeleton_frame(f.get("landmarks"), f["frame_bgr"])
        # Overlay frosted glass verdict panel
        verdict_frame = _draw_verdict_overlay(skel_frame, peak_sep)
        result.append(verdict_frame)

    return result


def make_title_card():
    """Opening title card — big, bright, zero wasted space."""
    pil = Image.new("RGB", (OUT_W, OUT_H), DARK_BG)
    draw = ImageDraw.Draw(pil)
    cx = OUT_W // 2

    y = OUT_H // 2 - 280

    # Hook — massive
    f_where = load_font(44)
    f_pace = load_font(96, bold=True)
    f_from = load_font(44)

    draw.text((cx - draw.textlength("Where does", font=f_where) // 2, y), "Where does", font=f_where, fill=WHITE)
    y += 60
    draw.text((cx - draw.textlength("PACE", font=f_pace) // 2, y), "PACE", font=f_pace, fill=ACCENT_RED)
    y += 110
    draw.text((cx - draw.textlength("come from?", font=f_from) // 2, y), "come from?", font=f_from, fill=WHITE)
    y += 90

    # Hip vs Shoulder — big colored labels
    f_vs = load_font(32, bold=True)
    f_label = load_font(28, bold=True)
    draw.ellipse((cx - 160, y + 4, cx - 140, y + 24), fill=HIP_COLOR)
    draw.text((cx - 132, y), "Hips", font=f_label, fill=HIP_COLOR)
    draw.text((cx - 20, y), "vs", font=f_vs, fill=(100, 110, 120))
    draw.ellipse((cx + 50, y + 4, cx + 70, y + 24), fill=SHOULDER_COLOR)
    draw.text((cx + 78, y), "Shoulders", font=f_label, fill=SHOULDER_COLOR)
    y += 70

    # Tagline
    f_tag = load_font(32)
    tag = "The bigger the gap,"
    draw.text((cx - draw.textlength(tag, font=f_tag) // 2, y), tag, font=f_tag, fill=(220, 228, 240))
    y += 42
    tag2 = "the faster the ball."
    draw.text((cx - draw.textlength(tag2, font=f_tag) // 2, y), tag2, font=f_tag, fill=(220, 228, 240))

    # Brand — luminous, prominent
    f_brand = load_font(36, bold=True)
    brand = "wellBowled.ai"
    bw = draw.textlength(brand, font=f_brand)
    # Glow effect: draw text slightly larger in teal with blur, then sharp on top
    for dx, dy in [(-1, -1), (-1, 1), (1, -1), (1, 1), (0, -2), (0, 2), (-2, 0), (2, 0)]:
        draw.text((cx - bw // 2 + dx, OUT_H - 120 + dy), brand, font=f_brand, fill=(0, 80, 90))
    draw.text((cx - bw // 2, OUT_H - 120), brand, font=f_brand, fill=BRAND_TEAL)

    return cv2.cvtColor(np.array(pil), cv2.COLOR_RGB2BGR)


def make_end_card():
    """End card — brand only, clean."""
    pil = Image.new("RGB", (OUT_W, OUT_H), (13, 17, 23))
    draw = ImageDraw.Draw(pil)
    cx = OUT_W // 2

    f_brand = load_font(80, bold=True)
    f_tag = load_font(32)

    brand = "wellBowled.ai"
    draw.text((cx - draw.textlength(brand, font=f_brand)//2, OUT_H//2 - 50), brand, font=f_brand, fill=BRAND_TEAL)

    tag = "Cricket biomechanics, visualized"
    draw.text((cx - draw.textlength(tag, font=f_tag)//2, OUT_H//2 + 50), tag, font=f_tag, fill=WHITE)

    return cv2.cvtColor(np.array(pil), cv2.COLOR_RGB2BGR)


# ─── Video Composition ───────────────────────────────────────────────────────

def current_phase(t, phases):
    if t < phases.get("back_foot_contact", 0): return "approach"
    if t < phases.get("front_foot_contact", 0): return "back foot contact"
    if t < phases.get("release", 0): return "front foot contact"
    if t < phases.get("follow_through", 999): return "release"
    return "follow through"


def compose_video(frames, peak_frame, phases, output_path, fps):
    """Compose the video: annotated slo-mo → freeze → verdict → end.

    No cold open prefix. Start directly with the bowling action analysis.
    Only frames within the bowling window (action_start → action_end) are included.
    """
    import logging
    log = logging.getLogger("compose")

    rendered = []
    peak_idx = peak_frame["index"] if peak_frame else -1
    peak_sep = peak_frame["separation"] if peak_frame else 0

    # Crop to ONLY the delivery stride: BFC → release + tiny buffer
    # No run-up. No follow-through. Just the X-factor moment.
    bfc = phases.get("back_foot_contact", 0)
    release = phases.get("release", phases.get("follow_through", frames[-1]["time"]))
    # End at peak X-factor frame + buffer
    # Ensure minimum 0.5s source footage (= 2s at 0.25x)
    peak_time = peak_frame["time"] if peak_frame else release
    clip_start = max(0, bfc - 0.1)  # tiny lead-in to see the stride begin
    clip_end = max(peak_time + 0.2, clip_start + 0.5)  # at least 0.5s source
    bowling_frames = [f for f in frames if clip_start <= f["time"] <= clip_end]
    if len(bowling_frames) < 5:
        bowling_frames = frames
        log.warning("Bowling window too narrow, using all frames")

    # Overlay on ALL frames in the clip (they're all delivery stride)
    log.info(f"Clip: {clip_start:.2f}s → {clip_end:.2f}s ({len(bowling_frames)} frames)")
    log.info(f"Peak: {peak_sep:.1f}° at frame {peak_idx}")

    # 0. Title card (3s) — explains what to watch for
    title = make_title_card()
    rendered.extend([title] * int(OUTPUT_FPS * 3))
    log.info("Title card: 3s")

    # 1. Slo-mo with overlays on every frame (clip IS the delivery stride)
    for f in bowling_frames:
        phase = current_phase(f["time"], phases)
        annotated = render_overlay(f["frame_bgr"], f["landmarks"], f["separation"], phase)
        canvas = fit_to_canvas(annotated)
        rendered.extend([canvas] * SLOW_FACTOR)

        # Freeze at peak
        if f["index"] == peak_idx:
            freeze = make_freeze_card(f["frame_bgr"], peak_sep)
            rendered.extend([freeze] * int(OUTPUT_FPS * 2.5))
            log.info(f"Freeze at t={f['time']:.2f}s, {peak_sep:.1f}°")

    log.info(f"Rendered {len(bowling_frames)} frames, all with overlays")

    # 2. Verdict — animated skeleton behind frosted glass panel (5s)
    verdict_frames = make_verdict_frames(bowling_frames, peak_sep, duration_s=5.0)
    rendered.extend(verdict_frames)
    log.info(f"Verdict: {len(verdict_frames)} frames ({len(verdict_frames)/OUTPUT_FPS:.1f}s)")

    # 3. End card (1.5s)
    end = make_end_card()
    rendered.extend([end] * int(OUTPUT_FPS * 1.5))
    log.info("End card: 1.5s")

    # Write raw MP4
    raw_path = output_path.replace(".mp4", "_raw.mp4")
    writer = cv2.VideoWriter(raw_path, cv2.VideoWriter_fourcc(*"mp4v"), OUTPUT_FPS, (OUT_W, OUT_H))
    for frame in rendered:
        writer.write(frame)
    writer.release()

    # FFmpeg re-encode for YouTube
    cmd = [
        "ffmpeg", "-y", "-i", raw_path,
        "-f", "lavfi", "-i", "anullsrc=r=44100:cl=stereo",
        "-map", "0:v:0", "-map", "1:a:0",
        "-c:v", "libx264", "-preset", "medium", "-crf", "17",
        "-pix_fmt", "yuv420p", "-movflags", "+faststart",
        "-shortest", "-c:a", "aac", "-b:a", "128k",
        output_path,
    ]
    subprocess.run(cmd, check=True, capture_output=True)
    Path(raw_path).unlink(missing_ok=True)
    return output_path


# ─── Main ────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="X-Factor v1.0.0 — bowling analysis video")
    parser.add_argument("input", help="Input bowling clip (MP4)")
    parser.add_argument("--output", default=None, help="Output path (default: xfactor_output.mp4)")
    parser.add_argument("--skip-gemini", action="store_true", help="Skip Gemini Flash call")
    parser.add_argument("--use-cache", default=None, help="Path to cached Flash JSON (skip API call)")
    args = parser.parse_args()

    input_path = Path(args.input).resolve()
    output_path = args.output or str(Path(__file__).parent / "output" / "xfactor_v100.mp4")
    Path(output_path).parent.mkdir(parents=True, exist_ok=True)

    print("=" * 50)
    print("  X-FACTOR v1.0.0")
    print("=" * 50)
    print(f"  Input:  {input_path}")
    print(f"  Output: {output_path}\n")

    # Stage 1: Gemini Flash (or cached response)
    bowler_roi = None
    flash_phases = None
    result = None
    if args.use_cache:
        t0 = time.time()
        print("[1/5] Loading cached Flash response...")
        with open(args.use_cache) as f:
            result = json.load(f)
        bowler_roi = result.get("delivery_roi") or result.get("bowler_roi")
        flash_phases = result.get("phases")
        print(f"  ROI: {bowler_roi}")
        print(f"  ({time.time()-t0:.2f}s)\n")
    elif not args.skip_gemini:
        t0 = time.time()
        print("[1/5] Gemini Flash — identifying bowler...")
        result = call_gemini_flash(str(input_path))
        if result:
            # Use bowler_roi (wider) for pose extraction — delivery_roi was too tight
            bowler_roi = result.get("bowler_roi")
            flash_phases = result.get("phases")
            action_start = result.get("action_start", 0)
            action_end = result.get("action_end")
            print(f"  ROI: {bowler_roi}")
            print(f"  Arm: {result.get('bowling_arm')}")
            print(f"  Action window: {action_start}s - {action_end}s")
        else:
            print("  Skipped — using heuristics")
        print(f"  ({time.time()-t0:.1f}s)\n")

    # Stage 2: Pose extraction
    t0 = time.time()
    print("[2/5] MediaPipe pose extraction...")
    data = extract_poses(str(input_path), bowler_roi)
    frames = data["frames"]
    fps = data["fps"]
    detected = sum(1 for f in frames if f["landmarks"])
    print(f"  {len(frames)} frames @ {fps:.0f}fps, bowler in {detected}/{len(frames)}")
    print(f"  ({time.time()-t0:.1f}s)\n")

    # Stage 3: X-factor computation
    t0 = time.time()
    print("[3/5] Computing X-factor...")
    frames = compute_xfactor(frames)
    peak = find_peak(frames)
    phases = flash_phases if flash_phases else detect_phases(frames)
    # Pass action_start through phases dict for cold open trimming
    if not args.skip_gemini and result:
        if result.get("action_start"):
            phases["_action_start"] = float(result["action_start"])
        if result.get("action_end"):
            phases["_action_end"] = float(result["action_end"])
    if peak:
        print(f"  Peak: {peak['separation']:.1f}° at {peak['time']:.2f}s")
    print(f"  Phases: {json.dumps({k: round(v, 2) for k, v in phases.items()})}")
    print(f"  ({time.time()-t0:.2f}s)\n")

    # Stage 4: Compose video
    t0 = time.time()
    print("[4/5] Composing video...")
    compose_video(frames, peak, phases, output_path, fps)
    print(f"  ({time.time()-t0:.1f}s)\n")

    # Stage 5: Verify
    print("[5/5] Verifying output...")
    probe = subprocess.run(
        ["ffprobe", "-v", "quiet", "-show_format", "-show_streams", output_path],
        capture_output=True, text=True
    )
    for line in probe.stdout.splitlines():
        if any(k in line for k in ["width=", "height=", "codec_name=h264", "duration=", "bit_rate="]):
            print(f"  {line.strip()}")

    size_mb = Path(output_path).stat().st_size / 1e6
    print(f"  Size: {size_mb:.1f}MB")
    print(f"\n  Output: {output_path}")
    print("=" * 50)

    # Extract review frames
    review_dir = Path(output_path).parent / "review"
    review_dir.mkdir(exist_ok=True)
    cap = cv2.VideoCapture(output_path)
    dur = cap.get(cv2.CAP_PROP_FRAME_COUNT) / cap.get(cv2.CAP_PROP_FPS)
    for pct in [0, 15, 30, 45, 60, 75, 90]:
        cap.set(cv2.CAP_PROP_POS_MSEC, int(dur * pct / 100 * 1000))
        ok, frame = cap.read()
        if ok:
            cv2.imwrite(str(review_dir / f"frame_{pct:02d}pct.png"), frame)
    cap.release()
    print(f"  Review frames: {review_dir}")


if __name__ == "__main__":
    main()
