#!/usr/bin/env python3
"""Phase Portrait Pipeline — angle-angle coordination signature loop.

Plots hip angle vs shoulder angle as a parametric curve that draws itself
during delivery. Elite bowlers trace tight loops; amateurs trace chaos.
Based on Hamill et al. 2014 (Continuous Relative Phase).
"""
from __future__ import annotations

import json
import math
import os
import subprocess
import tempfile
import urllib.request
from pathlib import Path

import cv2
import mediapipe as mp
import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy.signal import savgol_filter

# ── Paths ──────────────────────────────────────────────────────────────
ROOT = Path(__file__).resolve().parents[2]
INPUT_CLIP = ROOT / "resources" / "samples" / "3_sec_1_delivery_nets.mp4"
OUTPUT_DIR = Path(__file__).resolve().parent / "output"
FRAMES_DIR = OUTPUT_DIR / "frames"
ANNOTATED_DIR = OUTPUT_DIR / "annotated"
MODEL_PATH = Path(__file__).resolve().parent / "pose_landmarker_heavy.task"
MODEL_URL = "https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_heavy/float16/latest/pose_landmarker_heavy.task"

OUT_W, OUT_H = 1080, 1920
FPS = 30
DARK_BG = (13, 17, 23)
PEACOCK = (0, 109, 119)
WHITE = (255, 255, 255)
EXTRACT_FPS = 10
DT = 1.0 / EXTRACT_FPS

# Landmarks
L_SHOULDER, R_SHOULDER = 11, 12
L_HIP, R_HIP = 23, 24
L_KNEE, R_KNEE = 25, 26
L_ELBOW, R_ELBOW = 13, 14
R_WRIST = 16

POSE_CONNECTIONS = [
    (11, 12), (11, 13), (13, 15), (12, 14), (14, 16),
    (11, 23), (12, 24), (23, 24), (23, 25), (25, 27),
    (24, 26), (26, 28),
]

DELIVERY_START = 2
DELIVERY_END_DEFAULT = 25

# Phase portrait axes — two joint angles that reveal coordination
# X-axis: Hip rotation (shoulder-hip line angle from horizontal)
# Y-axis: Bowling arm angle (shoulder-elbow-wrist)
TRAIL_COLOR_START = (0, 150, 255)   # warm orange (BGR)
TRAIL_COLOR_END = (255, 0, 255)     # magenta (BGR)
TRAIL_COLOR_START_RGB = (255, 150, 0)
TRAIL_COLOR_END_RGB = (255, 0, 255)

# Portrait plot layout
PLOT_LEFT = 80
PLOT_RIGHT = OUT_W - 60
PLOT_TOP = int(OUT_H * 0.60)
PLOT_BOTTOM = OUT_H - 100
PLOT_W = PLOT_RIGHT - PLOT_LEFT
PLOT_H = PLOT_BOTTOM - PLOT_TOP


def load_font(size: int, bold: bool = False):
    candidates = ["/System/Library/Fonts/Supplemental/Arial Bold.ttf"] if bold else []
    candidates += ["/System/Library/Fonts/Supplemental/Arial.ttf",
                   "/System/Library/Fonts/Supplemental/Helvetica.ttc"]
    for c in candidates:
        if os.path.exists(c):
            try:
                return ImageFont.truetype(c, size=size)
            except OSError:
                continue
    return ImageFont.load_default()


def angle_between(a: tuple, b: tuple, c: tuple) -> float:
    """Angle at point b formed by a→b→c, in degrees."""
    ba = (a[0] - b[0], a[1] - b[1])
    bc = (c[0] - b[0], c[1] - b[1])
    dot = ba[0] * bc[0] + ba[1] * bc[1]
    mag_ba = math.sqrt(ba[0]**2 + ba[1]**2)
    mag_bc = math.sqrt(bc[0]**2 + bc[1]**2)
    if mag_ba * mag_bc == 0:
        return 0
    cos_angle = max(-1, min(1, dot / (mag_ba * mag_bc)))
    return math.degrees(math.acos(cos_angle))


