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

# Comparison mode colors — muted, ~70% saturation, broadcast-style
COMP_HIP_BGR = (51, 133, 204)         # muted amber in BGR (204, 133, 51 RGB)
COMP_SHOULDER_BGR = (179, 179, 51)    # muted cyan in BGR (51, 179, 179 RGB)
COMP_KNEE_BGR = (102, 179, 102)       # muted green in BGR
COMP_ARM_BGR = (220, 220, 220)        # off-white in BGR
COMP_SPINE_BGR = (160, 150, 140)      # muted warm grey in BGR

# Skeleton connections (upper body + legs)
POSE_CONNECTIONS = [
    (11, 12), (11, 13), (13, 15), (12, 14), (14, 16),
    (11, 23), (12, 24), (23, 24), (23, 25), (25, 27), (24, 26), (26, 28),
]
PRIMARY_JOINTS = [11, 12, 13, 14, 15, 16, 23, 24, 25, 26, 27, 28]

LEFT_SHOULDER = 11
RIGHT_SHOULDER = 12
LEFT_ELBOW = 13
RIGHT_ELBOW = 14
LEFT_WRIST = 15
RIGHT_WRIST = 16
LEFT_HIP = 23
RIGHT_HIP = 24
LEFT_KNEE = 25
RIGHT_KNEE = 26
LEFT_ANKLE = 27
RIGHT_ANKLE = 28


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


