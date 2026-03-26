"""Overlay renderer: hip/shoulder lines, skeleton, angle pill, phase label, legend.

ALL text rendered via Pillow with Liberation Sans fonts. NO cv2.putText.
Gate: all 4 x-factor joints (both hips, both shoulders) must be visible (>0.5)
to draw ANY overlay on a frame.
"""
from __future__ import annotations

import math
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFont

# ---------------------------------------------------------------------------
# Colours
# ---------------------------------------------------------------------------
HIP_COLOR_BGR = (180, 105, 255)        # #FF69B4 in BGR
SHOULDER_COLOR_BGR = (209, 206, 0)     # #00CED1 in BGR
HIP_COLOR_RGB = (255, 105, 180)
SHOULDER_COLOR_RGB = (0, 206, 209)
WHITE = (255, 255, 255)
BG_DARK = (10, 14, 20)                 # #0A0E14

# Skeleton connections (upper body + legs, no face/hands)
POSE_CONNECTIONS = [
    (11, 12), (11, 13), (13, 15), (12, 14), (14, 16),
    (11, 23), (12, 24), (23, 24), (23, 25), (25, 27), (24, 26), (26, 28),
]
PRIMARY_JOINTS = [11, 12, 13, 14, 15, 16, 23, 24, 25, 26, 27, 28]

LEFT_SHOULDER = 11
RIGHT_SHOULDER = 12
LEFT_HIP = 23
RIGHT_HIP = 24

XFACTOR_JOINTS = [LEFT_SHOULDER, RIGHT_SHOULDER, LEFT_HIP, RIGHT_HIP]


# ---------------------------------------------------------------------------
# Font helper (Linux paths)
# ---------------------------------------------------------------------------
_font_cache: dict[tuple[int, bool], ImageFont.FreeTypeFont | ImageFont.ImageFont] = {}