def lerp_color(c1: tuple, c2: tuple, t: float) -> tuple:
    """Linear interpolate between two BGR colors."""
    return tuple(int(c1[i] + (c2[i] - c1[i]) * t) for i in range(3))


def lerp_color_rgb(c1: tuple, c2: tuple, t: float) -> tuple:
    return tuple(int(c1[i] + (c2[i] - c1[i]) * t) for i in range(3))


# ── Stage 1: Extract frames ───────────────────────────────────────────
def extract_frames() -> tuple[list[Path], dict]:
    FRAMES_DIR.mkdir(parents=True, exist_ok=True)
    probe = subprocess.run(
        ["ffprobe", "-v", "quiet", "-print_format", "json", "-show_streams", str(INPUT_CLIP)],
        capture_output=True, text=True, check=True,
    )
    vs = next(s for s in json.loads(probe.stdout)["streams"] if s["codec_type"] == "video")
    meta = {"fps": eval(vs["r_frame_rate"]), "duration": float(vs["duration"]),
            "nb_frames": int(vs["nb_frames"])}
    subprocess.run(
        ["ffmpeg", "-y", "-i", str(INPUT_CLIP), "-vf", f"fps={EXTRACT_FPS}", "-q:v", "2",
         str(FRAMES_DIR / "f_%04d.jpg")],
        capture_output=True, check=True,
    )
    frames = sorted(FRAMES_DIR.glob("f_*.jpg"))
    meta["extracted"] = len(frames)
    print(f"  [1] Extracted {len(frames)} frames at {EXTRACT_FPS}fps")
    return frames, meta


# ── Stage 2: Pose extraction (centroid tracking) ─────────────────────
def extract_all_poses(frames: list[Path]) -> list[dict]:
    if not MODEL_PATH.exists():
        print("  Downloading pose model...")
        urllib.request.urlretrieve(MODEL_URL, MODEL_PATH)

    options = mp.tasks.vision.PoseLandmarkerOptions(
        base_options=mp.tasks.BaseOptions(model_asset_path=str(MODEL_PATH)),
        num_poses=2,
        min_pose_detection_confidence=0.4,
    )

    results = []
    prev_centroid = None

    with mp.tasks.vision.PoseLandmarker.create_from_options(options) as landmarker:
        for frame_path in frames:
            img = cv2.imread(str(frame_path))
            rgb = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
            mp_img = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)
            result = landmarker.detect(mp_img)

            entry = {"frame": frame_path.name, "path": str(frame_path), "landmarks": None}

            if result.pose_landmarks:
                candidates = []
                for pi, pose_lms in enumerate(result.pose_landmarks):
                    vis_lms = [(lm.x, lm.y) for lm in pose_lms if lm.visibility > 0.3]
                    if not vis_lms:
                        continue
                    xs, ys = zip(*vis_lms)
                    cx, cy = sum(xs) / len(xs), sum(ys) / len(ys)
                    size = (max(xs) - min(xs)) * (max(ys) - min(ys))
                    candidates.append({"idx": pi, "cx": cx, "cy": cy, "size": size})

                if candidates:
                    if prev_centroid is None:
                        best = max(candidates, key=lambda c: c["size"])
                    else:
                        best = min(candidates, key=lambda c:
                                   (c["cx"] - prev_centroid[0])**2 +
                                   (c["cy"] - prev_centroid[1])**2)
                    prev_centroid = (best["cx"], best["cy"])
                    entry["landmarks"] = [
                        {"x": lm.x, "y": lm.y, "z": lm.z, "vis": lm.visibility}
                        for lm in result.pose_landmarks[best["idx"]]
                    ]
            results.append(entry)

    detected = sum(1 for r in results if r["landmarks"])
    print(f"  [2] Pose: {detected}/{len(frames)}")
    return results