def render_comparison_overlay(
    frame_bgr: np.ndarray,
    landmarks: list[tuple[float, float, float]] | None,
    draw_knee: bool = True,
    draw_arm: bool = True,
    draw_spine: bool = False,
    bowling_side: str = "left",
) -> np.ndarray:
    """Render clean comparison overlay — no pills, no legend, no numbers.

    Args:
        frame_bgr: source frame (BGR).
        landmarks: pose landmarks from extractor.
        draw_knee: draw front knee triangle.
        draw_arm: draw bowling arm path.
        draw_spine: draw spine line (mid-shoulder to mid-hip).
        bowling_side: "left" or "right" — which side landmarks represent
                      the bowling arm in this side-on view.

    Returns BGR frame with overlay.
    """
    h, w = frame_bgr.shape[:2]
    out = frame_bgr.copy()

    if landmarks is None:
        return out

    def px(idx: int, min_vis: float = 0.3) -> tuple[int, int] | None:
        p = landmarks[idx]
        if p[2] < min_vis:
            return None
        return (int(p[0] * w), int(p[1] * h))

    # Gate: core joints must be visible
    core = [LEFT_SHOULDER, RIGHT_SHOULDER, LEFT_HIP, RIGHT_HIP]
    if not all(landmarks[j][2] > 0.4 for j in core):
        return out

    # Faded skeleton background — very subtle, 25% opacity
    overlay_skel = out.copy()
    for a, b in POSE_CONNECTIONS:
        pa, pb = px(a), px(b)
        if pa and pb:
            cv2.line(overlay_skel, pa, pb, (140, 140, 140), 1, cv2.LINE_AA)
    cv2.addWeighted(overlay_skel, 0.25, out, 0.75, 0, out)

    # Hip line — muted amber
    lh, rh = px(LEFT_HIP), px(RIGHT_HIP)
    if lh and rh:
        ext_a, ext_b = _extend_line(lh, rh, 0.2)
        cv2.line(out, ext_a, ext_b, COMP_HIP_BGR, 3, cv2.LINE_AA)
        cv2.circle(out, lh, 5, COMP_HIP_BGR, -1, cv2.LINE_AA)
        cv2.circle(out, rh, 5, COMP_HIP_BGR, -1, cv2.LINE_AA)

    # Shoulder line — muted cyan
    ls, rs = px(LEFT_SHOULDER), px(RIGHT_SHOULDER)
    if ls and rs:
        ext_a, ext_b = _extend_line(ls, rs, 0.2)
        cv2.line(out, ext_a, ext_b, COMP_SHOULDER_BGR, 3, cv2.LINE_AA)
        cv2.circle(out, ls, 5, COMP_SHOULDER_BGR, -1, cv2.LINE_AA)
        cv2.circle(out, rs, 5, COMP_SHOULDER_BGR, -1, cv2.LINE_AA)

    # Front knee triangle
    if draw_knee:
        # Draw both legs, let the viewer see which is the front leg
        for hip_idx, knee_idx, ankle_idx in [
            (LEFT_HIP, LEFT_KNEE, LEFT_ANKLE),
            (RIGHT_HIP, RIGHT_KNEE, RIGHT_ANKLE),
        ]:
            ph = px(hip_idx, 0.4)
            pk = px(knee_idx, 0.4)
            pa = px(ankle_idx, 0.4)
            if ph and pk and pa:
                cv2.line(out, ph, pk, COMP_KNEE_BGR, 2, cv2.LINE_AA)
                cv2.line(out, pk, pa, COMP_KNEE_BGR, 2, cv2.LINE_AA)
                cv2.circle(out, pk, 4, COMP_KNEE_BGR, -1, cv2.LINE_AA)

    # Bowling arm path
    if draw_arm:
        if bowling_side == "left":
            s_idx, e_idx, w_idx = LEFT_SHOULDER, LEFT_ELBOW, LEFT_WRIST
        else:
            s_idx, e_idx, w_idx = RIGHT_SHOULDER, RIGHT_ELBOW, RIGHT_WRIST
        ps = px(s_idx, 0.4)
        pe = px(e_idx, 0.4)
        pw = px(w_idx, 0.4)
        if ps and pe:
            cv2.line(out, ps, pe, COMP_ARM_BGR, 2, cv2.LINE_AA)
            cv2.circle(out, pe, 4, COMP_ARM_BGR, -1, cv2.LINE_AA)
        if pe and pw:
            cv2.line(out, pe, pw, COMP_ARM_BGR, 2, cv2.LINE_AA)
            cv2.circle(out, pw, 4, COMP_ARM_BGR, -1, cv2.LINE_AA)

    # Spine line — mid-shoulder to mid-hip
    if draw_spine and ls and rs and lh and rh:
        mid_s = ((ls[0] + rs[0]) // 2, (ls[1] + rs[1]) // 2)
        mid_h = ((lh[0] + rh[0]) // 2, (lh[1] + rh[1]) // 2)
        cv2.line(out, mid_s, mid_h, COMP_SPINE_BGR, 2, cv2.LINE_AA)

    return out


def render_pulse_glow(
    frame_bgr: np.ndarray,
    landmarks: list[tuple[float, float, float]] | None,
    opacity: float = 0.4,
    bowling_side: str = "left",
) -> np.ndarray:
    """Apply a glow emphasis on the skeleton lines that differ most.

    This function owns the VISUAL STYLE only — which lines glow, what colour,
    what radius, what opacity for a single frame. The composer controls timing
    by calling this with varying opacity values across frames.

    Args:
        frame_bgr: frame with comparison overlay already rendered.
        landmarks: pose landmarks.
        opacity: glow intensity (0.0 = invisible, 1.0 = full).
        bowling_side: which side is the bowling arm.

    Returns BGR frame with glow applied.
    """
    if landmarks is None or opacity <= 0:
        return frame_bgr

    h, w = frame_bgr.shape[:2]
    glow_layer = np.zeros_like(frame_bgr)

    def px(idx: int) -> tuple[int, int] | None:
        p = landmarks[idx]
        if p[2] < 0.3:
            return None
        return (int(p[0] * w), int(p[1] * h))

    # Glow on hip and shoulder lines — these show the X-Factor difference most
    for p1_idx, p2_idx, color in [
        (LEFT_HIP, RIGHT_HIP, COMP_HIP_BGR),
        (LEFT_SHOULDER, RIGHT_SHOULDER, COMP_SHOULDER_BGR),
    ]:
        p1, p2 = px(p1_idx), px(p2_idx)
        if p1 and p2:
            ext_a, ext_b = _extend_line(p1, p2, 0.2)
            cv2.line(glow_layer, ext_a, ext_b, color, 8, cv2.LINE_AA)

    # Glow on bowling arm path
    if bowling_side == "left":
        s_idx, e_idx, w_idx = LEFT_SHOULDER, LEFT_ELBOW, LEFT_WRIST
    else:
        s_idx, e_idx, w_idx = RIGHT_SHOULDER, RIGHT_ELBOW, RIGHT_WRIST
    ps, pe, pw = px(s_idx), px(e_idx), px(w_idx)
    if ps and pe:
        cv2.line(glow_layer, ps, pe, COMP_ARM_BGR, 6, cv2.LINE_AA)
    if pe and pw:
        cv2.line(glow_layer, pe, pw, COMP_ARM_BGR, 6, cv2.LINE_AA)

    # Blur for glow effect
    glow_layer = cv2.GaussianBlur(glow_layer, (0, 0), sigmaX=6)

    # Blend at requested opacity
    out = frame_bgr.copy()
    mask = glow_layer.astype(np.float32) / 255.0 * opacity
    out = (out.astype(np.float32) + glow_layer.astype(np.float32) * opacity)
    out = np.clip(out, 0, 255).astype(np.uint8)

    return out


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
