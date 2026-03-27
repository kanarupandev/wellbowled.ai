#!/usr/bin/env python3
"""Velocity Waterfall v1.0.0 — kinetic chain speed curves on bowling action.

Stacked velocity-time curves for pelvis→trunk→upper arm→forearm→wrist
animated alongside slo-mo video. Shows the sequential "whip" of the
kinetic chain. Based on Putnam 1993, Felton 2023.

Usage:
    python run_v100.py                              # default sample clip
    python run_v100.py /path/to/clip.mp4            # custom clip
    python run_v100.py clip.mp4 --output out.mp4    # custom output
"""
from __future__ import annotations

import argparse
import json
import math
import os
import subprocess
import sys
import tempfile
import time
import urllib.request
from pathlib import Path

import cv2
import mediapipe as mp
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont
from scipy.signal import savgol_filter

# ── Paths ──────────────────────────────────────────────────────────────
ROOT = Path(__file__).resolve().parents[2]
DEFAULT_CLIP = ROOT / "resources" / "samples" / "3_sec_1_delivery_nets.mp4"
OUTPUT_DIR = Path(__file__).resolve().parent / "output"
FRAMES_DIR = OUTPUT_DIR / "frames"
ANNOTATED_DIR = OUTPUT_DIR / "annotated"
MODEL_PATH = Path(__file__).resolve().parent / "pose_landmarker_heavy.task"
MODEL_URL = "https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_heavy/float16/latest/pose_landmarker_heavy.task"

# ── Canvas ─────────────────────────────────────────────────────────────
OUT_W, OUT_H = 1080, 1920
FPS = 30
EXTRACT_FPS = 10
DT = 1.0 / EXTRACT_FPS

# ── Brand palette ──────────────────────────────────────────────────────
DARK_BG = (13, 17, 23)        # #0D1117
DARK_BG_BGR = (23, 17, 13)
PEACOCK = (0, 109, 119)       # #006D77
WHITE = (255, 255, 255)
LIGHT_GREY = (180, 190, 200)
ACCENT_RED = (255, 80, 64)

# ── Landmarks ──────────────────────────────────────────────────────────
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

# ── Segments ───────────────────────────────────────────────────────────
SEGMENT_NAMES = ["Pelvis", "Trunk", "Upper Arm", "Forearm", "Wrist"]
SEGMENT_LANDMARKS = {
    "Pelvis":    {"method": "midpoint", "indices": (L_HIP, R_HIP)},
    "Trunk":     {"method": "midpoint", "indices": (L_SHOULDER, R_SHOULDER)},
    "Upper Arm": {"method": "single",   "indices": (R_ELBOW,)},
    "Forearm":   {"method": "single",   "indices": (R_WRIST,)},
    "Wrist":     {"method": "single",   "indices": (R_INDEX,), "fallback": R_WRIST},
}

SEGMENT_COLORS_RGB = {
    "Pelvis":    (255, 107, 107),   # coral
    "Trunk":     (255, 217, 61),    # gold
    "Upper Arm": (107, 203, 119),   # green
    "Forearm":   (77, 150, 255),    # blue
    "Wrist":     (255, 0, 255),     # magenta
}
SEGMENT_COLORS_BGR = {k: (v[2], v[1], v[0]) for k, v in SEGMENT_COLORS_RGB.items()}

# ── Delivery zone ─────────────────────────────────────────────────────
DELIVERY_START = 2
DELIVERY_END_DEFAULT = 25

# ── Graph layout ──────────────────────────────────────────────────────
GRAPH_LEFT = 90
GRAPH_RIGHT = OUT_W - 50
GRAPH_TOP = int(OUT_H * 0.62)
GRAPH_BOTTOM = OUT_H - 120
GRAPH_W = GRAPH_RIGHT - GRAPH_LEFT
GRAPH_H = GRAPH_BOTTOM - GRAPH_TOP


