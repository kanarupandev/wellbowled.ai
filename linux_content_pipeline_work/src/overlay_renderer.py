"""Stage 5: Draw X-factor overlays on each frame."""
from __future__ import annotations

import math
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFont

# Colors (BGR for OpenCV, RGBA for Pillow)
HIP_COLOR_BGR = (180, 105, 255)       # hot pink in BGR
SHOULDER_COLOR_BGR = (209, 206, 0)     # cyan in BGR
HIP_COLOR_RGBA = (255, 105, 180, 255)  # hot pink
SHOULDER_COLOR_RGBA = (0, 206, 209, 255)  # dark turquoise
WHITE = (255, 255, 255)
BG_DARK = (10, 14, 20)

# Skeleton connections (upper body + legs)
POSE_CONNECTIONS = [
    (11, 12), (11, 13), (13, 15), (12, 14), (14, 16),
    (11, 23), (12, 24), (23, 24), (23, 25), (25, 27), (24, 26), (26, 28),
]
PRIMARY_JOINTS = [11, 12, 13, 14, 15, 16, 23, 24, 25, 26, 27, 28]

LEFT_SHOULDER = 11
RIGHT_SHOULDER = 12
LEFT_HIP = 23
RIGHT_HIP = 24


def _load_font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    candidates = []
    if bold:
        candidates = [
            "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
            "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
            "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
        ]
    else:
        candidates = [
            "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf",
            "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
            "/System/Library/Fonts/Supplemental/Arial.ttf",
        ]
    for c in candidates:
        if Path(c).exists():
            try:
                return ImageFont.truetype(c, size=size)
            except OSError:
                continue
    return ImageFont.load_default()


def _extend_line(p1: tuple[int, int], p2: tuple[int, int], extend: float = 0.3) -> tuple[tuple[int, int], tuple[int, int]]:
    """Extend a line segment beyond both endpoints by a fraction of its length."""
    dx = p2[0] - p1[0]
    dy = p2[1] - p1[1]
    return (
        (int(p1[0] - dx * extend), int(p1[1] - dy * extend)),
        (int(p2[0] + dx * extend), int(p2[1] + dy * extend)),
    )


def _separation_color(separation: float) -> tuple[int, int, int]:
    """Color that transitions: white → green → yellow → red based on separation."""
    if separation < 15:
        return (200, 200, 200)
    elif separation < 30:
        t = (separation - 15) / 15
        return (int(200 * (1 - t) + 100 * t), int(200 * (1 - t) + 255 * t), int(200 * (1 - t) + 100 * t))
    elif separation < 45:
        t = (separation - 30) / 15
        return (int(100 * (1 - t) + 255 * t), int(255 * (1 - t) + 220 * t), int(100 * (1 - t)))
    else:
        return (255, 80, 60)