# ── Stage 3: Compute phase portrait angles ───────────────────────────
def compute_portrait_angles(pose_data: list[dict]) -> dict:
    n = len(pose_data)
    delivery_end = min(DELIVERY_END_DEFAULT, n - 1)

    # Two angles for the phase portrait:
    # Angle A (X-axis): Trunk rotation — angle of shoulder line from horizontal
    #   atan2(R_SHOULDER.y - L_SHOULDER.y, R_SHOULDER.x - L_SHOULDER.x)
    # Angle B (Y-axis): Bowling arm angle — shoulder-elbow-wrist
    angle_a_raw = []  # trunk rotation
    angle_b_raw = []  # bowling arm

    for fi in range(n):
        lm = pose_data[fi].get("landmarks")
        if lm is None:
            angle_a_raw.append(float("nan"))
            angle_b_raw.append(float("nan"))
            continue

        # Trunk rotation
        if lm[L_SHOULDER]["vis"] > 0.3 and lm[R_SHOULDER]["vis"] > 0.3:
            dx = lm[R_SHOULDER]["x"] - lm[L_SHOULDER]["x"]
            dy = lm[R_SHOULDER]["y"] - lm[L_SHOULDER]["y"]
            angle_a_raw.append(math.degrees(math.atan2(dy, dx)))
        else:
            angle_a_raw.append(float("nan"))

        # Bowling arm angle (R_SHOULDER → R_ELBOW → R_WRIST)
        if all(lm[i]["vis"] > 0.3 for i in [R_SHOULDER, R_ELBOW, R_WRIST]):
            s = (lm[R_SHOULDER]["x"], lm[R_SHOULDER]["y"])
            e = (lm[R_ELBOW]["x"], lm[R_ELBOW]["y"])
            w = (lm[R_WRIST]["x"], lm[R_WRIST]["y"])
            angle_b_raw.append(angle_between(s, e, w))
        else:
            angle_b_raw.append(float("nan"))

    # Interpolate NaN gaps and smooth
    angle_a = np.array(angle_a_raw, dtype=float)
    angle_b = np.array(angle_b_raw, dtype=float)

    for arr in [angle_a, angle_b]:
        valid = ~np.isnan(arr)
        if valid.sum() >= 3:
            indices = np.arange(len(arr))
            arr[~valid] = np.interp(indices[~valid], indices[valid], arr[valid])
            wl = min(7, len(arr))
            if wl % 2 == 0:
                wl -= 1
            if wl >= 3:
                arr[:] = savgol_filter(arr, window_length=wl, polyorder=2)

    # Compute ranges for the delivery zone (for axis scaling)
    d_a = angle_a[DELIVERY_START:delivery_end + 1]
    d_b = angle_b[DELIVERY_START:delivery_end + 1]

    a_min, a_max = float(np.nanmin(d_a)), float(np.nanmax(d_a))
    b_min, b_max = float(np.nanmin(d_b)), float(np.nanmax(d_b))

    # Add 10% padding
    a_pad = (a_max - a_min) * 0.15
    b_pad = (b_max - b_min) * 0.15
    a_min -= a_pad
    a_max += a_pad
    b_min -= b_pad
    b_max += b_pad

    # Compute loop "tightness" — average distance from centroid normalized by range
    centroid_a = float(np.nanmean(d_a))
    centroid_b = float(np.nanmean(d_b))
    distances = []
    for fi in range(DELIVERY_START, delivery_end + 1):
        da = (angle_a[fi] - centroid_a) / max(a_max - a_min, 1)
        db = (angle_b[fi] - centroid_b) / max(b_max - b_min, 1)
        distances.append(math.sqrt(da**2 + db**2))
    tightness = 1.0 - min(np.std(distances) * 4, 1.0)  # 0=chaotic, 1=tight

    print(f"  [3] Trunk rotation: {a_min:.0f}° to {a_max:.0f}°")
    print(f"  [3] Arm angle: {b_min:.0f}° to {b_max:.0f}°")
    print(f"  [3] Loop tightness: {tightness:.2f} ({'tight' if tightness > 0.5 else 'spread'})")

    return {
        "angle_a": angle_a.tolist(),
        "angle_b": angle_b.tolist(),
        "a_min": a_min, "a_max": a_max,
        "b_min": b_min, "b_max": b_max,
        "tightness": tightness,
        "delivery_end": delivery_end,
    }


