"""Stage 5: Render hip/shoulder line overlays on each frame."""
from __future__ import annotations

import json
import math
import os
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFont

OUTPUT_DIR = Path(__file__).resolve().parent / "output"
FRAMES_DIR = OUTPUT_DIR / "frames"
POSE_FILE = OUTPUT_DIR / "pose_data.json"
XFACTOR_FILE = OUTPUT_DIR / "xfactor_data.json"
ANNOTATED_DIR = OUTPUT_DIR / "annotated"

# Colors (BGR for OpenCV)
PINK_BGR = (180, 105, 255)   # #FF69B4
CYAN_BGR = (209, 206, 0)     # #00CED1
WHITE_BGR = (255, 255, 255)
DARK_BG = (23, 17, 13)       # #0D1117
SKELETON_COLOR = (255, 255, 255)

# Colors (RGB for Pillow)
PINK_RGB = (255, 105, 180)
CYAN_RGB = (0, 206, 209)
WHITE_RGB = (255, 255, 255)
GOLD_RGB = (255, 215, 0)

POSE_CONNECTIONS = [
    (11, 12), (11, 13), (13, 15), (12, 14), (14, 16),
    (11, 23), (12, 24), (23, 24), (23, 25), (25, 27),
    (24, 26), (26, 28),
]

L_HIP, R_HIP = 23, 24
L_SHOULDER, R_SHOULDER = 11, 12


def load_font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    candidates = []
    if bold:
        candidates.extend([
            "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
            "/System/Library/Fonts/Supplemental/Helvetica.ttc",
        ])
    candidates.extend([
        "/System/Library/Fonts/Supplemental/Arial.ttf",
        "/System/Library/Fonts/Supplemental/Helvetica.ttc",
    ])
    for c in candidates:
        if os.path.exists(c):
            try:
                return ImageFont.truetype(c, size=size)
            except OSError:
                continue
    return ImageFont.load_default()


def extend_line(p1: tuple[int, int], p2: tuple[int, int], extend_frac: float = 0.3) -> tuple[tuple[int, int], tuple[int, int]]:
    """Extend a line segment by extend_frac beyond each endpoint."""
    dx = p2[0] - p1[0]
    dy = p2[1] - p1[1]
    new_p1 = (int(p1[0] - dx * extend_frac), int(p1[1] - dy * extend_frac))
    new_p2 = (int(p2[0] + dx * extend_frac), int(p2[1] + dy * extend_frac))
    return new_p1, new_p2


def draw_skeleton(img: np.ndarray, landmarks: list[dict], alpha: float = 0.35):
    """Draw faded skeleton connections."""
    h, w = img.shape[:2]
    overlay = img.copy()
    for i1, i2 in POSE_CONNECTIONS:
        lm1, lm2 = landmarks[i1], landmarks[i2]
        if lm1["visibility"] < 0.3 or lm2["visibility"] < 0.3:
            continue
        pt1 = (int(lm1["x"] * w), int(lm1["y"] * h))
        pt2 = (int(lm2["x"] * w), int(lm2["y"] * h))
        cv2.line(overlay, pt1, pt2, SKELETON_COLOR, 2, cv2.LINE_AA)
    cv2.addWeighted(overlay, alpha, img, 1 - alpha, 0, img)


def draw_joint_dot(img: np.ndarray, landmark: dict, color: tuple, radius: int = 6):
    h, w = img.shape[:2]
    pt = (int(landmark["x"] * w), int(landmark["y"] * h))
    cv2.circle(img, pt, radius, color, -1, cv2.LINE_AA)
    cv2.circle(img, pt, radius, WHITE_BGR, 1, cv2.LINE_AA)


def draw_hip_shoulder_lines(img: np.ndarray, landmarks: list[dict]):
    """Draw extended hip line (pink) and shoulder line (cyan)."""
    h, w = img.shape[:2]

    lh = (int(landmarks[L_HIP]["x"] * w), int(landmarks[L_HIP]["y"] * h))
    rh = (int(landmarks[R_HIP]["x"] * w), int(landmarks[R_HIP]["y"] * h))
    ls = (int(landmarks[L_SHOULDER]["x"] * w), int(landmarks[L_SHOULDER]["y"] * h))
    rs = (int(landmarks[R_SHOULDER]["x"] * w), int(landmarks[R_SHOULDER]["y"] * h))

    # Extended lines
    h1, h2 = extend_line(lh, rh, 0.3)
    s1, s2 = extend_line(ls, rs, 0.3)

    cv2.line(img, h1, h2, PINK_BGR, 4, cv2.LINE_AA)
    cv2.line(img, s1, s2, CYAN_BGR, 4, cv2.LINE_AA)

    # Joint dots
    for pt in [lh, rh]:
        cv2.circle(img, pt, 6, PINK_BGR, -1, cv2.LINE_AA)
    for pt in [ls, rs]:
        cv2.circle(img, pt, 6, CYAN_BGR, -1, cv2.LINE_AA)


