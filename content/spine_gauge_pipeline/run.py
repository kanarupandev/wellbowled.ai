#!/usr/bin/env python3
"""Spine Stress Gauge Pipeline — lumbar lateral flexion + rotation risk arc.

Pulsing arc at the lumbar spine showing lateral flexion + rotation composite
risk score. Goes red when entering injury danger zone (>40° combined).
Based on Feros et al. 2024 (lumbar bone stress injuries in pace bowling).
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
L_EAR, R_EAR = 7, 8

POSE_CONNECTIONS = [
    (11, 12), (11, 13), (13, 15), (12, 14), (14, 16),
    (11, 23), (12, 24), (23, 24), (23, 25), (25, 27),
    (24, 26), (26, 28),
]

DELIVERY_START = 2
DELIVERY_END_DEFAULT = 25

# Risk thresholds (Feros et al. 2024)
SAFE_THRESHOLD = 25.0       # green: combined < 25°
WARN_THRESHOLD = 35.0       # yellow: 25-35°
DANGER_THRESHOLD = 40.0     # red: > 40°

# Gauge layout
GAUGE_RADIUS = 90
GAUGE_THICKNESS = 12


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


def risk_color_bgr(combined: float) -> tuple[int, int, int]:
    if combined < SAFE_THRESHOLD:
        return (0, 200, 0)       # green
    elif combined < WARN_THRESHOLD:
        # Lerp green → yellow
        t = (combined - SAFE_THRESHOLD) / (WARN_THRESHOLD - SAFE_THRESHOLD)
        return (0, 200 + int(55 * t), int(200 * t))
    elif combined < DANGER_THRESHOLD:
        # Lerp yellow → red
        t = (combined - WARN_THRESHOLD) / (DANGER_THRESHOLD - WARN_THRESHOLD)
        return (0, int(255 * (1 - t)), int(200 + 55 * t))
    else:
        return (0, 0, 230)       # bright red


def risk_color_rgb(combined: float) -> tuple[int, int, int]:
    bgr = risk_color_bgr(combined)
    return (bgr[2], bgr[1], bgr[0])


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


# ── Stage 3: Compute spine stress metrics ────────────────────────────
def compute_spine_stress(pose_data: list[dict]) -> dict:
    n = len(pose_data)
    delivery_end = min(DELIVERY_END_DEFAULT, n - 1)

    lateral_flexion = []   # angle of mid-shoulder from vertical relative to mid-hip
    trunk_rotation = []    # shoulder line angle (rotation in transverse plane)
    combined_stress = []   # composite risk score

    for fi in range(n):
        lm = pose_data[fi].get("landmarks")
        if lm is None:
            lateral_flexion.append(float("nan"))
            trunk_rotation.append(float("nan"))
            combined_stress.append(float("nan"))
            continue

        has_shoulders = lm[L_SHOULDER]["vis"] > 0.3 and lm[R_SHOULDER]["vis"] > 0.3
        has_hips = lm[L_HIP]["vis"] > 0.3 and lm[R_HIP]["vis"] > 0.3

        if not (has_shoulders and has_hips):
            lateral_flexion.append(float("nan"))
            trunk_rotation.append(float("nan"))
            combined_stress.append(float("nan"))
            continue

        # Mid-shoulder and mid-hip
        ms_x = (lm[L_SHOULDER]["x"] + lm[R_SHOULDER]["x"]) / 2
        ms_y = (lm[L_SHOULDER]["y"] + lm[R_SHOULDER]["y"]) / 2
        mh_x = (lm[L_HIP]["x"] + lm[R_HIP]["x"]) / 2
        mh_y = (lm[L_HIP]["y"] + lm[R_HIP]["y"]) / 2

        # Lateral flexion: angle of trunk from vertical
        # In 2D: angle of (mid_shoulder - mid_hip) vector from straight up
        dx = ms_x - mh_x
        dy = ms_y - mh_y  # y increases downward in image
        # Vertical is (0, -1) in image coords (straight up)
        # atan2 of the trunk vector
        trunk_angle_from_vertical = abs(math.degrees(math.atan2(dx, -dy)))
        lateral_flexion.append(trunk_angle_from_vertical)

        # Trunk rotation: angle of shoulder line from horizontal
        s_dx = lm[R_SHOULDER]["x"] - lm[L_SHOULDER]["x"]
        s_dy = lm[R_SHOULDER]["y"] - lm[L_SHOULDER]["y"]
        rotation = abs(math.degrees(math.atan2(s_dy, s_dx)))
        trunk_rotation.append(rotation)

        # Combined stress: weighted sum (Feros et al. uses lateral flexion
        # as primary risk factor, rotation as secondary)
        combined = lateral_flexion[-1] * 0.7 + trunk_rotation[-1] * 0.3
        combined_stress.append(combined)

    # Smooth
    for arr_name in ["lateral_flexion", "trunk_rotation", "combined_stress"]:
        arr = np.array(locals()[arr_name], dtype=float)
        valid = ~np.isnan(arr)
        if valid.sum() >= 3:
            indices = np.arange(len(arr))
            arr[~valid] = np.interp(indices[~valid], indices[valid], arr[valid])
            wl = min(7, len(arr))
            if wl % 2 == 0:
                wl -= 1
            if wl >= 3:
                arr[:] = savgol_filter(arr, window_length=wl, polyorder=2)
            arr = np.clip(arr, 0, None)
        if arr_name == "lateral_flexion":
            lateral_flexion = arr.tolist()
        elif arr_name == "trunk_rotation":
            trunk_rotation = arr.tolist()
        else:
            combined_stress = arr.tolist()

    # Peak stress during delivery
    delivery_combined = combined_stress[DELIVERY_START:delivery_end + 1]
    peak_idx = int(np.argmax(delivery_combined)) + DELIVERY_START
    peak_combined = combined_stress[peak_idx]
    peak_lateral = lateral_flexion[peak_idx]
    peak_rotation = trunk_rotation[peak_idx]

    print(f"  [3] Peak combined stress: {peak_combined:.1f}° at frame {peak_idx}")
    print(f"      Lateral flexion: {peak_lateral:.1f}°, Rotation: {peak_rotation:.1f}°")

    if peak_combined < SAFE_THRESHOLD:
        verdict = "LOW RISK"
    elif peak_combined < WARN_THRESHOLD:
        verdict = "MONITOR"
    elif peak_combined < DANGER_THRESHOLD:
        verdict = "CAUTION"
    else:
        verdict = "HIGH RISK"
    print(f"      Verdict: {verdict}")

    return {
        "lateral_flexion": lateral_flexion,
        "trunk_rotation": trunk_rotation,
        "combined_stress": combined_stress,
        "peak_idx": peak_idx,
        "peak_combined": peak_combined,
        "peak_lateral": peak_lateral,
        "peak_rotation": peak_rotation,
        "verdict": verdict,
        "delivery_end": delivery_end,
    }


# ── Stage 4: Render spine gauge frames ───────────────────────────────
def draw_gauge_arc(canvas: np.ndarray, center: tuple[int, int],
                   combined: float, pulse_phase: float):
    """Draw a semi-circular gauge arc centered at the lumbar spine."""
    color = risk_color_bgr(combined)

    # Gauge fills from left (0°) to right based on stress level
    # Map combined stress: 0° → 0 sweep, 60° → full 180° sweep
    fill_ratio = min(combined / 60.0, 1.0)
    sweep_angle = fill_ratio * 180.0

    # Pulsing effect when in danger zone
    pulse_extra = 0
    if combined > WARN_THRESHOLD:
        pulse_extra = int(4 * math.sin(pulse_phase * math.pi * 2))

    radius = GAUGE_RADIUS + pulse_extra
    thickness = GAUGE_THICKNESS

    # Background arc (dark)
    cv2.ellipse(canvas, center, (radius, radius), 0, -180, 0,
                (30, 35, 45), thickness, cv2.LINE_AA)

    # Filled arc
    if sweep_angle > 0:
        cv2.ellipse(canvas, center, (radius, radius), 0,
                    -180, -180 + sweep_angle, color, thickness, cv2.LINE_AA)

    # Danger zone flash
    if combined > DANGER_THRESHOLD:
        flash_alpha = 0.15 + 0.1 * math.sin(pulse_phase * math.pi * 4)
        glow = canvas.copy()
        cv2.ellipse(glow, center, (radius + 15, radius + 15), 0,
                    -180, 0, (0, 0, 255), 20, cv2.LINE_AA)
        cv2.addWeighted(glow, flash_alpha, canvas, 1 - flash_alpha, 0, canvas)

    # Tick marks at thresholds
    for threshold, label in [(SAFE_THRESHOLD, "25"), (WARN_THRESHOLD, "35"),
                              (DANGER_THRESHOLD, "40")]:
        tick_ratio = min(threshold / 60.0, 1.0)
        tick_angle = math.radians(-180 + tick_ratio * 180)
        inner_r = radius - thickness // 2 - 4
        outer_r = radius + thickness // 2 + 4
        p_inner = (center[0] + int(inner_r * math.cos(tick_angle)),
                   center[1] + int(inner_r * math.sin(tick_angle)))
        p_outer = (center[0] + int(outer_r * math.cos(tick_angle)),
                   center[1] + int(outer_r * math.sin(tick_angle)))
        cv2.line(canvas, p_inner, p_outer, (140, 140, 140), 1, cv2.LINE_AA)

    # Center dot
    cv2.circle(canvas, center, 5, color, -1, cv2.LINE_AA)


def render_spine_frames(pose_data: list[dict], stress_data: dict) -> list[np.ndarray]:
    ANNOTATED_DIR.mkdir(parents=True, exist_ok=True)
    delivery_end = stress_data["delivery_end"]
    combined = stress_data["combined_stress"]
    lateral = stress_data["lateral_flexion"]
    rotation = stress_data["trunk_rotation"]
    all_canvases = []

    for fi, pd in enumerate(pose_data):
        img = cv2.imread(pd["path"])
        h, w = img.shape[:2]
        lm = pd.get("landmarks")

        # Video in top 65% (more video space since gauge is overlaid)
        scale = min(OUT_W / w, (OUT_H * 0.65) / h)
        new_w, new_h = int(w * scale), int(h * scale)
        x_off = (OUT_W - new_w) // 2
        y_off = 80

        canvas = np.zeros((OUT_H, OUT_W, 3), dtype=np.uint8)
        canvas[:] = DARK_BG[::-1]
        resized = cv2.resize(img, (new_w, new_h), interpolation=cv2.INTER_LANCZOS4)
        canvas[y_off:y_off + new_h, x_off:x_off + new_w] = resized

        in_delivery = DELIVERY_START <= fi <= delivery_end
        stress_val = combined[fi] if fi < len(combined) else 0

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

            # Highlight spine line (mid-hip to mid-shoulder)
            has_all = (vis(L_SHOULDER) > 0.3 and vis(R_SHOULDER) > 0.3 and
                       vis(L_HIP) > 0.3 and vis(R_HIP) > 0.3)
            if has_all:
                ms = ((px(L_SHOULDER)[0] + px(R_SHOULDER)[0]) // 2,
                      (px(L_SHOULDER)[1] + px(R_SHOULDER)[1]) // 2)
                mh = ((px(L_HIP)[0] + px(R_HIP)[0]) // 2,
                      (px(L_HIP)[1] + px(R_HIP)[1]) // 2)

                spine_color = risk_color_bgr(stress_val)

                # Spine line
                cv2.line(canvas, ms, mh, spine_color, 5, cv2.LINE_AA)

                # Shoulder line
                cv2.line(canvas, px(L_SHOULDER), px(R_SHOULDER), spine_color, 3, cv2.LINE_AA)

                # Hip line
                cv2.line(canvas, px(L_HIP), px(R_HIP), (100, 100, 100), 3, cv2.LINE_AA)

                # Vertical reference (from mid-hip straight up)
                vert_top = (mh[0], mh[1] - int((mh[1] - ms[1]) * 1.2))
                cv2.line(canvas, mh, vert_top, (60, 60, 60), 1, cv2.LINE_AA)

                # Joint dots
                for pt in [ms, mh]:
                    cv2.circle(canvas, pt, 7, spine_color, -1, cv2.LINE_AA)
                    cv2.circle(canvas, pt, 7, WHITE, 2, cv2.LINE_AA)

                # Draw gauge arc at lumbar region (between mid-hip and mid-shoulder)
                lumbar = ((ms[0] + mh[0]) // 2, (ms[1] + mh[1]) // 2)
                pulse_phase = (fi - DELIVERY_START) / max(delivery_end - DELIVERY_START, 1)
                draw_gauge_arc(canvas, lumbar, stress_val, pulse_phase)

        # ── Stress meter panel (bottom) ───────────────────────────
        panel_y = y_off + new_h + 20
        panel_h = OUT_H - panel_y - 60

        # Horizontal stress bar
        bar_left = 80
        bar_right = OUT_W - 80
        bar_top = panel_y + 60
        bar_h = 28
        bar_w = bar_right - bar_left

        # Background bar with zone colors
        zone_w = bar_w / 3
        # Green zone
        cv2.rectangle(canvas, (bar_left, bar_top),
                      (bar_left + int(zone_w * SAFE_THRESHOLD / 60), bar_top + bar_h),
                      (0, 80, 0), -1)
        # Yellow zone
        cv2.rectangle(canvas, (bar_left + int(zone_w * SAFE_THRESHOLD / 60), bar_top),
                      (bar_left + int(bar_w * WARN_THRESHOLD / 60), bar_top + bar_h),
                      (0, 80, 80), -1)
        # Orange zone
        cv2.rectangle(canvas, (bar_left + int(bar_w * WARN_THRESHOLD / 60), bar_top),
                      (bar_left + int(bar_w * DANGER_THRESHOLD / 60), bar_top + bar_h),
                      (0, 50, 120), -1)
        # Red zone
        cv2.rectangle(canvas, (bar_left + int(bar_w * DANGER_THRESHOLD / 60), bar_top),
                      (bar_right, bar_top + bar_h),
                      (0, 0, 80), -1)

        # Bar outline
        cv2.rectangle(canvas, (bar_left, bar_top), (bar_right, bar_top + bar_h),
                      (60, 65, 75), 1)

        # Current value indicator
        if in_delivery or fi > delivery_end:
            val = min(stress_val, 60)
            indicator_x = bar_left + int(val / 60 * bar_w)
            color = risk_color_bgr(stress_val)
            # Filled portion
            cv2.rectangle(canvas, (bar_left, bar_top),
                          (indicator_x, bar_top + bar_h), color, -1)
            # Needle
            cv2.line(canvas, (indicator_x, bar_top - 6),
                     (indicator_x, bar_top + bar_h + 6), WHITE, 2, cv2.LINE_AA)

        # ── Text overlays ─────────────────────────────────────────
        pil = Image.fromarray(cv2.cvtColor(canvas, cv2.COLOR_BGR2RGB))
        draw = ImageDraw.Draw(pil)

        font_title = load_font(34, bold=True)
        font_angle = load_font(28, bold=True)
        font_label = load_font(17, bold=False)
        font_small = load_font(14, bold=False)
        font_brand = load_font(20, bold=True)
        font_verdict = load_font(22, bold=True)

        # Title
        title = "SPINE STRESS GAUGE"
        bbox = draw.textbbox((0, 0), title, font=font_title)
        tw = bbox[2] - bbox[0]
        draw.text(((OUT_W - tw) // 2, 20), title, fill=WHITE, font=font_title)

        # Angle readouts
        text_y = panel_y + 5
        if in_delivery or fi > delivery_end:
            rc = risk_color_rgb(stress_val)

            draw.text((bar_left, text_y),
                       f"Combined: {stress_val:.0f}°", fill=rc, font=font_angle)

            # Verdict text
            if stress_val < SAFE_THRESHOLD:
                vtext, vc = "LOW RISK", (0, 200, 0)
            elif stress_val < WARN_THRESHOLD:
                vtext, vc = "MONITOR", (255, 200, 0)
            elif stress_val < DANGER_THRESHOLD:
                vtext, vc = "CAUTION", (255, 140, 0)
            else:
                vtext, vc = "HIGH RISK", (230, 50, 50)
            draw.text((bar_left + 280, text_y + 4), vtext, fill=vc, font=font_verdict)

        # Sub-angles below bar
        sub_y = bar_top + bar_h + 12
        if in_delivery or fi > delivery_end:
            lat_val = lateral[fi] if fi < len(lateral) else 0
            rot_val = rotation[fi] if fi < len(rotation) else 0
            draw.text((bar_left, sub_y),
                       f"Lateral flexion: {lat_val:.0f}°", fill=(160, 160, 160), font=font_small)
            draw.text((bar_left + 250, sub_y),
                       f"Rotation: {rot_val:.0f}°", fill=(160, 160, 160), font=font_small)

        # Zone labels under bar
        zone_y = sub_y + 22
        draw.text((bar_left, zone_y), "SAFE", fill=(0, 160, 0), font=font_small)
        draw.text((bar_left + int(bar_w * 0.35), zone_y), "WARN", fill=(200, 200, 0), font=font_small)
        draw.text((bar_left + int(bar_w * 0.58), zone_y), "CAUTION", fill=(255, 140, 0), font=font_small)
        draw.text((bar_right - 70, zone_y), "DANGER", fill=(200, 50, 50), font=font_small)

        # Time
        time_s = fi / EXTRACT_FPS
        draw.text((OUT_W - 100, sub_y), f"{time_s:.1f}s", fill=(120, 120, 120), font=font_label)

        # Brand
        draw.text((OUT_W - 180, OUT_H - 45), "wellBowled.ai", fill=PEACOCK, font=font_brand)

        canvas = cv2.cvtColor(np.array(pil), cv2.COLOR_RGB2BGR)
        cv2.imwrite(str(ANNOTATED_DIR / pd["frame"]), canvas, [cv2.IMWRITE_JPEG_QUALITY, 95])
        all_canvases.append(canvas)

    print(f"  [4] Rendered {len(all_canvases)} spine gauge frames")
    return all_canvases


# ── Stage 5: Compose video ────────────────────────────────────────────
def compose_video(canvases: list[np.ndarray], stress_data: dict) -> Path:
    final_path = OUTPUT_DIR / "spine_gauge.mp4"
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
            text = "Watch the spine."
            bbox = d.textbbox((0, 0), text, font=f)
            tw = bbox[2] - bbox[0]
            d.rounded_rectangle([(OUT_W - tw) // 2 - 16, OUT_H - 140,
                                  (OUT_W + tw) // 2 + 16, OUT_H - 96],
                                 radius=10, fill=(0, 0, 0, 200))
            d.text(((OUT_W - tw) // 2, OUT_H - 136), text, fill=WHITE, font=f)
            c = cv2.cvtColor(np.array(pil), cv2.COLOR_RGB2BGR)

        for _ in range(3):
            all_frames.append(c)

    # Segment 2: Slo-mo with gauge (0.25x)
    for canvas in canvases:
        for _ in range(12):
            all_frames.append(canvas)

    # Segment 3: Freeze on peak stress frame (2s)
    peak_idx = stress_data["peak_idx"]
    if peak_idx < len(canvases):
        freeze = canvases[peak_idx]
        pil = Image.fromarray(cv2.cvtColor(freeze, cv2.COLOR_BGR2RGB))
        d = ImageDraw.Draw(pil)
        f = load_font(28, bold=True)

        combined = stress_data["peak_combined"]
        verdict = stress_data["verdict"]
        rc = risk_color_rgb(combined)

        badge = f"PEAK STRESS: {combined:.0f}° — {verdict}"
        bbox = d.textbbox((0, 0), badge, font=f)
        tw = bbox[2] - bbox[0]
        bx = (OUT_W - tw) // 2 - 16
        by = int(OUT_H * 0.28)
        d.rounded_rectangle([bx, by, bx + tw + 32, by + 48], radius=12,
                             fill=(0, 0, 0, 220), outline=rc, width=2)
        d.text((bx + 16, by + 10), badge, fill=rc, font=f)

        freeze_canvas = cv2.cvtColor(np.array(pil), cv2.COLOR_RGB2BGR)
        for _ in range(2 * FPS):
            all_frames.append(freeze_canvas)

    # Segment 4: Verdict card (2.5s)
    verdict_pil = Image.new("RGB", (OUT_W, OUT_H), DARK_BG)
    d = ImageDraw.Draw(verdict_pil)
    f_big = load_font(42, bold=True)
    f_med = load_font(30, bold=False)
    f_sm = load_font(22, bold=False)

    y = OUT_H // 2 - 160
    d.text((OUT_W // 2 - 200, y), "SPINE STRESS ANALYSIS", fill=WHITE, font=f_big)
    y += 70

    combined = stress_data["peak_combined"]
    rc = risk_color_rgb(combined)
    d.text((OUT_W // 2 - 180, y), f"Peak combined: {combined:.0f}°", fill=rc, font=f_med)
    y += 50

    d.text((OUT_W // 2 - 180, y),
           f"Lateral flexion: {stress_data['peak_lateral']:.0f}°",
           fill=(160, 160, 160), font=f_sm)
    y += 35
    d.text((OUT_W // 2 - 180, y),
           f"Trunk rotation: {stress_data['peak_rotation']:.0f}°",
           fill=(160, 160, 160), font=f_sm)
    y += 55

    verdict = stress_data["verdict"]
    if verdict == "LOW RISK":
        d.text((OUT_W // 2 - 180, y), "Low spinal stress —", fill=(0, 200, 0), font=f_sm)
        y += 30
        d.text((OUT_W // 2 - 180, y), "healthy loading pattern.",
                fill=(160, 160, 160), font=f_sm)
    elif verdict == "MONITOR":
        d.text((OUT_W // 2 - 180, y), "Moderate stress detected —", fill=(255, 200, 0), font=f_sm)
        y += 30
        d.text((OUT_W // 2 - 180, y), "monitor for fatigue changes.",
                fill=(160, 160, 160), font=f_sm)
    elif verdict == "CAUTION":
        d.text((OUT_W // 2 - 180, y), "Elevated spinal stress —", fill=(255, 140, 0), font=f_sm)
        y += 30
        d.text((OUT_W // 2 - 180, y), "risk factor for lumbar injury.",
                fill=(160, 160, 160), font=f_sm)
    else:
        d.text((OUT_W // 2 - 180, y), "High risk loading pattern —", fill=(230, 50, 50), font=f_sm)
        y += 30
        d.text((OUT_W // 2 - 180, y), "immediate technique review needed.",
                fill=(160, 160, 160), font=f_sm)

    y += 50
    d.text((OUT_W // 2 - 180, y), "Ref: Feros et al. 2024",
            fill=(80, 80, 80), font=load_font(16, bold=False))

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

    for label, t in [("intro", 0.5), ("gauge_early", duration * 0.2),
                     ("gauge_mid", duration * 0.4), ("peak", duration * 0.6),
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
    print("  SPINE STRESS GAUGE PIPELINE")
    print("=" * 50)

    frames, meta = extract_frames()
    pose_data = extract_all_poses(frames)
    stress_data = compute_spine_stress(pose_data)
    canvases = render_spine_frames(pose_data, stress_data)
    video_path = compose_video(canvases, stress_data)
    review(video_path)

    elapsed = time.time() - start
    print(f"\n{'=' * 50}")
    print(f"  DONE in {elapsed:.1f}s")
    print(f"  Video: {video_path}")
    print(f"{'=' * 50}")


if __name__ == "__main__":
    main()