def render_frame_overlay(
    frame_bgr: np.ndarray,
    landmarks: list[tuple[float, float, float]] | None,
    separation: float | None,
    phase_label: str,
    is_peak: bool = False,
    peak_separation: float | None = None,
) -> np.ndarray:
    """Render X-factor overlay onto a single frame. Returns BGR frame."""
    h, w = frame_bgr.shape[:2]
    out = frame_bgr.copy()

    if landmarks is None:
        return out

    def px(idx: int) -> tuple[int, int] | None:
        p = landmarks[idx]
        if p[2] < 0.3:
            return None
        return (int(p[0] * w), int(p[1] * h))

    # Gate: ALL four x-factor joints must be clearly visible to draw anything
    xfactor_joints = [LEFT_SHOULDER, RIGHT_SHOULDER, LEFT_HIP, RIGHT_HIP]
    xfactor_visible = all(landmarks[j][2] > 0.5 for j in xfactor_joints)
    if not xfactor_visible:
        return out  # raw frame, no overlays — don't draw noise

    # Draw faded skeleton first (behind everything) — subtle, 35% opacity
    overlay_skel = out.copy()
    for a, b in POSE_CONNECTIONS:
        pa, pb = px(a), px(b)
        if pa and pb:
            cv2.line(overlay_skel, pa, pb, (180, 180, 180), 1, cv2.LINE_AA)
    for idx in PRIMARY_JOINTS:
        p = px(idx)
        if p:
            cv2.circle(overlay_skel, p, 2, (200, 200, 200), -1, cv2.LINE_AA)
    cv2.addWeighted(overlay_skel, 0.35, out, 0.65, 0, out)

    # Hip line (pink) — extended
    lh, rh = px(LEFT_HIP), px(RIGHT_HIP)
    if lh and rh:
        ext_a, ext_b = _extend_line(lh, rh, 0.25)
        cv2.line(out, ext_a, ext_b, HIP_COLOR_BGR, 4, cv2.LINE_AA)
        cv2.circle(out, lh, 7, (255, 255, 255), 2, cv2.LINE_AA)  # white border
        cv2.circle(out, lh, 5, HIP_COLOR_BGR, -1, cv2.LINE_AA)
        cv2.circle(out, rh, 7, (255, 255, 255), 2, cv2.LINE_AA)
        cv2.circle(out, rh, 5, HIP_COLOR_BGR, -1, cv2.LINE_AA)

    # Shoulder line (cyan) — extended
    ls, rs = px(LEFT_SHOULDER), px(RIGHT_SHOULDER)
    if ls and rs:
        ext_a, ext_b = _extend_line(ls, rs, 0.25)
        cv2.line(out, ext_a, ext_b, SHOULDER_COLOR_BGR, 4, cv2.LINE_AA)
        cv2.circle(out, ls, 7, (255, 255, 255), 2, cv2.LINE_AA)
        cv2.circle(out, ls, 5, SHOULDER_COLOR_BGR, -1, cv2.LINE_AA)
        cv2.circle(out, rs, 7, (255, 255, 255), 2, cv2.LINE_AA)
        cv2.circle(out, rs, 5, SHOULDER_COLOR_BGR, -1, cv2.LINE_AA)

    # Separation angle display at spine midpoint
    if separation is not None and lh and rh and ls and rs:
        mid_x = (lh[0] + rh[0] + ls[0] + rs[0]) // 4
        mid_y = (lh[1] + rh[1] + ls[1] + rs[1]) // 4
        color = _separation_color(separation)
        angle_text = f"{separation:.0f}"

        # Draw with Pillow for antialiased text
        pil_img = Image.fromarray(cv2.cvtColor(out, cv2.COLOR_BGR2RGB))
        draw = ImageDraw.Draw(pil_img)
        font_angle = _load_font(32, bold=True)
        font_deg = _load_font(18, bold=False)

        # Background pill for angle
        text_w = draw.textlength(angle_text, font=font_angle)
        deg_w = draw.textlength("\u00b0", font=font_deg)
        pill_w = int(text_w + deg_w + 24)
        pill_h = 44
        pill_x = mid_x - pill_w // 2
        pill_y = mid_y - pill_h // 2
        draw.rounded_rectangle(
            (pill_x, pill_y, pill_x + pill_w, pill_y + pill_h),
            radius=14, fill=(10, 14, 20, 210),
        )
        draw.text((pill_x + 10, pill_y + 6), angle_text, font=font_angle, fill=color)
        draw.text((pill_x + 10 + int(text_w) + 2, pill_y + 14), "\u00b0", font=font_deg, fill=color)

        out = cv2.cvtColor(np.array(pil_img), cv2.COLOR_RGB2BGR)

    # Phase label pill (top center) — use Pillow
    pil_img = Image.fromarray(cv2.cvtColor(out, cv2.COLOR_BGR2RGB))
    draw = ImageDraw.Draw(pil_img)
    font_phase = _load_font(18, bold=True)
    label = phase_label.upper()
    tw = draw.textlength(label, font=font_phase)
    pill_w = int(tw + 28)
    pill_h = 32
    pill_x = w // 2 - pill_w // 2
    pill_y = 16
    draw.rounded_rectangle(
        (pill_x, pill_y, pill_x + pill_w, pill_y + pill_h),
        radius=12, fill=(10, 14, 20, 200),
    )
    draw.text((pill_x + 14, pill_y + 7), label, font=font_phase, fill=WHITE)

    # Peak badge — removed; the freeze card handles this

    out = cv2.cvtColor(np.array(pil_img), cv2.COLOR_RGB2BGR)
    return out


def render_legend(frame_bgr: np.ndarray) -> np.ndarray:
    """Add a color legend bar at the bottom of a frame."""
    h, w = frame_bgr.shape[:2]
    pil_img = Image.fromarray(cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2RGB))
    draw = ImageDraw.Draw(pil_img)
    font = _load_font(14, bold=True)

    bar_y = h - 30
    # Hip legend
    draw.rounded_rectangle((20, bar_y, 110, bar_y + 22), radius=8, fill=(10, 14, 20, 180))
    draw.ellipse((26, bar_y + 5, 38, bar_y + 17), fill=HIP_COLOR_RGBA[:3])
    draw.text((44, bar_y + 3), "HIPS", font=font, fill=WHITE)

    # Shoulder legend
    draw.rounded_rectangle((120, bar_y, 240, bar_y + 22), radius=8, fill=(10, 14, 20, 180))
    draw.ellipse((126, bar_y + 5, 138, bar_y + 17), fill=SHOULDER_COLOR_RGBA[:3])
    draw.text((144, bar_y + 3), "SHOULDERS", font=font, fill=WHITE)

    return cv2.cvtColor(np.array(pil_img), cv2.COLOR_RGB2BGR)