def render_frame_with_pillow(img: np.ndarray, separation: float, phase: str | None,
                              is_peak: bool, reliable: bool) -> np.ndarray:
    """Add text overlays using Pillow for better typography."""
    pil_img = Image.fromarray(cv2.cvtColor(img, cv2.COLOR_BGR2RGB))
    draw = ImageDraw.Draw(pil_img)
    w, h = pil_img.size

    font_angle = load_font(32, bold=True)
    font_phase = load_font(18, bold=False)
    font_peak = load_font(28, bold=True)

    # Phase label pill at top center
    if phase:
        label = phase.replace("_", " ")
        bbox = draw.textbbox((0, 0), label, font=font_phase)
        tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
        pill_x = (w - tw) // 2 - 14
        pill_y = 20
        draw.rounded_rectangle(
            [pill_x, pill_y, pill_x + tw + 28, pill_y + th + 12],
            radius=14, fill=(0, 0, 0, 200),
        )
        draw.text((pill_x + 14, pill_y + 6), label, fill=WHITE_RGB, font=font_phase)

    # Separation angle — bottom area, clear of action
    if separation is not None and reliable:
        angle_text = f"{separation:.0f}°"
        bbox = draw.textbbox((0, 0), angle_text, font=font_angle)
        tw = bbox[2] - bbox[0]
        ax = (w - tw) // 2
        ay = h - 80

        # Semi-transparent background pill
        draw.rounded_rectangle(
            [ax - 12, ay - 6, ax + tw + 12, ay + 40],
            radius=10, fill=(0, 0, 0, 180),
        )
        draw.text((ax, ay), angle_text, fill=WHITE_RGB, font=font_angle)

    # Peak X-Factor badge
    if is_peak and separation is not None:
        peak_text = f"PEAK X-FACTOR: {separation:.0f}°"
        bbox = draw.textbbox((0, 0), peak_text, font=font_peak)
        tw = bbox[2] - bbox[0]
        px = (w - tw) // 2 - 16
        py = h // 2 - 60

        # Glow effect: draw slightly larger text in gold behind
        for dx in range(-2, 3):
            for dy in range(-2, 3):
                draw.text((px + 16 + dx, py + 10 + dy), peak_text, fill=(255, 215, 0), font=font_peak)

        draw.rounded_rectangle(
            [px, py, px + tw + 32, py + 48],
            radius=12, fill=(0, 0, 0, 220), outline=GOLD_RGB, width=2,
        )
        draw.text((px + 16, py + 10), peak_text, fill=GOLD_RGB, font=font_peak)

    return cv2.cvtColor(np.array(pil_img), cv2.COLOR_RGB2BGR)


def run() -> int:
    ANNOTATED_DIR.mkdir(parents=True, exist_ok=True)

    pose_data = json.loads(POSE_FILE.read_text())
    xfactor_data = json.loads(XFACTOR_FILE.read_text())

    peak_idx = xfactor_data["peak_separation_frame"]
    xframes = {f["frame"]: f for f in xfactor_data["frames"]}

    rendered = 0
    for fd in pose_data:
        frame_path = FRAMES_DIR / fd["frame"]
        if not frame_path.exists():
            continue

        img = cv2.imread(str(frame_path))
        lm = fd.get("landmarks")
        xf = xframes.get(fd["frame"], {})
        sep = xf.get("separation")
        phase = xf.get("phase")
        reliable = xf.get("reliable", False)
        is_peak = xf.get("frame_index") == peak_idx

        if lm:
            # Draw skeleton first (faded)
            draw_skeleton(img, lm, alpha=0.35)
            # Draw hip and shoulder lines
            draw_hip_shoulder_lines(img, lm)

        # Add text overlays with Pillow
        img = render_frame_with_pillow(img, sep, phase, is_peak, reliable)

        out_path = ANNOTATED_DIR / fd["frame"]
        cv2.imwrite(str(out_path), img)
        rendered += 1

    print(f"  Rendered {rendered} annotated frames")
    return rendered


if __name__ == "__main__":
    count = run()
    print(f"Done: {count} frames in {ANNOTATED_DIR}")