# ── Stage 4: Render phase portrait frames ────────────────────────────
def angle_to_plot_px(a_val: float, b_val: float, data: dict) -> tuple[int, int]:
    t_a = (a_val - data["a_min"]) / max(data["a_max"] - data["a_min"], 1)
    t_b = (b_val - data["b_min"]) / max(data["b_max"] - data["b_min"], 1)
    px_x = PLOT_LEFT + int(t_a * PLOT_W)
    px_y = PLOT_BOTTOM - int(t_b * PLOT_H)  # invert Y
    return (px_x, px_y)


def render_portrait_frames(pose_data: list[dict], portrait_data: dict) -> list[np.ndarray]:
    ANNOTATED_DIR.mkdir(parents=True, exist_ok=True)
    delivery_end = portrait_data["delivery_end"]
    angle_a = portrait_data["angle_a"]
    angle_b = portrait_data["angle_b"]
    all_canvases = []

    for fi, pd in enumerate(pose_data):
        img = cv2.imread(pd["path"])
        h, w = img.shape[:2]
        lm = pd.get("landmarks")

        # Video in top 56%
        scale = min(OUT_W / w, (OUT_H * 0.54) / h)
        new_w, new_h = int(w * scale), int(h * scale)
        x_off = (OUT_W - new_w) // 2
        y_off = 80

        canvas = np.zeros((OUT_H, OUT_W, 3), dtype=np.uint8)
        canvas[:] = DARK_BG[::-1]
        resized = cv2.resize(img, (new_w, new_h), interpolation=cv2.INTER_LANCZOS4)
        canvas[y_off:y_off + new_h, x_off:x_off + new_w] = resized

        in_delivery = DELIVERY_START <= fi <= delivery_end

        if lm and in_delivery:
            def px(idx):
                return (x_off + int(lm[idx]["x"] * new_w),
                        y_off + int(lm[idx]["y"] * new_h))
            def vis(idx):
                return lm[idx]["vis"]

            # Faded skeleton
            overlay = canvas.copy()
            for j1, j2 in POSE_CONNECTIONS:
                if vis(j1) < 0.3 or vis(j2) < 0.3:
                    continue
                cv2.line(overlay, px(j1), px(j2), (180, 180, 180), 2, cv2.LINE_AA)
            cv2.addWeighted(overlay, 0.3, canvas, 0.7, 0, canvas)

            # Highlight the two angle joints
            # Shoulder line (trunk rotation)
            if vis(L_SHOULDER) > 0.3 and vis(R_SHOULDER) > 0.3:
                cv2.line(canvas, px(L_SHOULDER), px(R_SHOULDER),
                         (0, 200, 255), 4, cv2.LINE_AA)  # orange
                cv2.circle(canvas, px(L_SHOULDER), 6, (0, 200, 255), -1, cv2.LINE_AA)
                cv2.circle(canvas, px(R_SHOULDER), 6, (0, 200, 255), -1, cv2.LINE_AA)

            # Bowling arm
            if all(vis(i) > 0.3 for i in [R_SHOULDER, R_ELBOW, R_WRIST]):
                cv2.line(canvas, px(R_SHOULDER), px(R_ELBOW),
                         (255, 0, 200), 4, cv2.LINE_AA)  # pink
                cv2.line(canvas, px(R_ELBOW), px(R_WRIST),
                         (255, 0, 200), 4, cv2.LINE_AA)
                cv2.circle(canvas, px(R_ELBOW), 6, (255, 0, 200), -1, cv2.LINE_AA)

        # ── Draw phase portrait plot ──────────────────────────────
        sep_y = PLOT_TOP - 20
        cv2.line(canvas, (40, sep_y), (OUT_W - 40, sep_y), (40, 44, 50), 1, cv2.LINE_AA)

        # Grid
        for frac in [0.0, 0.25, 0.5, 0.75, 1.0]:
            gy = PLOT_BOTTOM - int(frac * PLOT_H)
            cv2.line(canvas, (PLOT_LEFT, gy), (PLOT_RIGHT, gy), (30, 33, 40), 1, cv2.LINE_AA)
            gx = PLOT_LEFT + int(frac * PLOT_W)
            cv2.line(canvas, (gx, PLOT_TOP), (gx, PLOT_BOTTOM), (30, 33, 40), 1, cv2.LINE_AA)

        # Axes
        cv2.line(canvas, (PLOT_LEFT, PLOT_BOTTOM), (PLOT_RIGHT, PLOT_BOTTOM),
                 (60, 65, 75), 1, cv2.LINE_AA)
        cv2.line(canvas, (PLOT_LEFT, PLOT_TOP), (PLOT_LEFT, PLOT_BOTTOM),
                 (60, 65, 75), 1, cv2.LINE_AA)

        # Draw trail progressively
        show_plot = in_delivery or fi > delivery_end
        if show_plot:
            draw_end = min(fi, delivery_end)
            total_delivery = delivery_end - DELIVERY_START

            # Draw the full trail up to current frame with gradient color
            for fj in range(DELIVERY_START, draw_end):
                t1 = (fj - DELIVERY_START) / max(total_delivery, 1)
                t2 = (fj + 1 - DELIVERY_START) / max(total_delivery, 1)

                p1 = angle_to_plot_px(angle_a[fj], angle_b[fj], portrait_data)
                p2 = angle_to_plot_px(angle_a[fj + 1], angle_b[fj + 1], portrait_data)
                color = lerp_color(TRAIL_COLOR_START, TRAIL_COLOR_END, t1)

                # Glow layer
                glow = canvas.copy()
                cv2.line(glow, p1, p2, color, 8, cv2.LINE_AA)
                glow_blurred = cv2.GaussianBlur(glow, (7, 7), 0)
                cv2.addWeighted(glow_blurred, 0.2, canvas, 0.8, 0, canvas)

                # Main line
                cv2.line(canvas, p1, p2, color, 3, cv2.LINE_AA)

            # Current position dot (pulsing)
            if in_delivery and fi <= delivery_end:
                cur_pos = angle_to_plot_px(angle_a[fi], angle_b[fi], portrait_data)
                t_cur = (fi - DELIVERY_START) / max(total_delivery, 1)
                cur_color = lerp_color(TRAIL_COLOR_START, TRAIL_COLOR_END, t_cur)
                # Outer glow
                cv2.circle(canvas, cur_pos, 12, cur_color, 2, cv2.LINE_AA)
                # Inner dot
                cv2.circle(canvas, cur_pos, 6, cur_color, -1, cv2.LINE_AA)
                cv2.circle(canvas, cur_pos, 6, WHITE, 1, cv2.LINE_AA)

            # Start marker
            start_pos = angle_to_plot_px(angle_a[DELIVERY_START], angle_b[DELIVERY_START],
                                          portrait_data)
            cv2.circle(canvas, start_pos, 8, TRAIL_COLOR_START, -1, cv2.LINE_AA)
            cv2.circle(canvas, start_pos, 8, WHITE, 2, cv2.LINE_AA)

        # ── Text overlays ─────────────────────────────────────────
        pil = Image.fromarray(cv2.cvtColor(canvas, cv2.COLOR_BGR2RGB))
        draw = ImageDraw.Draw(pil)

        font_title = load_font(34, bold=True)
        font_label = load_font(15, bold=False)
        font_small = load_font(13, bold=False)
        font_brand = load_font(20, bold=True)
        font_axis = load_font(14, bold=True)

        # Title
        title = "PHASE PORTRAIT"
        bbox = draw.textbbox((0, 0), title, font=font_title)
        tw = bbox[2] - bbox[0]
        draw.text(((OUT_W - tw) // 2, 20), title, fill=WHITE, font=font_title)

        # Subtitle
        sub = "Coordination Signature"
        bbox = draw.textbbox((0, 0), sub, font=font_label)
        sw = bbox[2] - bbox[0]
        draw.text(((OUT_W - sw) // 2, 56), sub, fill=(140, 140, 140), font=font_label)

        # Axis labels
        draw.text((PLOT_LEFT + PLOT_W // 2 - 50, PLOT_BOTTOM + 8),
                   "Trunk Rotation °", fill=(140, 140, 140), font=font_axis)
        # Y-axis (vertical text)
        draw.text((10, PLOT_TOP + PLOT_H // 2 - 30), "A\nR\nM\n°",
                   fill=(140, 140, 140), font=font_small)

        # Color legend: gradient bar
        legend_y = PLOT_BOTTOM + 35
        draw.text((PLOT_LEFT, legend_y), "START", fill=TRAIL_COLOR_START_RGB, font=font_small)
        draw.text((PLOT_RIGHT - 60, legend_y), "RELEASE", fill=TRAIL_COLOR_END_RGB, font=font_small)

        # Tightness badge
        if show_plot:
            tightness = portrait_data["tightness"]
            if tightness > 0.6:
                verdict = "TIGHT LOOP"
                v_color = (0, 200, 0)
            elif tightness > 0.35:
                verdict = "MODERATE"
                v_color = (255, 200, 0)
            else:
                verdict = "SCATTERED"
                v_color = (220, 80, 80)
            draw.text((PLOT_LEFT + PLOT_W // 2 - 40, PLOT_TOP - 35),
                       f"{verdict} ({tightness:.0%})", fill=v_color, font=font_label)

        # Time
        time_s = fi / EXTRACT_FPS
        draw.text((OUT_W - 100, PLOT_BOTTOM + 35), f"{time_s:.1f}s",
                   fill=(120, 120, 120), font=font_label)

        # Brand
        draw.text((OUT_W - 180, OUT_H - 45), "wellBowled.ai", fill=PEACOCK, font=font_brand)

        canvas = cv2.cvtColor(np.array(pil), cv2.COLOR_RGB2BGR)
        cv2.imwrite(str(ANNOTATED_DIR / pd["frame"]), canvas, [cv2.IMWRITE_JPEG_QUALITY, 95])
        all_canvases.append(canvas)

    print(f"  [4] Rendered {len(all_canvases)} portrait frames")
    return all_canvases


# ── Stage 5: Compose video ────────────────────────────────────────────
def compose_video(canvases: list[np.ndarray], portrait_data: dict) -> Path:
    final_path = OUTPUT_DIR / "portrait.mp4"
    delivery_end = portrait_data["delivery_end"]
    all_frames = []

    # Segment 1: Raw intro (1.5s)
    raw_frames = sorted(FRAMES_DIR.glob("f_*.jpg"))
    for i in range(min(15, len(raw_frames))):
        img = cv2.imread(str(raw_frames[i]))
        h, w = img.shape[:2]
        scale = min(OUT_W / w, OUT_H * 0.78 / h)
        nw, nh = int(w * scale), int(h * scale)
        c = np.zeros((OUT_H, OUT_W, 3), dtype=np.uint8)
        c[:] = DARK_BG[::-1]
        resized = cv2.resize(img, (nw, nh), interpolation=cv2.INTER_LANCZOS4)
        xo, yo = (OUT_W - nw) // 2, 100
        c[yo:yo + nh, xo:xo + nw] = resized

        if i < 12:
            pil = Image.fromarray(cv2.cvtColor(c, cv2.COLOR_BGR2RGB))
            d = ImageDraw.Draw(pil)
            f = load_font(32, bold=True)
            text = "Watch the signature."
            bbox = d.textbbox((0, 0), text, font=f)
            tw = bbox[2] - bbox[0]
            d.rounded_rectangle([(OUT_W - tw) // 2 - 16, OUT_H - 140,
                                  (OUT_W + tw) // 2 + 16, OUT_H - 96],
                                 radius=10, fill=(0, 0, 0, 200))
            d.text(((OUT_W - tw) // 2, OUT_H - 136), text, fill=WHITE, font=f)
            c = cv2.cvtColor(np.array(pil), cv2.COLOR_RGB2BGR)

        for _ in range(3):
            all_frames.append(c)

    # Segment 2: Slo-mo with portrait (0.25x)
    for canvas in canvases:
        for _ in range(12):
            all_frames.append(canvas)

    # Segment 3: Freeze on completed loop (2s)
    # Use the last delivery frame which has the full loop drawn
    freeze_idx = min(delivery_end, len(canvases) - 1)
    if freeze_idx < len(canvases):
        freeze_frame = canvases[freeze_idx]
        pil = Image.fromarray(cv2.cvtColor(freeze_frame, cv2.COLOR_BGR2RGB))
        d = ImageDraw.Draw(pil)
        f = load_font(28, bold=True)

        tightness = portrait_data["tightness"]
        if tightness > 0.6:
            badge = "TIGHT COORDINATION"
            badge_color = (0, 200, 0)
        elif tightness > 0.35:
            badge = "MODERATE COORDINATION"
            badge_color = (255, 200, 0)
        else:
            badge = "SCATTERED PATTERN"
            badge_color = (220, 80, 80)

        bbox = d.textbbox((0, 0), badge, font=f)
        tw = bbox[2] - bbox[0]
        bx = (OUT_W - tw) // 2 - 16
        by = int(OUT_H * 0.30)
        d.rounded_rectangle([bx, by, bx + tw + 32, by + 48], radius=12,
                             fill=(0, 0, 0, 220), outline=badge_color, width=2)
        d.text((bx + 16, by + 10), badge, fill=badge_color, font=f)

        freeze_canvas = cv2.cvtColor(np.array(pil), cv2.COLOR_RGB2BGR)
        for _ in range(2 * FPS):
            all_frames.append(freeze_canvas)

    # Segment 4: Verdict card (2.5s)
    verdict_pil = Image.new("RGB", (OUT_W, OUT_H), DARK_BG)
    d = ImageDraw.Draw(verdict_pil)
    f_big = load_font(42, bold=True)
    f_med = load_font(30, bold=False)
    f_sm = load_font(22, bold=False)

    y = OUT_H // 2 - 140
    d.text((OUT_W // 2 - 200, y), "COORDINATION ANALYSIS", fill=WHITE, font=f_big)
    y += 70

    tightness = portrait_data["tightness"]
    d.text((OUT_W // 2 - 180, y), f"Loop tightness: {tightness:.0%}", fill=(200, 200, 200),
            font=f_med)
    y += 50

    d.text((OUT_W // 2 - 180, y), "Trunk rotation range:", fill=(140, 140, 140), font=f_sm)
    d.text((OUT_W // 2 + 80, y),
           f"{portrait_data['a_max'] - portrait_data['a_min']:.0f}°",
           fill=(0, 200, 255), font=f_sm)
    y += 35
    d.text((OUT_W // 2 - 180, y), "Arm angle range:", fill=(140, 140, 140), font=f_sm)
    d.text((OUT_W // 2 + 80, y),
           f"{portrait_data['b_max'] - portrait_data['b_min']:.0f}°",
           fill=(255, 0, 200), font=f_sm)
    y += 55

    if tightness > 0.6:
        d.text((OUT_W // 2 - 200, y), "Efficient coordination —", fill=(0, 200, 0), font=f_sm)
        y += 30
        d.text((OUT_W // 2 - 200, y), "trunk and arm work in sync.", fill=(160, 160, 160), font=f_sm)
    elif tightness > 0.35:
        d.text((OUT_W // 2 - 200, y), "Moderate coordination —", fill=(255, 200, 0), font=f_sm)
        y += 30
        d.text((OUT_W // 2 - 200, y), "some room to tighten the loop.", fill=(160, 160, 160), font=f_sm)
    else:
        d.text((OUT_W // 2 - 200, y), "Scattered pattern —", fill=(220, 80, 80), font=f_sm)
        y += 30
        d.text((OUT_W // 2 - 200, y), "trunk-arm timing is inconsistent.", fill=(160, 160, 160), font=f_sm)

    verdict_frame = cv2.cvtColor(np.array(verdict_pil), cv2.COLOR_RGB2BGR)
    for _ in range(int(2.5 * FPS)):
        all_frames.append(verdict_frame)

    # Segment 5: End card (1.5s)
    end_pil = Image.new("RGB", (OUT_W, OUT_H), DARK_BG)
    d = ImageDraw.Draw(end_pil)
    bf = load_font(56, bold=True)
    tf = load_font(28, bold=False)
    text = "wellBowled.ai"
    bbox = d.textbbox((0, 0), text, font=bf)
    d.text(((OUT_W - bbox[2] + bbox[0]) // 2, OUT_H // 2 - 40), text, fill=PEACOCK, font=bf)
    tag = "Cricket biomechanics, visualized"
    bbox = d.textbbox((0, 0), tag, font=tf)
    d.text(((OUT_W - bbox[2] + bbox[0]) // 2, OUT_H // 2 + 30), tag, fill=WHITE, font=tf)
    end_frame = cv2.cvtColor(np.array(end_pil), cv2.COLOR_RGB2BGR)
    for _ in range(int(1.5 * FPS)):
        all_frames.append(end_frame)

    # Encode
    with tempfile.TemporaryDirectory() as tmpdir:
        for i, frame in enumerate(all_frames):
            cv2.imwrite(f"{tmpdir}/f_{i:06d}.jpg", frame, [cv2.IMWRITE_JPEG_QUALITY, 95])
        subprocess.run(
            ["ffmpeg", "-y", "-framerate", str(FPS), "-i", f"{tmpdir}/f_%06d.jpg",
             "-c:v", "libx264", "-preset", "medium", "-crf", "20",
             "-pix_fmt", "yuv420p", "-movflags", "+faststart", str(final_path)],
            capture_output=True, check=True,
        )

    duration = len(all_frames) / FPS
    size_mb = final_path.stat().st_size / (1024 * 1024)
    print(f"  [5] Video: {duration:.1f}s, {size_mb:.1f}MB")
    return final_path


# ── Stage 6: Review ───────────────────────────────────────────────────
def review(video_path: Path):
    review_dir = OUTPUT_DIR / "review"
    review_dir.mkdir(exist_ok=True)

    probe = subprocess.run(
        ["ffprobe", "-v", "quiet", "-print_format", "json", "-show_streams", str(video_path)],
        capture_output=True, text=True, check=True,
    )
    vs = next(s for s in json.loads(probe.stdout)["streams"] if s["codec_type"] == "video")
    duration = float(vs["duration"])

    for label, t in [("intro", 0.5), ("portrait_early", duration * 0.2),
                     ("portrait_mid", duration * 0.4), ("freeze", duration * 0.6),
                     ("verdict", duration * 0.8), ("end", duration * 0.95)]:
        subprocess.run(
            ["ffmpeg", "-y", "-ss", f"{t:.2f}", "-i", str(video_path),
             "-frames:v", "1", "-q:v", "2", str(review_dir / f"{label}.jpg")],
            capture_output=True, check=True,
        )

    print(f"  [6] Review: {vs['width']}x{vs['height']}, {duration:.1f}s, "
          f"{video_path.stat().st_size / 1024 / 1024:.1f}MB")


# ── Main ──────────────────────────────────────────────────────────────
def main():
    import time
    start = time.time()

    print("=" * 50)
    print("  PHASE PORTRAIT PIPELINE")
    print("=" * 50)

    frames, meta = extract_frames()
    pose_data = extract_all_poses(frames)
    portrait_data = compute_portrait_angles(pose_data)
    canvases = render_portrait_frames(pose_data, portrait_data)
    video_path = compose_video(canvases, portrait_data)
    review(video_path)

    elapsed = time.time() - start
    print(f"\n{'=' * 50}")
    print(f"  DONE in {elapsed:.1f}s")
    print(f"  Video: {video_path}")
    print(f"{'=' * 50}")


if __name__ == "__main__":
    main()