def _load_font(size: int, bold: bool = False):
    key = (size, bold)
    if key in _font_cache:
        return _font_cache[key]
    candidates = [
        "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf" if bold
        else "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf" if bold
        else "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    ]
    for c in candidates:
        if Path(c).exists():
            try:
                font = ImageFont.truetype(c, size=size)
                _font_cache[key] = font
                return font
            except OSError:
                pass
    font = ImageFont.load_default()
    _font_cache[key] = font
    return font


# ---------------------------------------------------------------------------
# Geometry helpers
# ---------------------------------------------------------------------------
def _extend_line(
    p1: tuple[int, int], p2: tuple[int, int], extend: float = 0.25,
) -> tuple[tuple[int, int], tuple[int, int]]:
    dx = p2[0] - p1[0]
    dy = p2[1] - p1[1]
    return (
        (int(p1[0] - dx * extend), int(p1[1] - dy * extend)),
        (int(p2[0] + dx * extend), int(p2[1] + dy * extend)),
    )


def _separation_color(separation: float) -> tuple[int, int, int]:
    """Color transitions: <15 grey, 15-30 yellow, 30-45 green, 45+ bright green."""
    if separation < 15:
        return (200, 200, 200)
    elif separation < 30:
        t = (separation - 15) / 15
        return (
            int(200 + t * 55),     # toward yellow
            int(200 + t * 20),
            int(200 * (1 - t) + 80 * t),
        )
    elif separation < 45:
        t = (separation - 30) / 15
        return (
            int(255 * (1 - t) + 100 * t),
            int(220 * (1 - t) + 255 * t),
            int(80 * (1 - t) + 100 * t),
        )
    else:
        return (100, 255, 100)


# ---------------------------------------------------------------------------
# Rendering
# ---------------------------------------------------------------------------
def render_frame_overlay(
    frame_bgr: np.ndarray,
    landmarks: list[tuple[float, float, float]] | None,
    separation: float | None,
    phase_label: str,
    canvas_w: int = 1080,
    canvas_h: int = 1920,
    y_offset: int = 0,
) -> np.ndarray:
    """Render X-factor overlay on a 9:16 canvas frame (BGR).

    y_offset: vertical offset from letterboxing, so overlays track the bowler.
    """
    h, w = frame_bgr.shape[:2]
    out = frame_bgr.copy()

    if landmarks is None:
        return out

    def px(idx: int) -> tuple[int, int] | None:
        p = landmarks[idx]
        if p[2] < 0.3:
            return None
        return (int(p[0] * w), int(p[1] * h))

    # Gate: ALL 4 x-factor joints must be clearly visible
    if not all(landmarks[j][2] > 0.5 for j in XFACTOR_JOINTS):
        return out

    # --- Skeleton (35% opacity, behind everything) ---
    overlay_skel = out.copy()
    for a, b in POSE_CONNECTIONS:
        pa, pb = px(a), px(b)
        if pa and pb:
            cv2.line(overlay_skel, pa, pb, (180, 180, 180), 1, cv2.LINE_AA)
    for jidx in PRIMARY_JOINTS:
        p = px(jidx)
        if p:
            cv2.circle(overlay_skel, p, 2, (200, 200, 200), -1, cv2.LINE_AA)
    cv2.addWeighted(overlay_skel, 0.35, out, 0.65, 0, out)

    # --- Hip line (pink, 4px, 25% extension, white-bordered dots) ---
    lh, rh = px(LEFT_HIP), px(RIGHT_HIP)
    if lh and rh:
        ext_a, ext_b = _extend_line(lh, rh, 0.25)
        cv2.line(out, ext_a, ext_b, HIP_COLOR_BGR, 4, cv2.LINE_AA)
        for pt in (lh, rh):
            cv2.circle(out, pt, 7, (255, 255, 255), 2, cv2.LINE_AA)
            cv2.circle(out, pt, 5, HIP_COLOR_BGR, -1, cv2.LINE_AA)

    # --- Shoulder line (cyan, 4px, 25% extension, white-bordered dots) ---
    ls, rs = px(LEFT_SHOULDER), px(RIGHT_SHOULDER)
    if ls and rs:
        ext_a, ext_b = _extend_line(ls, rs, 0.25)
        cv2.line(out, ext_a, ext_b, SHOULDER_COLOR_BGR, 4, cv2.LINE_AA)
        for pt in (ls, rs):
            cv2.circle(out, pt, 7, (255, 255, 255), 2, cv2.LINE_AA)
            cv2.circle(out, pt, 5, SHOULDER_COLOR_BGR, -1, cv2.LINE_AA)

    # --- Angle pill near torso (Pillow for anti-aliased text) ---
    if separation is not None and lh and rh and ls and rs:
        pil_img = Image.fromarray(cv2.cvtColor(out, cv2.COLOR_BGR2RGB))
        draw = ImageDraw.Draw(pil_img)
        font_angle = _load_font(32, bold=True)
        font_deg = _load_font(18, bold=False)

        mid_x = (lh[0] + rh[0] + ls[0] + rs[0]) // 4
        mid_y = (lh[1] + rh[1] + ls[1] + rs[1]) // 4
        color = _separation_color(separation)
        angle_text = f"{separation:.0f}"

        text_w = draw.textlength(angle_text, font=font_angle)
        deg_w = draw.textlength("\u00b0", font=font_deg)
        pill_w = int(text_w + deg_w + 24)
        pill_h = 44
        pill_x = mid_x - pill_w // 2
        pill_y = mid_y - pill_h // 2

        # Clamp to safe area
        pill_x = max(16, min(w - pill_w - 16, pill_x))
        pill_y = max(16, min(h - pill_h - 16, pill_y))

        draw.rounded_rectangle(
            (pill_x, pill_y, pill_x + pill_w, pill_y + pill_h),
            radius=14, fill=(10, 14, 20, 210),
        )
        draw.text((pill_x + 10, pill_y + 6), angle_text, font=font_angle, fill=color)
        draw.text(
            (pill_x + 10 + int(text_w) + 2, pill_y + 14),
            "\u00b0", font=font_deg, fill=color,
        )
        out = cv2.cvtColor(np.array(pil_img), cv2.COLOR_RGB2BGR)

    # --- Phase label pill (top center) ---
    pil_img = Image.fromarray(cv2.cvtColor(out, cv2.COLOR_BGR2RGB))
    draw = ImageDraw.Draw(pil_img)
    font_phase = _load_font(20, bold=True)
    label = phase_label.upper()
    tw = draw.textlength(label, font=font_phase)
    pill_w = int(tw + 28)
    pill_h = 36
    pill_x = w // 2 - pill_w // 2
    pill_y = max(16, int(h * 0.02))
    draw.rounded_rectangle(
        (pill_x, pill_y, pill_x + pill_w, pill_y + pill_h),
        radius=12, fill=(10, 14, 20, 200),
    )
    draw.text((pill_x + 14, pill_y + 8), label, font=font_phase, fill=WHITE)
    out = cv2.cvtColor(np.array(pil_img), cv2.COLOR_RGB2BGR)

    return out


def render_legend(frame_bgr: np.ndarray) -> np.ndarray:
    """Colour legend bar at the bottom (safe zone)."""
    h, w = frame_bgr.shape[:2]
    pil_img = Image.fromarray(cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2RGB))
    draw = ImageDraw.Draw(pil_img)
    font = _load_font(16, bold=True)

    bar_y = h - 50
    cx = w // 2

    # Background pill spanning both legend items
    total_w = 260
    draw.rounded_rectangle(
        (cx - total_w // 2, bar_y - 4, cx + total_w // 2, bar_y + 26),
        radius=10, fill=(10, 14, 20, 180),
    )

    # Hip legend
    draw.ellipse(
        (cx - total_w // 2 + 12, bar_y + 2, cx - total_w // 2 + 26, bar_y + 16),
        fill=HIP_COLOR_RGB,
    )
    draw.text((cx - total_w // 2 + 32, bar_y), "HIPS", font=font, fill=WHITE)

    # Shoulder legend
    draw.ellipse(
        (cx + 20, bar_y + 2, cx + 34, bar_y + 16),
        fill=SHOULDER_COLOR_RGB,
    )
    draw.text((cx + 40, bar_y), "SHOULDERS", font=font, fill=WHITE)

    return cv2.cvtColor(np.array(pil_img), cv2.COLOR_RGB2BGR)
