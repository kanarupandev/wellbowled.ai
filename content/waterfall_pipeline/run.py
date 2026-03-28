#!/usr/bin/env python3
"""Velocity Waterfall Pipeline — kinetic chain speed curves on bowling action.

Stacked velocity-time curves for pelvis→trunk→upper arm→forearm→wrist
animated alongside slo-mo video. Shows the sequential "whip" of the
kinetic chain. Based on Putnam 1993, Felton 2023.
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

# Landmark indices
L_SHOULDER, R_SHOULDER = 11, 12
L_HIP, R_HIP = 23, 24
R_ELBOW = 14
R_WRIST = 16
R_INDEX = 20

POSE_CONNECTIONS = [
    (11, 12), (11, 13), (13, 15), (12, 14), (14, 16),
    (11, 23), (12, 24), (23, 24), (23, 25), (25, 27),
    (24, 26), (26, 28),
]

# Segment definitions
SEGMENT_NAMES = ["Pelvis", "Trunk", "Upper Arm", "Forearm", "Wrist"]
SEGMENT_LANDMARKS = {
    "Pelvis":    {"method": "midpoint", "indices": (L_HIP, R_HIP)},
    "Trunk":     {"method": "midpoint", "indices": (L_SHOULDER, R_SHOULDER)},
    "Upper Arm": {"method": "single",   "indices": (R_ELBOW,)},
    "Forearm":   {"method": "single",   "indices": (R_WRIST,)},
    "Wrist":     {"method": "single",   "indices": (R_INDEX,), "fallback": R_WRIST},
}

SEGMENT_COLORS_RGB = {
    "Pelvis":    (255, 107, 107),
    "Trunk":     (255, 217, 61),
    "Upper Arm": (107, 203, 119),
    "Forearm":   (77, 150, 255),
    "Wrist":     (255, 0, 255),
}
SEGMENT_COLORS_BGR = {k: (v[2], v[1], v[0]) for k, v in SEGMENT_COLORS_RGB.items()}

DELIVERY_START = 2
DELIVERY_END_DEFAULT = 25

# Graph layout constants
GRAPH_LEFT = 90
GRAPH_RIGHT = OUT_W - 50
GRAPH_TOP = int(OUT_H * 0.62)
GRAPH_BOTTOM = OUT_H - 110
GRAPH_W = GRAPH_RIGHT - GRAPH_LEFT
GRAPH_H = GRAPH_BOTTOM - GRAPH_TOP


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


# ── Stage 3: Compute velocities ──────────────────────────────────────
def compute_velocities(pose_data: list[dict]) -> dict:
    n = len(pose_data)
    delivery_end = min(DELIVERY_END_DEFAULT, n - 1)

    # Decide wrist landmark: use R_INDEX if visible enough, else R_WRIST
    index_vis_count = 0
    delivery_frames = 0
    for fi in range(DELIVERY_START, delivery_end + 1):
        lm = pose_data[fi].get("landmarks")
        if lm:
            delivery_frames += 1
            if lm[R_INDEX]["vis"] > 0.3:
                index_vis_count += 1
    use_index = index_vis_count > delivery_frames * 0.5
    wrist_idx = R_INDEX if use_index else R_WRIST
    print(f"  [3a] Wrist landmark: {'R_INDEX(20)' if use_index else 'R_WRIST(16)'} "
          f"({index_vis_count}/{delivery_frames} visible)")

    # Extract positions per segment
    positions = {seg: [] for seg in SEGMENT_NAMES}

    for fi in range(n):
        lm = pose_data[fi].get("landmarks")
        for seg in SEGMENT_NAMES:
            spec = SEGMENT_LANDMARKS[seg]
            if lm is None:
                positions[seg].append((float("nan"), float("nan")))
                continue

            if seg == "Wrist":
                idx = wrist_idx
                if lm[idx]["vis"] < 0.3:
                    idx = R_WRIST  # fallback
                if lm[idx]["vis"] < 0.3:
                    positions[seg].append((float("nan"), float("nan")))
                    continue
                positions[seg].append((lm[idx]["x"], lm[idx]["y"]))
            elif spec["method"] == "midpoint":
                i1, i2 = spec["indices"]
                if lm[i1]["vis"] < 0.3 or lm[i2]["vis"] < 0.3:
                    positions[seg].append((float("nan"), float("nan")))
                    continue
                positions[seg].append((
                    (lm[i1]["x"] + lm[i2]["x"]) / 2,
                    (lm[i1]["y"] + lm[i2]["y"]) / 2,
                ))
            else:  # single
                idx = spec["indices"][0]
                if lm[idx]["vis"] < 0.3:
                    positions[seg].append((float("nan"), float("nan")))
                    continue
                positions[seg].append((lm[idx]["x"], lm[idx]["y"]))

    # Compute raw velocities using central difference
    raw_velocities = {}
    for seg in SEGMENT_NAMES:
        pos = positions[seg]
        vel = np.zeros(n)
        for i in range(1, n - 1):
            x0, y0 = pos[i - 1]
            x2, y2 = pos[i + 1]
            if math.isnan(x0) or math.isnan(x2):
                vel[i] = float("nan")
            else:
                vx = (x2 - x0) / (2 * DT)
                vy = (y2 - y0) / (2 * DT)
                vel[i] = math.sqrt(vx**2 + vy**2)
        vel[0] = vel[1]
        vel[-1] = vel[-2]
        raw_velocities[seg] = vel

    # Interpolate NaN gaps and smooth
    smooth_velocities = {}
    for seg in SEGMENT_NAMES:
        vel = raw_velocities[seg].copy()
        valid = ~np.isnan(vel)
        if valid.sum() >= 3:
            indices = np.arange(len(vel))
            vel[~valid] = np.interp(indices[~valid], indices[valid], vel[valid])
            wl = min(7, len(vel))
            if wl % 2 == 0:
                wl -= 1
            if wl >= 3:
                vel = savgol_filter(vel, window_length=wl, polyorder=2)
            vel = np.clip(vel, 0, None)
        else:
            vel = np.zeros(len(vel))
        smooth_velocities[seg] = vel

    # Normalize to max wrist velocity
    wrist_delivery = smooth_velocities["Wrist"][DELIVERY_START:delivery_end + 1]
    max_wrist = float(np.max(wrist_delivery)) if len(wrist_delivery) > 0 else 1.0
    if max_wrist < 1e-6:
        max_wrist = 1.0

    normalized = {}
    for seg in SEGMENT_NAMES:
        normalized[seg] = np.clip(smooth_velocities[seg] / max_wrist, 0, 1.5)

    # Peak detection within delivery zone
    peak_frames = {}
    for seg in SEGMENT_NAMES:
        delivery_slice = smooth_velocities[seg][DELIVERY_START:delivery_end + 1]
        peak_frames[seg] = int(np.argmax(delivery_slice)) + DELIVERY_START

    peak_wrist_frame = peak_frames["Wrist"]

    # Zoom graph to interesting region: from DELIVERY_START to a few frames past last peak
    last_peak = max(peak_frames.values())
    graph_end = min(last_peak + 6, delivery_end)  # 6 frames (0.6s) buffer after last peak

    # Check sequencing: peaks should be proximal → distal
    peak_order = sorted(peak_frames.items(), key=lambda x: x[1])
    expected_order = SEGMENT_NAMES
    actual_order = [p[0] for p in peak_order]
    sequencing_correct = True
    for i in range(len(expected_order) - 1):
        if peak_frames[expected_order[i]] > peak_frames[expected_order[i + 1]]:
            sequencing_correct = False
            break

    print(f"  [3b] Peak frames: {peak_frames}")
    print(f"  [3b] Sequencing: {'ELITE' if sequencing_correct else 'BLOCKED'} "
          f"({' → '.join(actual_order)})")
    print(f"  [3b] Graph zoom: frames {DELIVERY_START}-{graph_end} (last peak at {last_peak})")

    return {
        "positions": positions,
        "smooth_velocities": {k: v.tolist() for k, v in smooth_velocities.items()},
        "normalized": {k: v.tolist() for k, v in normalized.items()},
        "peak_frames": peak_frames,
        "peak_wrist_frame": peak_wrist_frame,
        "max_wrist_velocity": max_wrist,
        "sequencing_correct": sequencing_correct,
        "peak_order": peak_order,
        "delivery_end": delivery_end,
        "graph_end": graph_end,
    }


# ── Stage 4: Render waterfall frames ─────────────────────────────────
def data_to_graph_px(frame_idx: int, vel_norm: float, graph_end: int) -> tuple[int, int]:
    t = (frame_idx - DELIVERY_START) / max(graph_end - DELIVERY_START, 1)
    px_x = GRAPH_LEFT + int(t * GRAPH_W)
    px_y = GRAPH_BOTTOM - int(min(vel_norm, 1.2) / 1.2 * GRAPH_H)
    return (px_x, px_y)


def render_waterfall_frames(pose_data: list[dict], vel_data: dict) -> list[np.ndarray]:
    ANNOTATED_DIR.mkdir(parents=True, exist_ok=True)
    delivery_end = vel_data["delivery_end"]
    graph_end = vel_data["graph_end"]
    normalized = {k: np.array(v) for k, v in vel_data["normalized"].items()}
    all_canvases = []

    for fi, pd in enumerate(pose_data):
        img = cv2.imread(pd["path"])
        h, w = img.shape[:2]
        lm = pd.get("landmarks")

        # Fit video to top 58%
        scale = min(OUT_W / w, (OUT_H * 0.56) / h)
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

            # Find which segment has max velocity at this frame
            max_seg = None
            max_vel = 0
            for seg in SEGMENT_NAMES:
                v = normalized[seg][fi]
                if v > max_vel:
                    max_vel = v
                    max_seg = seg

            # Draw faded skeleton
            overlay = canvas.copy()
            for j1, j2 in POSE_CONNECTIONS:
                if vis(j1) < 0.3 or vis(j2) < 0.3:
                    continue
                cv2.line(overlay, px(j1), px(j2), (180, 180, 180), 2, cv2.LINE_AA)
            cv2.addWeighted(overlay, 0.3, canvas, 0.7, 0, canvas)

            # Highlight active segment's landmarks
            if max_seg:
                color = SEGMENT_COLORS_BGR[max_seg]
                spec = SEGMENT_LANDMARKS[max_seg]
                for idx in spec["indices"]:
                    if vis(idx) > 0.3:
                        cv2.circle(canvas, px(idx), 10, color, -1, cv2.LINE_AA)
                        cv2.circle(canvas, px(idx), 10, WHITE, 2, cv2.LINE_AA)

        # ── Draw velocity graph ───────────────────────────────────
        # Separator line
        sep_y = GRAPH_TOP - 20
        cv2.line(canvas, (40, sep_y), (OUT_W - 40, sep_y), (40, 44, 50), 1, cv2.LINE_AA)

        # Grid lines
        for frac in [0.0, 0.25, 0.5, 0.75, 1.0]:
            gy = GRAPH_BOTTOM - int(frac / 1.2 * GRAPH_H)
            cv2.line(canvas, (GRAPH_LEFT, gy), (GRAPH_RIGHT, gy),
                     (35, 38, 45), 1, cv2.LINE_AA)

        # X-axis baseline
        cv2.line(canvas, (GRAPH_LEFT, GRAPH_BOTTOM), (GRAPH_RIGHT, GRAPH_BOTTOM),
                 (60, 65, 75), 1, cv2.LINE_AA)
        # Y-axis
        cv2.line(canvas, (GRAPH_LEFT, GRAPH_TOP), (GRAPH_LEFT, GRAPH_BOTTOM),
                 (60, 65, 75), 1, cv2.LINE_AA)

        # Draw curves: progressively during delivery, frozen after graph_end
        show_graph = in_delivery or fi > graph_end
        if show_graph:
            draw_end = min(fi, graph_end)

            for seg in SEGMENT_NAMES:
                pts = []
                for fj in range(DELIVERY_START, draw_end + 1):
                    v = normalized[seg][fj]
                    pts.append(data_to_graph_px(fj, v, graph_end))

                if len(pts) < 2:
                    continue

                pts_arr = np.array(pts, dtype=np.int32)
                color = SEGMENT_COLORS_BGR[seg]

                # Fill under curve (low alpha)
                fill_pts = list(pts_arr)
                fill_pts.append((pts_arr[-1][0], GRAPH_BOTTOM))
                fill_pts.append((pts_arr[0][0], GRAPH_BOTTOM))
                fill_overlay = canvas.copy()
                cv2.fillPoly(fill_overlay, [np.array(fill_pts, dtype=np.int32)], color)
                cv2.addWeighted(fill_overlay, 0.10, canvas, 0.90, 0, canvas)

                # Glow layer
                glow_overlay = canvas.copy()
                cv2.polylines(glow_overlay, [pts_arr], False, color, 7, cv2.LINE_AA)
                glow_blurred = cv2.GaussianBlur(glow_overlay, (9, 9), 0)
                cv2.addWeighted(glow_blurred, 0.25, canvas, 0.75, 0, canvas)

                # Main curve
                cv2.polylines(canvas, [pts_arr], False, color, 3, cv2.LINE_AA)

            # Vertical cursor (only during active graph drawing)
            if fi <= graph_end:
                cursor_x = data_to_graph_px(fi, 0, graph_end)[0]
                for dy in range(GRAPH_TOP, GRAPH_BOTTOM, 14):
                    cv2.line(canvas, (cursor_x, dy), (cursor_x, min(dy + 8, GRAPH_BOTTOM)),
                             (200, 200, 200), 1, cv2.LINE_AA)

                # Cursor dots on each curve
                for seg in SEGMENT_NAMES:
                    v = normalized[seg][fi]
                    dot_pos = data_to_graph_px(fi, v, graph_end)
                    color = SEGMENT_COLORS_BGR[seg]
                    cv2.circle(canvas, dot_pos, 5, color, -1, cv2.LINE_AA)
                    cv2.circle(canvas, dot_pos, 5, WHITE, 1, cv2.LINE_AA)

        # ── Text overlays via Pillow ──────────────────────────────
        pil = Image.fromarray(cv2.cvtColor(canvas, cv2.COLOR_BGR2RGB))
        draw = ImageDraw.Draw(pil)

        font_title = load_font(34, bold=True)
        font_label = load_font(16, bold=False)
        font_small = load_font(14, bold=False)
        font_brand = load_font(20, bold=True)

        # Title
        title = "VELOCITY WATERFALL"
        bbox = draw.textbbox((0, 0), title, font=font_title)
        tw = bbox[2] - bbox[0]
        draw.text(((OUT_W - tw) // 2, 20), title, fill=WHITE, font=font_title)

        # Y-axis label
        draw.text((12, GRAPH_TOP + GRAPH_H // 2 - 40), "V\nE\nL", fill=(120, 120, 120),
                   font=font_small)

        # Legend below graph
        legend_y = GRAPH_BOTTOM + 30
        legend_x = 60
        for seg in SEGMENT_NAMES:
            c = SEGMENT_COLORS_RGB[seg]
            draw.rectangle([legend_x, legend_y, legend_x + 12, legend_y + 12], fill=c)
            draw.text((legend_x + 18, legend_y - 2), seg, fill=(180, 180, 180), font=font_small)
            bbox = draw.textbbox((0, 0), seg, font=font_small)
            legend_x += 18 + (bbox[2] - bbox[0]) + 24

        # Time
        time_s = fi / EXTRACT_FPS
        draw.text((OUT_W - 100, GRAPH_BOTTOM + 30), f"{time_s:.1f}s",
                   fill=(120, 120, 120), font=font_label)

        # Brand
        draw.text((OUT_W - 180, OUT_H - 45), "wellBowled.ai", fill=PEACOCK, font=font_brand)

        canvas = cv2.cvtColor(np.array(pil), cv2.COLOR_RGB2BGR)
        cv2.imwrite(str(ANNOTATED_DIR / pd["frame"]), canvas, [cv2.IMWRITE_JPEG_QUALITY, 95])
        all_canvases.append(canvas)

    print(f"  [4] Rendered {len(all_canvases)} waterfall frames")
    return all_canvases


# ── Stage 5: Compose video ────────────────────────────────────────────
def compose_video(canvases: list[np.ndarray], vel_data: dict) -> Path:
    final_path = OUTPUT_DIR / "waterfall.mp4"
    delivery_end = vel_data["delivery_end"]
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
            text = "Watch the kinetic chain."
            bbox = d.textbbox((0, 0), text, font=f)
            tw = bbox[2] - bbox[0]
            d.rounded_rectangle([(OUT_W - tw) // 2 - 16, OUT_H - 140,
                                  (OUT_W + tw) // 2 + 16, OUT_H - 96],
                                 radius=10, fill=(0, 0, 0, 200))
            d.text(((OUT_W - tw) // 2, OUT_H - 136), text, fill=WHITE, font=f)
            c = cv2.cvtColor(np.array(pil), cv2.COLOR_RGB2BGR)

        for _ in range(3):
            all_frames.append(c)

    # Segment 2: Slo-mo with waterfall (0.25x)
    for canvas in canvases:
        for _ in range(12):
            all_frames.append(canvas)

    # Segment 3: Freeze on peak wrist velocity (2s)
    peak_idx = vel_data["peak_wrist_frame"]
    if peak_idx < len(canvases):
        peak_frame = canvases[peak_idx]
        pil = Image.fromarray(cv2.cvtColor(peak_frame, cv2.COLOR_BGR2RGB))
        d = ImageDraw.Draw(pil)
        f = load_font(28, bold=True)

        badge = "PEAK WRIST VELOCITY"
        bbox = d.textbbox((0, 0), badge, font=f)
        tw = bbox[2] - bbox[0]
        bx = (OUT_W - tw) // 2 - 16
        by = int(OUT_H * 0.30)
        d.rounded_rectangle([bx, by, bx + tw + 32, by + 48], radius=12,
                             fill=(0, 0, 0, 220), outline=(255, 0, 255), width=2)
        d.text((bx + 16, by + 10), badge, fill=(255, 0, 255), font=f)

        # Show peak order
        f_sm = load_font(20, bold=False)
        order_y = by + 65
        ox = OUT_W // 2 - 140
        for seg_name, frame_idx in vel_data["peak_order"]:
            c_rgb = SEGMENT_COLORS_RGB[seg_name]
            d.ellipse([ox, order_y, ox + 16, order_y + 16], fill=c_rgb)
            d.text((ox + 24, order_y - 2), f"{seg_name}: frame {frame_idx}",
                    fill=(200, 200, 200), font=f_sm)
            order_y += 28

        peak_canvas = cv2.cvtColor(np.array(pil), cv2.COLOR_RGB2BGR)
        for _ in range(2 * FPS):
            all_frames.append(peak_canvas)

    # Segment 4: Verdict card (2.5s)
    verdict_pil = Image.new("RGB", (OUT_W, OUT_H), DARK_BG)
    d = ImageDraw.Draw(verdict_pil)
    f_big = load_font(42, bold=True)
    f_med = load_font(30, bold=False)
    f_sm = load_font(22, bold=False)

    y = OUT_H // 2 - 180
    d.text((OUT_W // 2 - 220, y), "KINETIC CHAIN ANALYSIS", fill=WHITE, font=f_big)
    y += 70

    # Peak order display
    for seg_name, frame_idx in vel_data["peak_order"]:
        c_rgb = SEGMENT_COLORS_RGB[seg_name]
        d.ellipse([OUT_W // 2 - 200, y + 4, OUT_W // 2 - 184, y + 20], fill=c_rgb)
        d.text((OUT_W // 2 - 170, y), f"{seg_name}  →  frame {frame_idx}",
                fill=(200, 200, 200), font=f_sm)
        y += 36

    y += 30
    if vel_data["sequencing_correct"]:
        d.text((OUT_W // 2 - 180, y), "ELITE SEQUENCING", fill=(0, 200, 0), font=f_med)
        y += 45
        d.text((OUT_W // 2 - 200, y), "Sequential energy transfer —",
                fill=(160, 160, 160), font=f_sm)
        y += 30
        d.text((OUT_W // 2 - 200, y), "the hallmark of express pace.",
                fill=(160, 160, 160), font=f_sm)
    else:
        d.text((OUT_W // 2 - 170, y), "BLOCKED ROTATION", fill=(220, 80, 80), font=f_med)
        y += 45
        d.text((OUT_W // 2 - 200, y), "Simultaneous segment activation —",
                fill=(160, 160, 160), font=f_sm)
        y += 30
        d.text((OUT_W // 2 - 200, y), "velocity is being leaked.",
                fill=(160, 160, 160), font=f_sm)

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

    for label, t in [("intro", 0.5), ("waterfall_early", duration * 0.2),
                     ("waterfall_mid", duration * 0.4), ("peak", duration * 0.6),
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
    print("  VELOCITY WATERFALL PIPELINE")
    print("=" * 50)

    frames, meta = extract_frames()
    pose_data = extract_all_poses(frames)
    vel_data = compute_velocities(pose_data)
    canvases = render_waterfall_frames(pose_data, vel_data)
    video_path = compose_video(canvases, vel_data)
    review(video_path)

    elapsed = time.time() - start
    print(f"\n{'=' * 50}")
    print(f"  DONE in {elapsed:.1f}s")
    print(f"  Video: {video_path}")
    print(f"{'=' * 50}")


if __name__ == "__main__":
    main()