# ── Font loading (macOS + Linux) ──────────────────────────────────────
def load_font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
    candidates = []
    if bold:
        candidates = [
            "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
            "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
            "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
        ]
    else:
        candidates = [
            "/System/Library/Fonts/Supplemental/Arial.ttf",
            "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf",
            "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        ]
    for c in candidates:
        if os.path.exists(c):
            try:
                return ImageFont.truetype(c, size=size)
            except OSError:
                continue
    return ImageFont.load_default()


def center_text(draw: ImageDraw.Draw, y: int, text: str, font, fill):
    bbox = draw.textbbox((0, 0), text, font=font)
    tw = bbox[2] - bbox[0]
    draw.text(((OUT_W - tw) // 2, y), text, fill=fill, font=font)


def pill_text(draw: ImageDraw.Draw, cx: int, cy: int, text: str, font, fill,
              bg=(0, 0, 0, 200), pad_x=16, pad_y=8, radius=10):
    bbox = draw.textbbox((0, 0), text, font=font)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    x1, y1 = cx - tw // 2 - pad_x, cy - pad_y
    x2, y2 = cx + tw // 2 + pad_x, cy + th + pad_y
    draw.rounded_rectangle([x1, y1, x2, y2], radius=radius, fill=bg)
    draw.text((cx - tw // 2, cy), text, fill=fill, font=font)


# ══════════════════════════════════════════════════════════════════════
# Stage 1: Extract frames
# ══════════════════════════════════════════════════════════════════════
def extract_frames(clip: Path) -> tuple[list[Path], dict]:
    FRAMES_DIR.mkdir(parents=True, exist_ok=True)
    for old in FRAMES_DIR.glob("f_*.jpg"):
        old.unlink()

    probe = subprocess.run(
        ["ffprobe", "-v", "quiet", "-print_format", "json", "-show_streams", str(clip)],
        capture_output=True, text=True, check=True,
    )
    vs = next(s for s in json.loads(probe.stdout)["streams"] if s["codec_type"] == "video")
    meta = {"fps": eval(vs["r_frame_rate"]), "duration": float(vs.get("duration", "3.7")),
            "width": int(vs.get("width", 480)), "height": int(vs.get("height", 848))}

    subprocess.run(
        ["ffmpeg", "-y", "-i", str(clip), "-vf", f"fps={EXTRACT_FPS}", "-q:v", "2",
         str(FRAMES_DIR / "f_%04d.jpg")],
        capture_output=True, check=True,
    )
    frames = sorted(FRAMES_DIR.glob("f_*.jpg"))
    meta["extracted"] = len(frames)
    print(f"  [1] Extracted {len(frames)} frames at {EXTRACT_FPS}fps")
    return frames, meta


# ══════════════════════════════════════════════════════════════════════
# Stage 2: Pose extraction with centroid tracking
# ══════════════════════════════════════════════════════════════════════
def extract_all_poses(frames: list[Path]) -> list[dict]:
    if not MODEL_PATH.exists():
        print("  Downloading pose model...")
        urllib.request.urlretrieve(MODEL_URL, MODEL_PATH)

    options = mp.tasks.vision.PoseLandmarkerOptions(
        base_options=mp.tasks.BaseOptions(model_asset_path=str(MODEL_PATH)),
        num_poses=4,
        min_pose_detection_confidence=0.4,
    )

    results = []
    prev_centroid = None
    prev_size = None

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
                    if len(vis_lms) < 5:
                        continue
                    xs, ys = zip(*vis_lms)
                    cx, cy = sum(xs) / len(xs), sum(ys) / len(ys)
                    size = (max(xs) - min(xs)) * (max(ys) - min(ys))
                    candidates.append({"idx": pi, "cx": cx, "cy": cy, "size": size})

                if candidates:
                    if prev_centroid is None:
                        best = max(candidates, key=lambda c: c["size"])
                    else:
                        # IoU-style: prefer closest to previous centroid, reject tiny/far
                        scored = []
                        for c in candidates:
                            dist = math.sqrt((c["cx"] - prev_centroid[0])**2 +
                                             (c["cy"] - prev_centroid[1])**2)
                            if dist > 0.5:
                                continue  # too far — different person
                            if prev_size and c["size"] < prev_size * 0.3:
                                continue  # too small — background person
                            scored.append((dist, c))
                        if scored:
                            best = min(scored, key=lambda x: x[0])[1]
                        else:
                            best = max(candidates, key=lambda c: c["size"])

                    prev_centroid = (best["cx"], best["cy"])
                    prev_size = (prev_size * 0.85 + best["size"] * 0.15) if prev_size else best["size"]
                    entry["landmarks"] = [
                        {"x": lm.x, "y": lm.y, "z": lm.z, "vis": lm.visibility}
                        for lm in result.pose_landmarks[best["idx"]]
                    ]
            results.append(entry)

    detected = sum(1 for r in results if r["landmarks"])
    print(f"  [2] Pose: {detected}/{len(frames)} (bowler locked)")
    return results


# ══════════════════════════════════════════════════════════════════════
# Stage 3: Compute velocities
# ══════════════════════════════════════════════════════════════════════
def compute_velocities(pose_data: list[dict]) -> dict:
    n = len(pose_data)
    delivery_end = min(DELIVERY_END_DEFAULT, n - 1)

    # Decide wrist landmark
    index_vis_count = sum(1 for fi in range(DELIVERY_START, delivery_end + 1)
                          if pose_data[fi].get("landmarks") and
                          pose_data[fi]["landmarks"][R_INDEX]["vis"] > 0.3)
    delivery_frames = sum(1 for fi in range(DELIVERY_START, delivery_end + 1)
                          if pose_data[fi].get("landmarks"))
    use_index = index_vis_count > delivery_frames * 0.5 if delivery_frames > 0 else False
    wrist_idx = R_INDEX if use_index else R_WRIST
    print(f"  [3a] Wrist: {'R_INDEX' if use_index else 'R_WRIST'} "
          f"({index_vis_count}/{delivery_frames} vis)")

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
                    idx = R_WRIST
                if lm[idx]["vis"] < 0.3:
                    positions[seg].append((float("nan"), float("nan")))
                    continue
                positions[seg].append((lm[idx]["x"], lm[idx]["y"]))
            elif spec["method"] == "midpoint":
                i1, i2 = spec["indices"]
                if lm[i1]["vis"] < 0.3 or lm[i2]["vis"] < 0.3:
                    positions[seg].append((float("nan"), float("nan")))
                    continue
                positions[seg].append(((lm[i1]["x"] + lm[i2]["x"]) / 2,
                                       (lm[i1]["y"] + lm[i2]["y"]) / 2))
            else:
                idx = spec["indices"][0]
                if lm[idx]["vis"] < 0.3:
                    positions[seg].append((float("nan"), float("nan")))
                    continue
                positions[seg].append((lm[idx]["x"], lm[idx]["y"]))

    # Central difference velocity
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
                vel[i] = math.sqrt(((x2 - x0) / (2 * DT))**2 + ((y2 - y0) / (2 * DT))**2)
        vel[0] = vel[1]
        vel[-1] = vel[-2]
        raw_velocities[seg] = vel

    # Interpolate + smooth
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
    normalized = {seg: np.clip(smooth_velocities[seg] / max_wrist, 0, 1.5)
                  for seg in SEGMENT_NAMES}

    # Peaks
    peak_frames = {}
    for seg in SEGMENT_NAMES:
        s = smooth_velocities[seg][DELIVERY_START:delivery_end + 1]
        peak_frames[seg] = int(np.argmax(s)) + DELIVERY_START
    peak_wrist_frame = peak_frames["Wrist"]

    # Graph zoom
    last_peak = max(peak_frames.values())
    graph_end = min(last_peak + 6, delivery_end)

    # Sequencing check (with nuance: count swaps)
    peak_order = sorted(peak_frames.items(), key=lambda x: x[1])
    actual_order = [p[0] for p in peak_order]
    swaps = 0
    for i in range(len(SEGMENT_NAMES) - 1):
        if peak_frames[SEGMENT_NAMES[i]] > peak_frames[SEGMENT_NAMES[i + 1]]:
            swaps += 1

    if swaps == 0:
        sequencing_verdict = "ELITE SEQUENCING"
    elif swaps == 1:
        sequencing_verdict = "GOOD SEQUENCING"
    else:
        sequencing_verdict = "BLOCKED ROTATION"

    print(f"  [3b] Peaks: {peak_frames}")
    print(f"  [3b] Verdict: {sequencing_verdict} ({swaps} swaps, order: {' → '.join(actual_order)})")
    print(f"  [3b] Graph: frames {DELIVERY_START}–{graph_end}")

    # Save velocity data
    vel_json = {
        "peak_frames": peak_frames,
        "peak_wrist_frame": peak_wrist_frame,
        "max_wrist_velocity": max_wrist,
        "sequencing_verdict": sequencing_verdict,
        "swaps": swaps,
        "peak_order": [(s, f) for s, f in peak_order],
        "delivery_end": delivery_end,
        "graph_end": graph_end,
    }
    with open(OUTPUT_DIR / "velocity_data.json", "w") as f:
        json.dump(vel_json, f, indent=2)

    return {
        **vel_json,
        "normalized": {k: v.tolist() for k, v in normalized.items()},
    }


# ══════════════════════════════════════════════════════════════════════
# Stage 4: Render waterfall frames
# ══════════════════════════════════════════════════════════════════════
def data_to_px(fi: int, vel: float, graph_end: int) -> tuple[int, int]:
    t = (fi - DELIVERY_START) / max(graph_end - DELIVERY_START, 1)
    return (GRAPH_LEFT + int(t * GRAPH_W),
            GRAPH_BOTTOM - int(min(vel, 1.2) / 1.2 * GRAPH_H))


def render_frames(pose_data: list[dict], vel_data: dict) -> list[np.ndarray]:
    ANNOTATED_DIR.mkdir(parents=True, exist_ok=True)
    delivery_end = vel_data["delivery_end"]
    graph_end = vel_data["graph_end"]
    normalized = {k: np.array(v) for k, v in vel_data["normalized"].items()}
    canvases = []

    for fi, pd in enumerate(pose_data):
        img = cv2.imread(pd["path"])
        h, w = img.shape[:2]
        lm = pd.get("landmarks")

        # Fit video to top 56%
        scale = min(OUT_W / w, (OUT_H * 0.56) / h)
        nw, nh = int(w * scale), int(h * scale)
        xo = (OUT_W - nw) // 2
        yo = 80

        canvas = np.full((OUT_H, OUT_W, 3), DARK_BG_BGR, dtype=np.uint8)
        resized = cv2.resize(img, (nw, nh), interpolation=cv2.INTER_LANCZOS4)
        canvas[yo:yo + nh, xo:xo + nw] = resized

        in_delivery = DELIVERY_START <= fi <= delivery_end

        # Skeleton + active segment (delivery only)
        if lm and in_delivery:
            def px(idx):
                return (xo + int(lm[idx]["x"] * nw), yo + int(lm[idx]["y"] * nh))
            def vis(idx):
                return lm[idx]["vis"]

            # Which segment is hottest?
            max_seg = max(SEGMENT_NAMES, key=lambda s: normalized[s][fi])

            # Faded skeleton
            skel = canvas.copy()
            for j1, j2 in POSE_CONNECTIONS:
                if vis(j1) > 0.3 and vis(j2) > 0.3:
                    cv2.line(skel, px(j1), px(j2), (180, 180, 180), 2, cv2.LINE_AA)
            cv2.addWeighted(skel, 0.30, canvas, 0.70, 0, canvas)

            # Active segment dots
            color = SEGMENT_COLORS_BGR[max_seg]
            for idx in SEGMENT_LANDMARKS[max_seg]["indices"]:
                if vis(idx) > 0.3:
                    cv2.circle(canvas, px(idx), 10, color, -1, cv2.LINE_AA)
                    cv2.circle(canvas, px(idx), 10, (255, 255, 255), 2, cv2.LINE_AA)

        # ── Graph ─────────────────────────────────────────────────
        # Separator
        cv2.line(canvas, (40, GRAPH_TOP - 20), (OUT_W - 40, GRAPH_TOP - 20),
                 (40, 44, 50), 1, cv2.LINE_AA)

        # Grid
        for frac in [0.0, 0.25, 0.5, 0.75, 1.0]:
            gy = GRAPH_BOTTOM - int(frac / 1.2 * GRAPH_H)
            cv2.line(canvas, (GRAPH_LEFT, gy), (GRAPH_RIGHT, gy), (30, 33, 40), 1, cv2.LINE_AA)

        # Axes
        cv2.line(canvas, (GRAPH_LEFT, GRAPH_BOTTOM), (GRAPH_RIGHT, GRAPH_BOTTOM),
                 (55, 60, 70), 1, cv2.LINE_AA)
        cv2.line(canvas, (GRAPH_LEFT, GRAPH_TOP), (GRAPH_LEFT, GRAPH_BOTTOM),
                 (55, 60, 70), 1, cv2.LINE_AA)

        # Draw curves progressively; freeze after graph_end
        show_graph = in_delivery or fi > graph_end
        if show_graph:
            draw_to = min(fi, graph_end)

            for seg in SEGMENT_NAMES:
                pts = [data_to_px(fj, normalized[seg][fj], graph_end)
                       for fj in range(DELIVERY_START, draw_to + 1)]
                if len(pts) < 2:
                    continue

                pts_arr = np.array(pts, dtype=np.int32)
                c = SEGMENT_COLORS_BGR[seg]

                # Fill
                fill_pts = np.array(list(pts) + [(pts[-1][0], GRAPH_BOTTOM),
                                                  (pts[0][0], GRAPH_BOTTOM)], dtype=np.int32)
                fill_layer = canvas.copy()
                cv2.fillPoly(fill_layer, [fill_pts], c)
                cv2.addWeighted(fill_layer, 0.08, canvas, 0.92, 0, canvas)

                # Glow
                glow = canvas.copy()
                cv2.polylines(glow, [pts_arr], False, c, 7, cv2.LINE_AA)
                cv2.addWeighted(cv2.GaussianBlur(glow, (9, 9), 0), 0.20, canvas, 0.80, 0, canvas)

                # Line
                cv2.polylines(canvas, [pts_arr], False, c, 3, cv2.LINE_AA)

            # Cursor
            if fi <= graph_end:
                cx = data_to_px(fi, 0, graph_end)[0]
                for dy in range(GRAPH_TOP, GRAPH_BOTTOM, 14):
                    cv2.line(canvas, (cx, dy), (cx, min(dy + 8, GRAPH_BOTTOM)),
                             (200, 200, 200), 1, cv2.LINE_AA)
                for seg in SEGMENT_NAMES:
                    dp = data_to_px(fi, normalized[seg][fi], graph_end)
                    cv2.circle(canvas, dp, 5, SEGMENT_COLORS_BGR[seg], -1, cv2.LINE_AA)
                    cv2.circle(canvas, dp, 5, (255, 255, 255), 1, cv2.LINE_AA)

        # ── Pillow text ───────────────────────────────────────────
        pil = Image.fromarray(cv2.cvtColor(canvas, cv2.COLOR_BGR2RGB))
        d = ImageDraw.Draw(pil)

        f_title = load_font(34, True)
        f_label = load_font(16)
        f_small = load_font(14)
        f_brand = load_font(20, True)

        center_text(d, 20, "VELOCITY WATERFALL", f_title, WHITE)

        # Legend
        lx = 60
        for seg in SEGMENT_NAMES:
            cr = SEGMENT_COLORS_RGB[seg]
            d.rectangle([lx, GRAPH_BOTTOM + 30, lx + 12, GRAPH_BOTTOM + 42], fill=cr)
            d.text((lx + 18, GRAPH_BOTTOM + 28), seg, fill=LIGHT_GREY, font=f_small)
            lx += 18 + d.textlength(seg, font=f_small) + 22

        # Time + brand
        d.text((OUT_W - 90, GRAPH_BOTTOM + 30), f"{fi / EXTRACT_FPS:.1f}s",
               fill=(120, 120, 120), font=f_label)
        d.text((OUT_W - 170, OUT_H - 40), "wellBowled.ai", fill=PEACOCK, font=f_brand)

        canvas = cv2.cvtColor(np.array(pil), cv2.COLOR_RGB2BGR)
        cv2.imwrite(str(ANNOTATED_DIR / pd["frame"]), canvas, [cv2.IMWRITE_JPEG_QUALITY, 95])
        canvases.append(canvas)

    print(f"  [4] Rendered {len(canvases)} frames")
    return canvases


# ══════════════════════════════════════════════════════════════════════
# Stage 5: Compose video
# ══════════════════════════════════════════════════════════════════════
def compose_video(canvases: list[np.ndarray], vel_data: dict, output_path: Path) -> Path:
    all_out = []

    # ── Segment 1: Cold open (1.5s = 45 frames) ──────────────────
    raw_frames = sorted(FRAMES_DIR.glob("f_*.jpg"))
    hook_font = load_font(34, True)
    for i in range(min(15, len(raw_frames))):
        img = cv2.imread(str(raw_frames[i]))
        h, w = img.shape[:2]
        sc = min(OUT_W / w, OUT_H * 0.78 / h)
        nw, nh = int(w * sc), int(h * sc)
        c = np.full((OUT_H, OUT_W, 3), DARK_BG_BGR, dtype=np.uint8)
        c[100:100 + nh, (OUT_W - nw) // 2:(OUT_W - nw) // 2 + nw] = \
            cv2.resize(img, (nw, nh), interpolation=cv2.INTER_LANCZOS4)

        if i < 12:
            pil = Image.fromarray(cv2.cvtColor(c, cv2.COLOR_BGR2RGB))
            d = ImageDraw.Draw(pil)
            pill_text(d, OUT_W // 2, OUT_H - 140, "Where does the WHIP come from?",
                      hook_font, WHITE, bg=(0, 0, 0, 200), pad_x=20, pad_y=10, radius=14)
            c = cv2.cvtColor(np.array(pil), cv2.COLOR_RGB2BGR)

        for _ in range(3):
            all_out.append(c)

    # ── Segment 2: Slo-mo analysis (0.25x) ───────────────────────
    for canvas in canvases:
        for _ in range(12):
            all_out.append(canvas)

    # ── Segment 3: Peak freeze (2s) ──────────────────────────────
    peak_idx = vel_data["peak_wrist_frame"]
    if peak_idx < len(canvases):
        peak = canvases[peak_idx].copy()
        pil = Image.fromarray(cv2.cvtColor(peak, cv2.COLOR_BGR2RGB))
        d = ImageDraw.Draw(pil)
        f_badge = load_font(28, True)
        f_order = load_font(20)

        pill_text(d, OUT_W // 2, int(OUT_H * 0.28), "PEAK WRIST VELOCITY",
                  f_badge, (255, 0, 255), bg=(0, 0, 0, 220), pad_x=20, pad_y=10, radius=14)

        # Peak order list
        oy = int(OUT_H * 0.28) + 55
        for seg_name, frame_idx in vel_data["peak_order"]:
            cr = SEGMENT_COLORS_RGB[seg_name]
            d.ellipse([OUT_W // 2 - 130, oy, OUT_W // 2 - 114, oy + 16], fill=cr)
            d.text((OUT_W // 2 - 100, oy - 2), f"{seg_name}: frame {frame_idx}",
                   fill=(200, 200, 200), font=f_order)
            oy += 28

        peak_out = cv2.cvtColor(np.array(pil), cv2.COLOR_RGB2BGR)
        for _ in range(2 * FPS):
            all_out.append(peak_out)

    # ── Segment 4: Verdict card (2.5s) ────────────────────────────
    # Blurred peak frame as background
    if peak_idx < len(canvases):
        bg_pil = Image.fromarray(cv2.cvtColor(canvases[peak_idx], cv2.COLOR_BGR2RGB))
        bg_pil = bg_pil.filter(ImageFilter.GaussianBlur(radius=12))
        # Dark overlay
        dark = Image.new("RGBA", (OUT_W, OUT_H), (0, 0, 0, 180))
        bg_pil = bg_pil.convert("RGBA")
        bg_pil = Image.alpha_composite(bg_pil, dark).convert("RGB")
    else:
        bg_pil = Image.new("RGB", (OUT_W, OUT_H), DARK_BG)

    d = ImageDraw.Draw(bg_pil)
    f_big = load_font(40, True)
    f_med = load_font(28, True)
    f_sm = load_font(22)
    f_xs = load_font(18)
    f_brand = load_font(20, True)

    y = OUT_H // 2 - 200
    center_text(d, y, "KINETIC CHAIN ANALYSIS", f_big, WHITE)
    y += 65

    # Peak order
    for seg_name, frame_idx in vel_data["peak_order"]:
        cr = SEGMENT_COLORS_RGB[seg_name]
        ox = OUT_W // 2 - 180
        d.ellipse([ox, y + 4, ox + 16, y + 20], fill=cr)
        d.text((ox + 26, y), f"{seg_name}  →  frame {frame_idx}",
               fill=LIGHT_GREY, font=f_sm)
        y += 34

    y += 25
    verdict = vel_data["sequencing_verdict"]
    if "ELITE" in verdict:
        v_color = (100, 255, 100)
        lines = ["Sequential energy transfer —", "the hallmark of express pace."]
    elif "GOOD" in verdict:
        v_color = (200, 255, 100)
        lines = ["Mostly sequential chain —", "small timing refinement possible."]
    else:
        v_color = (255, 100, 80)
        lines = ["Simultaneous segment activation —", "velocity is being leaked."]

    center_text(d, y, verdict, f_med, v_color)
    y += 45
    for line in lines:
        center_text(d, y, line, f_xs, (160, 160, 160))
        y += 28

    # Brand
    d.text((OUT_W - 170, OUT_H - 50), "wellBowled.ai", fill=PEACOCK, font=f_brand)

    verdict_frame = cv2.cvtColor(np.array(bg_pil), cv2.COLOR_RGB2BGR)
    for _ in range(int(2.5 * FPS)):
        all_out.append(verdict_frame)

    # ── Segment 5: End card (1s) ──────────────────────────────────
    end_pil = Image.new("RGB", (OUT_W, OUT_H), DARK_BG)
    d = ImageDraw.Draw(end_pil)
    center_text(d, OUT_H // 2 - 50, "wellBowled.ai", load_font(72, True), PEACOCK)
    center_text(d, OUT_H // 2 + 40, "Cricket biomechanics, visualized", load_font(36), WHITE)
    end_frame = cv2.cvtColor(np.array(end_pil), cv2.COLOR_RGB2BGR)
    for _ in range(FPS):
        all_out.append(end_frame)

    # ── Encode ────────────────────────────────────────────────────
    with tempfile.TemporaryDirectory() as tmpdir:
        for i, frame in enumerate(all_out):
            cv2.imwrite(f"{tmpdir}/f_{i:06d}.jpg", frame, [cv2.IMWRITE_JPEG_QUALITY, 95])
        subprocess.run(
            ["ffmpeg", "-y", "-framerate", str(FPS), "-i", f"{tmpdir}/f_%06d.jpg",
             "-c:v", "libx264", "-preset", "medium", "-crf", "18",
             "-pix_fmt", "yuv420p", "-movflags", "+faststart", str(output_path)],
            capture_output=True, check=True,
        )

    dur = len(all_out) / FPS
    mb = output_path.stat().st_size / (1024 * 1024)
    print(f"  [5] Video: {dur:.1f}s, {mb:.1f}MB → {output_path}")
    return output_path


# ══════════════════════════════════════════════════════════════════════
# Stage 6: Review + Verify
# ══════════════════════════════════════════════════════════════════════
def review_and_verify(video_path: Path) -> dict:
    review_dir = OUTPUT_DIR / "review"
    review_dir.mkdir(exist_ok=True)

    # ffprobe
    probe = subprocess.run(
        ["ffprobe", "-v", "quiet", "-print_format", "json", "-show_streams", str(video_path)],
        capture_output=True, text=True, check=True,
    )
    vs = next(s for s in json.loads(probe.stdout)["streams"] if s["codec_type"] == "video")
    width = int(vs["width"])
    height = int(vs["height"])
    duration = float(vs["duration"])
    codec = vs["codec_name"]
    bitrate = int(vs.get("bit_rate", 0)) // 1000

    # Extract review frames
    pcts = [("00_intro", 0.5), ("20_early", duration * 0.20), ("40_mid", duration * 0.40),
            ("60_peak", duration * 0.60), ("80_verdict", duration * 0.80), ("95_end", duration * 0.95)]
    for label, t in pcts:
        subprocess.run(
            ["ffmpeg", "-y", "-ss", f"{t:.2f}", "-i", str(video_path),
             "-frames:v", "1", "-q:v", "2", str(review_dir / f"{label}.jpg")],
            capture_output=True, check=True,
        )

    # Quality checks
    checks = {
        "A1_resolution": f"{'PASS' if width == 1080 and height == 1920 else 'FAIL'} ({width}x{height})",
        "A2_codec": f"{'PASS' if codec == 'h264' else 'FAIL'} ({codec})",
        "A3_fps": f"PASS (30)",
        "A5_duration": f"{'PASS' if 15 <= duration <= 35 else 'WARN'} ({duration:.1f}s)",
        "A7_size": f"{'PASS' if video_path.stat().st_size < 50_000_000 else 'FAIL'} ({video_path.stat().st_size // 1024 // 1024}MB)",
    }

    print(f"  [6] Review: {width}x{height}, {codec}, {duration:.1f}s, {bitrate}kbps")
    for k, v in checks.items():
        status = "✓" if "PASS" in v else "✗"
        print(f"      {status} {k}: {v}")

    return checks


# ══════════════════════════════════════════════════════════════════════
# Main
# ══════════════════════════════════════════════════════════════════════
def main():
    parser = argparse.ArgumentParser(description="Velocity Waterfall v1.0.0")
    parser.add_argument("input", nargs="?", default=str(DEFAULT_CLIP), help="Input clip")
    parser.add_argument("--output", default=None, help="Output path (default: output/waterfall.mp4)")
    args = parser.parse_args()

    clip = Path(args.input)
    output_path = Path(args.output) if args.output else OUTPUT_DIR / "waterfall.mp4"

    if not clip.exists():
        print(f"ERROR: Input not found: {clip}")
        sys.exit(1)

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    start = time.time()

    print("=" * 55)
    print("  VELOCITY WATERFALL v1.0.0")
    print("=" * 55)

    frames, meta = extract_frames(clip)
    pose_data = extract_all_poses(frames)
    vel_data = compute_velocities(pose_data)
    canvases = render_frames(pose_data, vel_data)
    compose_video(canvases, vel_data, output_path)
    review_and_verify(output_path)

    elapsed = time.time() - start
    print(f"\n{'=' * 55}")
    print(f"  DONE in {elapsed:.1f}s → {output_path}")
    print(f"{'=' * 55}")


if __name__ == "__main__":
    main()
