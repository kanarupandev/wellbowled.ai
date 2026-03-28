#!/usr/bin/env python3
"""Speed Gradient v1.0.0 — Energy transfer visualization for broadcast bowling clips.

Preprocessing:  Gemini Pro 3 → bowler ROI + BFC/FFC/release → crop → upscale
Analysis:       MediaPipe pose → velocity per joint → transfer points → leak levels
Visualization:  Run-up (uniform heat) → delivery (per-joint color) → verdict → end card

Usage:
    cd content/speed_gradient_pipeline
    python run_v100.py                                   # default clip
    python run_v100.py /path/to/broadcast_clip.mp4       # custom clip
"""
from __future__ import annotations

import argparse
import base64
import json
import logging
import math
import os
import shutil
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path

import cv2
import mediapipe as mp
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont
from scipy.signal import savgol_filter

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
PIPELINE_DIR = Path(__file__).resolve().parent
REPO_ROOT = PIPELINE_DIR.parents[1]
OUTPUT_DIR = PIPELINE_DIR / "output" / "v100"
MODEL_PATH = REPO_ROOT / "resources" / "pose_landmarker_heavy.task"
DEFAULT_CLIP = REPO_ROOT / "resources" / "samples" / "steyn_sa_vs_eng_broadcast_5sec.mp4"

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
OUT_W, OUT_H = 1080, 1920
FPS_OUT = 30
BG_DARK = (13, 17, 23)       # #0D1117
BRAND_TEAL = (0, 109, 119)   # #006D77

# Energy color ramp: cold (blue) → hot (red)
COLOR_RAMP = [
    (0.00, (30, 80, 220)),    # blue — cold
    (0.20, (0, 200, 220)),    # cyan
    (0.40, (50, 220, 50)),    # green
    (0.60, (255, 220, 0)),    # yellow
    (0.80, (255, 140, 0)),    # orange
    (1.00, (255, 40, 40)),    # red — max
]

# MediaPipe landmark indices
BODY_SEGMENTS = {
    "back_foot":  [27, 28],              # ankles
    "front_foot": [27, 28],              # same landmarks, distinguished by phase
    "hips":       [23, 24],              # L/R hip
    "trunk":      [11, 12],              # L/R shoulder
    "upper_arm":  [12, 14],              # R shoulder → R elbow
    "forearm":    [14, 16],              # R elbow → R wrist
    "wrist":      [16, 20],              # R wrist → R index (fallback 16 only)
}

# Joints for velocity computation (5 chain segments)
CHAIN_JOINTS = {
    "hips":      [23, 24],
    "trunk":     [11, 12],
    "upper_arm": [14],        # R elbow
    "forearm":   [16],        # R wrist
    "wrist":     [20, 16],    # R index, fallback R wrist
}

# Skeleton connections for drawing
SKELETON_CONNECTIONS = [
    (11, 12), (11, 13), (13, 15), (12, 14), (14, 16),
    (11, 23), (12, 24), (23, 24), (23, 25), (25, 27),
    (24, 26), (26, 28), (15, 17), (15, 19), (16, 18), (16, 20),
]

PRIMARY_JOINTS = [11, 12, 13, 14, 15, 16, 23, 24, 25, 26, 27, 28]

# Transfer points
TRANSFERS = [
    ("BFC → FFC",     "back_foot",  "front_foot"),
    ("FFC → Hips",    "front_foot", "hips"),
    ("Hips → Trunk",  "hips",       "trunk"),
    ("Trunk → Arm",   "trunk",      "wrist"),
]

log = logging.getLogger("speed_gradient")


# ===================================================================
# FONTS
# ===================================================================
def _load_font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
    candidates = []
    if sys.platform == "darwin":
        candidates += [
            "/System/Library/Fonts/Helvetica.ttc",
            "/Library/Fonts/Arial.ttf",
        ]
    candidates += [
        "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf" if bold
        else "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf" if bold
        else "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    ]
    for c in candidates:
        if Path(c).exists():
            try:
                return ImageFont.truetype(c, size=size)
            except OSError:
                pass
    return ImageFont.load_default()


FONT_TITLE = _load_font(34, bold=True)
FONT_LABEL = _load_font(20, bold=True)
FONT_SMALL = _load_font(16)
FONT_VERDICT_TITLE = _load_font(42, bold=True)
FONT_VERDICT_BODY = _load_font(24)
FONT_VERDICT_LEAK = _load_font(20, bold=True)
FONT_BRAND_BIG = _load_font(72, bold=True)
FONT_TAGLINE = _load_font(36)
FONT_BRAND_SMALL = _load_font(20, bold=True)
FONT_PHASE = _load_font(28, bold=True)


# ===================================================================
# GEMINI PRO 3 — Bowler ROI + delivery phases
# ===================================================================
def _load_api_key() -> str | None:
    key = os.environ.get("GEMINI_API_KEY")
    if key:
        return key
    for env_path in [
        REPO_ROOT / "linux_content_pipeline_work" / ".env",
        REPO_ROOT / ".env",
    ]:
        if env_path.exists():
            for line in env_path.read_text().splitlines():
                if line.startswith("GEMINI_API_KEY="):
                    return line.split("=", 1)[1].strip()
    return None


def _build_contact_sheet(frames_bgr: list[np.ndarray], fps: float) -> str:
    """Build a 3x2 contact sheet from 6 evenly spaced frames."""
    n = len(frames_bgr)
    indices = [int(n * i / 5) for i in range(6)]
    indices = [min(i, n - 1) for i in indices]

    cols, tile_w = 3, 320
    h_orig, w_orig = frames_bgr[0].shape[:2]
    tile_h = int(tile_w * h_orig / max(1, w_orig))
    gutter = 12
    rows = 2
    sheet_w = cols * tile_w + (cols + 1) * gutter
    sheet_h = 60 + rows * tile_h + (rows + 1) * gutter

    canvas = Image.new("RGB", (sheet_w, sheet_h), BG_DARK)
    draw = ImageDraw.Draw(canvas)
    font = _load_font(16, bold=True)
    draw.text((gutter, 16), "Broadcast Bowling Clip", font=_load_font(24, bold=True), fill=(240, 244, 248))

    for i, idx in enumerate(indices):
        row, col = i // cols, i % cols
        x = gutter + col * (tile_w + gutter)
        y = 60 + gutter + row * (tile_h + gutter)
        rgb = cv2.cvtColor(frames_bgr[idx], cv2.COLOR_BGR2RGB)
        tile = Image.fromarray(rgb).resize((tile_w, tile_h))
        canvas.paste(tile, (x, y))
        t = idx / fps
        draw.rounded_rectangle((x + 4, y + 4, x + 120, y + 28), radius=8, fill=BG_DARK)
        draw.text((x + 10, y + 6), f"F{i+1} {t:.2f}s", font=font, fill=(255, 255, 255))

    sheet_path = str(OUTPUT_DIR / "contact_sheet.jpg")
    canvas.save(sheet_path, quality=85)
    return sheet_path


def call_gemini(frames_bgr: list[np.ndarray], fps: float) -> dict | None:
    """Call Gemini Pro 3 to identify bowler ROI and delivery phases."""
    api_key = _load_api_key()
    if not api_key:
        log.warning("[gemini] No GEMINI_API_KEY — skipping")
        return None

    sheet_path = _build_contact_sheet(frames_bgr, fps)
    with open(sheet_path, "rb") as f:
        sheet_b64 = base64.b64encode(f.read()).decode("utf-8")

    n = len(frames_bgr)
    frame_list = "\n".join(
        f"- F{i+1}: {min(int(n * i / 5), n-1) / fps:.2f}s"
        for i in range(6)
    )

    prompt = f"""This contact sheet shows frames from a cricket bowling broadcast clip.
Frames labeled with timestamps:
{frame_list}

Identify the PRIMARY BOWLER (person delivering the ball). Ignore everyone else.

Return STRICT JSON only:
{{
  "bowler_roi": {{"x": 0.0, "y": 0.0, "w": 1.0, "h": 1.0}},
  "bowling_arm": "right|left",
  "phases": {{
    "back_foot_contact": 0.0,
    "front_foot_contact": 0.0,
    "release": 0.0,
    "follow_through": 0.0
  }},
  "bowler_description": "one sentence"
}}

Rules:
- bowler_roi: normalized bounding box (0-1) containing bowler across ALL frames. Add 15% padding.
- phases: timestamps in seconds. back_foot_contact and front_foot_contact are when each foot plants at the crease.
- Focus ONLY on the bowler. Ignore batsmen, fielders, umpires."""

    model = "gemini-2.5-pro-preview-06-05"
    payload = {
        "contents": [{"parts": [
            {"text": "Broadcast cricket bowling clip:"},
            {"inlineData": {"mimeType": "image/jpeg", "data": sheet_b64}},
            {"text": prompt},
        ]}],
        "generationConfig": {
            "temperature": 0.1,
            "responseMimeType": "application/json",
        },
    }

    url = (
        f"https://generativelanguage.googleapis.com/v1beta/models/{model}"
        f":generateContent?key={api_key}"
    )
    req = urllib.request.Request(
        url, data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
    )

    try:
        log.info("[gemini] Calling %s ...", model)
        with urllib.request.urlopen(req, timeout=120) as resp:
            response = json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        log.error("[gemini] HTTP %d: %s", exc.code, body[:300])
        return None
    except Exception as exc:
        log.error("[gemini] Error: %s", exc)
        return None

    try:
        text = response["candidates"][0]["content"]["parts"][0]["text"]
        result = json.loads(text)
    except (KeyError, IndexError, json.JSONDecodeError) as exc:
        log.error("[gemini] Parse failed: %s", exc)
        return None

    # Cache
    cache_path = OUTPUT_DIR / "gemini_plan.json"
    with cache_path.open("w") as f:
        json.dump({"result": result, "raw": response}, f, indent=2)

    log.info("[gemini] Bowler: %s", result.get("bowler_description", "?"))
    log.info("[gemini] ROI: %s", result.get("bowler_roi"))
    log.info("[gemini] Phases: %s", result.get("phases"))
    return result


# ===================================================================
# STAGE 1: Extract frames
# ===================================================================
def extract_frames(clip_path: str) -> tuple[list[np.ndarray], float]:
    """Read all frames from clip at native fps."""
    cap = cv2.VideoCapture(clip_path)
    fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
    frames = []
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        frames.append(frame)
    cap.release()
    log.info("[extract] %d frames at %.1f fps", len(frames), fps)
    return frames, fps


# ===================================================================
# STAGE 2: Crop + upscale
# ===================================================================
def crop_and_upscale(
    frames: list[np.ndarray], roi: dict | None, target_h: int = 720,
) -> list[np.ndarray]:
    """Crop to bowler ROI and upscale via bicubic interpolation."""
    if roi is None:
        log.info("[crop] No ROI — using full frame")
        cropped = frames
    else:
        h_full, w_full = frames[0].shape[:2]
        rx = max(0, int(roi["x"] * w_full))
        ry = max(0, int(roi["y"] * h_full))
        rw = min(w_full - rx, int(roi["w"] * w_full))
        rh = min(h_full - ry, int(roi["h"] * h_full))
        log.info("[crop] ROI: x=%d y=%d w=%d h=%d (from %dx%d)", rx, ry, rw, rh, w_full, h_full)
        cropped = [f[ry:ry+rh, rx:rx+rw] for f in frames]

    # Upscale to target height (preserve aspect)
    ch, cw = cropped[0].shape[:2]
    if ch >= target_h:
        log.info("[upscale] Already %dx%d — no upscale needed", cw, ch)
        return cropped

    scale = target_h / ch
    new_w = int(cw * scale)
    new_h = target_h
    log.info("[upscale] %dx%d → %dx%d (%.1fx bicubic)", cw, ch, new_w, new_h, scale)
    return [cv2.resize(f, (new_w, new_h), interpolation=cv2.INTER_CUBIC) for f in cropped]


# ===================================================================
# STAGE 3: Pose extraction
# ===================================================================
def extract_poses(frames: list[np.ndarray]) -> list[list[tuple] | None]:
    """Run MediaPipe on each frame. Returns list of 33-landmark lists or None."""
    if not MODEL_PATH.exists():
        raise FileNotFoundError(f"Model not found: {MODEL_PATH}")

    PoseLandmarker = mp.tasks.vision.PoseLandmarker
    PoseLandmarkerOptions = mp.tasks.vision.PoseLandmarkerOptions
    BaseOptions = mp.tasks.BaseOptions

    options = PoseLandmarkerOptions(
        base_options=BaseOptions(model_asset_path=str(MODEL_PATH)),
        running_mode=mp.tasks.vision.RunningMode.IMAGE,
        num_poses=4,
        min_pose_detection_confidence=0.4,
        min_tracking_confidence=0.4,
    )

    all_landmarks = []
    prev_bbox = None
    bowler_size = None

    with PoseLandmarker.create_from_options(options) as landmarker:
        for frame_bgr in frames:
            rgb = cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2RGB)
            result = landmarker.detect(mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb))

            chosen = None
            if result.pose_landmarks:
                best_score = -1.0
                for pose in result.pose_landmarks:
                    pts = [(p.x, p.y, p.visibility) for p in pose]
                    s = _score_pose(pts, prev_bbox, bowler_size)
                    if s > best_score:
                        best_score = s
                        chosen = pts

            if chosen is not None:
                bbox = _bbox_from_pts(chosen)
                if bbox:
                    prev_bbox = bbox
                    bowler_size = bbox["area"] if bowler_size is None else bowler_size * 0.85 + bbox["area"] * 0.15

            all_landmarks.append(chosen)

    detected = sum(1 for lm in all_landmarks if lm is not None)
    log.info("[pose] %d/%d frames with detections", detected, len(frames))
    return all_landmarks


def _bbox_from_pts(pts):
    xs = [pts[i][0] for i in PRIMARY_JOINTS if i < len(pts) and pts[i][2] > 0.3]
    ys = [pts[i][1] for i in PRIMARY_JOINTS if i < len(pts) and pts[i][2] > 0.3]
    if len(xs) < 6:
        return None
    x1, x2, y1, y2 = min(xs), max(xs), min(ys), max(ys)
    return {"x1": x1, "y1": y1, "x2": x2, "y2": y2,
            "cx": (x1+x2)/2, "cy": (y1+y2)/2, "area": (x2-x1)*(y2-y1)}


def _score_pose(pts, prev_bbox, bowler_size):
    bbox = _bbox_from_pts(pts)
    if bbox is None:
        return -1.0
    vis = sum(pts[i][2] for i in PRIMARY_JOINTS if i < len(pts)) / len(PRIMARY_JOINTS)
    if prev_bbox is None:
        return bbox["area"] * 5.0 + vis
    dist = ((bbox["cx"]-prev_bbox["cx"])**2 + (bbox["cy"]-prev_bbox["cy"])**2)**0.5
    if dist > 0.5:
        return -1.0
    if bowler_size and bbox["area"] < bowler_size * 0.3:
        return -1.0
    iou_val = _iou(bbox, prev_bbox)
    return iou_val * 12.0 + max(0, 3.0 - dist*6.0) + vis*0.5 + bbox["area"]


def _iou(a, b):
    ix1, iy1 = max(a["x1"], b["x1"]), max(a["y1"], b["y1"])
    ix2, iy2 = min(a["x2"], b["x2"]), min(a["y2"], b["y2"])
    inter = max(0, ix2-ix1) * max(0, iy2-iy1)
    union = a["area"] + b["area"] - inter
    return inter / max(1e-6, union)


# ===================================================================
# STAGE 4: Velocity computation
# ===================================================================
def compute_velocities(
    landmarks: list[list[tuple] | None], fps: float,
) -> dict:
    """Compute per-joint velocity via central difference + Savgol smooth.

    Returns dict:
        raw: {segment_name: np.array of velocities per frame}
        smoothed: {segment_name: np.array}
        normalized: {segment_name: np.array normalized 0-1}
        total_body: np.array of mean velocity across all joints per frame
    """
    n = len(landmarks)
    dt = 1.0 / fps

    # Extract positions per chain segment
    positions = {}  # segment -> list of (x, y) or None
    for seg, joint_ids in CHAIN_JOINTS.items():
        pos = []
        for lm in landmarks:
            if lm is None:
                pos.append(None)
                continue
            xs, ys, count = 0, 0, 0
            for jid in joint_ids:
                if jid < len(lm) and lm[jid][2] > 0.3:
                    xs += lm[jid][0]
                    ys += lm[jid][1]
                    count += 1
            if count > 0:
                pos.append((xs/count, ys/count))
            else:
                pos.append(None)
        positions[seg] = pos

    # Central difference velocity
    raw = {}
    for seg, pos in positions.items():
        vel = np.zeros(n)
        for i in range(n):
            if i == 0:
                # Forward difference
                if pos[0] is not None and pos[1] is not None:
                    dx = pos[1][0] - pos[0][0]
                    dy = pos[1][1] - pos[0][1]
                    vel[0] = math.sqrt(dx*dx + dy*dy) / dt
            elif i == n - 1:
                # Backward difference
                if pos[n-1] is not None and pos[n-2] is not None:
                    dx = pos[n-1][0] - pos[n-2][0]
                    dy = pos[n-1][1] - pos[n-2][1]
                    vel[n-1] = math.sqrt(dx*dx + dy*dy) / dt
            else:
                # Central difference
                if pos[i-1] is not None and pos[i+1] is not None:
                    dx = pos[i+1][0] - pos[i-1][0]
                    dy = pos[i+1][1] - pos[i-1][1]
                    vel[i] = math.sqrt(dx*dx + dy*dy) / (2*dt)
        # Interpolate NaN/zero gaps
        vel = np.clip(vel, 0, None)
        raw[seg] = vel

    # Savgol smooth — adapt window to data length
    smoothed = {}
    for seg, vel in raw.items():
        win = min(7, len(vel))
        if win % 2 == 0:
            win -= 1
        win = max(3, win)
        poly = min(2, win - 1)
        smoothed[seg] = savgol_filter(vel, win, poly)
        smoothed[seg] = np.clip(smoothed[seg], 0, None)

    # Normalize to max wrist velocity
    max_wrist = max(smoothed.get("wrist", [0]).max(), 1e-6)
    normalized = {}
    for seg, vel in smoothed.items():
        normalized[seg] = vel / max_wrist

    # Total body velocity (mean of all segments, for run-up uniform coloring)
    total = np.zeros(n)
    for seg in smoothed:
        total += smoothed[seg]
    total /= max(len(smoothed), 1)
    total_norm = total / max(total.max(), 1e-6)

    return {
        "raw": raw,
        "smoothed": smoothed,
        "normalized": normalized,
        "total_body": total_norm,
    }


# ===================================================================
# STAGE 5: Transfer point detection + leak computation
# ===================================================================
def detect_transfers(
    velocities: dict,
    gemini_phases: dict | None,
    fps: float,
    n_frames: int,
) -> dict:
    """Detect BFC/FFC from Gemini + velocity peaks. Compute leak levels.

    Returns dict with:
        bfc_frame, ffc_frame, release_frame: int
        peaks: {segment: peak_frame_index}
        leaks: [(name, level, frame_gap), ...]  level = 0/1/2 (minimal/moderate/major)
    """
    norm = velocities["normalized"]

    # Phase frames from Gemini
    bfc_frame = ffc_frame = release_frame = None
    if gemini_phases:
        phases = gemini_phases.get("phases", {})
        bfc_frame = int(phases.get("back_foot_contact", 0) * fps) if phases.get("back_foot_contact") else None
        ffc_frame = int(phases.get("front_foot_contact", 0) * fps) if phases.get("front_foot_contact") else None
        release_frame = int(phases.get("release", 0) * fps) if phases.get("release") else None

    # Clamp to valid range
    for var_name in ["bfc_frame", "ffc_frame", "release_frame"]:
        val = locals()[var_name]
        if val is not None:
            val = max(0, min(val, n_frames - 1))
            if var_name == "bfc_frame": bfc_frame = val
            elif var_name == "ffc_frame": ffc_frame = val
            elif var_name == "release_frame": release_frame = val

    # Fallback: use velocity peaks if Gemini didn't provide
    if bfc_frame is None:
        bfc_frame = max(0, n_frames // 3)
    if ffc_frame is None:
        ffc_frame = max(bfc_frame + 2, int(n_frames * 0.5))
    if release_frame is None:
        release_frame = max(ffc_frame + 2, int(n_frames * 0.7))

    # Find peak frame per segment (within delivery window: BFC to end)
    delivery_start = max(0, bfc_frame - 2)
    delivery_end = min(n_frames, release_frame + 5)
    peaks = {}
    for seg in ["hips", "trunk", "upper_arm", "forearm", "wrist"]:
        if seg in norm:
            window = norm[seg][delivery_start:delivery_end]
            if len(window) > 0:
                peaks[seg] = delivery_start + int(np.argmax(window))
            else:
                peaks[seg] = delivery_start

    # Leak computation: frame gap between consecutive peaks
    chain_order = ["hips", "trunk", "upper_arm", "forearm", "wrist"]
    transfer_names = ["BFC → FFC", "FFC → Hips", "Hips → Trunk", "Trunk → Arm"]

    # For BFC→FFC, use phase frames directly
    leaks = []

    # Transfer 1: BFC → FFC
    gap1 = abs(ffc_frame - bfc_frame)
    leaks.append(("BFC → FFC", _classify_leak(gap1), gap1))

    # Transfer 2: FFC → Hips
    gap2 = abs(peaks.get("hips", ffc_frame) - ffc_frame)
    leaks.append(("FFC → Hips", _classify_leak(gap2), gap2))

    # Transfer 3: Hips → Trunk
    gap3 = abs(peaks.get("trunk", 0) - peaks.get("hips", 0))
    leaks.append(("Hips → Trunk", _classify_leak(gap3), gap3))

    # Transfer 4: Trunk → Arm (trunk peak → wrist peak)
    gap4 = abs(peaks.get("wrist", 0) - peaks.get("trunk", 0))
    leaks.append(("Trunk → Arm", _classify_leak(gap4), gap4))

    log.info("[transfers] BFC=%d FFC=%d Release=%d", bfc_frame, ffc_frame, release_frame)
    log.info("[transfers] Peaks: %s", peaks)
    for name, level, gap in leaks:
        log.info("[transfers] %s: level=%d gap=%d frames", name, level, gap)

    return {
        "bfc_frame": bfc_frame,
        "ffc_frame": ffc_frame,
        "release_frame": release_frame,
        "peaks": peaks,
        "leaks": leaks,
    }


def _classify_leak(frame_gap: int) -> int:
    """0=minimal, 1=moderate, 2=major."""
    if frame_gap <= 2:
        return 0
    elif frame_gap <= 4:
        return 1
    else:
        return 2


# ===================================================================
# COLOR HELPERS
# ===================================================================
def energy_color(t: float) -> tuple[int, int, int]:
    """Map normalized velocity (0-1) to color via ramp."""
    t = max(0.0, min(1.0, t))
    for i in range(len(COLOR_RAMP) - 1):
        t0, c0 = COLOR_RAMP[i]
        t1, c1 = COLOR_RAMP[i + 1]
        if t0 <= t <= t1:
            f = (t - t0) / max(1e-6, t1 - t0)
            return tuple(int(c0[j] + f * (c1[j] - c0[j])) for j in range(3))
    return COLOR_RAMP[-1][1]


def leak_visual(level: int) -> tuple[int, tuple[int, int, int]]:
    """Return (line_thickness, color) for leak level."""
    if level == 0:
        return 6, (50, 255, 80)     # fat bright green
    elif level == 1:
        return 3, (255, 200, 50)    # medium yellow
    else:
        return 1, (255, 50, 50)     # thin red


# ===================================================================
# STAGE 6: Render frames
# ===================================================================
def render_all_frames(
    frames_bgr: list[np.ndarray],
    landmarks: list[list[tuple] | None],
    velocities: dict,
    transfers: dict,
    fps: float,
) -> list[np.ndarray]:
    """Render all output frames (1080x1920 canvases)."""
    n = len(frames_bgr)
    bfc = transfers["bfc_frame"]
    ffc = transfers["ffc_frame"]
    release = transfers["release_frame"]
    norm = velocities["normalized"]
    total = velocities["total_body"]

    rendered = []
    for i in range(n):
        canvas = np.full((OUT_H, OUT_W, 3), BG_DARK, dtype=np.uint8)

        # --- Video frame in top portion ---
        frame = frames_bgr[i]
        fh, fw = frame.shape[:2]
        # Fit into top 56% of canvas
        video_h = int(OUT_H * 0.56)
        scale = min(OUT_W / fw, video_h / fh)
        new_w = int(fw * scale)
        new_h = int(fh * scale)
        resized = cv2.resize(frame, (new_w, new_h))

        # Dim background slightly
        resized = (resized * 0.75).astype(np.uint8)

        vx = (OUT_W - new_w) // 2
        vy = 80  # leave room for title
        canvas[vy:vy+new_h, vx:vx+new_w] = resized

        lm = landmarks[i]

        # Determine phase
        is_runup = i < bfc
        is_delivery = bfc <= i <= release + 3
        is_post = i > release + 3

        # --- Skeleton overlay ---
        if lm is not None:
            # Compute per-joint energy for this frame
            joint_energy = {}
            if is_delivery or is_post:
                for seg, joints in CHAIN_JOINTS.items():
                    e = norm[seg][i] if seg in norm and i < len(norm[seg]) else 0.0
                    for jid in joints:
                        joint_energy[jid] = max(joint_energy.get(jid, 0), e)
                # Fill remaining joints with low energy
                for jid in range(33):
                    if jid not in joint_energy:
                        joint_energy[jid] = 0.1
            else:
                # Run-up: uniform energy from total body
                uniform_e = total[i] if i < len(total) else 0.0
                for jid in range(33):
                    joint_energy[jid] = uniform_e

            # Draw skeleton connections
            for j1, j2 in SKELETON_CONNECTIONS:
                if j1 >= len(lm) or j2 >= len(lm):
                    continue
                if lm[j1][2] < 0.3 or lm[j2][2] < 0.3:
                    continue
                x1 = int(vx + lm[j1][0] * new_w)
                y1 = int(vy + lm[j1][1] * new_h)
                x2 = int(vx + lm[j2][0] * new_w)
                y2 = int(vy + lm[j2][1] * new_h)
                e = max(joint_energy.get(j1, 0), joint_energy.get(j2, 0))
                color = energy_color(e)
                thickness = max(2, int(2 + e * 4))
                cv2.line(canvas, (x1, y1), (x2, y2), color, thickness, cv2.LINE_AA)

            # Draw joint dots
            for jid in PRIMARY_JOINTS:
                if jid >= len(lm) or lm[jid][2] < 0.3:
                    continue
                x = int(vx + lm[jid][0] * new_w)
                y = int(vy + lm[jid][1] * new_h)
                e = joint_energy.get(jid, 0)
                color = energy_color(e)
                radius = max(4, int(4 + e * 8))
                cv2.circle(canvas, (x, y), radius, color, -1, cv2.LINE_AA)
                cv2.circle(canvas, (x, y), radius, (255, 255, 255), 1, cv2.LINE_AA)

        # --- Transfer leak indicators (during delivery) ---
        if is_delivery and lm is not None:
            _draw_leak_indicators(canvas, lm, transfers, i, vx, vy, new_w, new_h)

        # --- Phase label ---
        pil_canvas = Image.fromarray(cv2.cvtColor(canvas, cv2.COLOR_BGR2RGB))
        draw = ImageDraw.Draw(pil_canvas)

        # Title
        draw.text((OUT_W//2, 30), "ENERGY TRANSFER", font=FONT_TITLE,
                   fill=(240, 244, 248), anchor="mt")

        # Phase text
        if is_runup:
            phase_text = "LOADING"
            phase_color = (100, 180, 255)
        elif i < ffc:
            phase_text = "PLANT"
            phase_color = (255, 200, 50)
        elif i < ffc + 3:
            phase_text = "BRACE"
            phase_color = (255, 140, 0)
        elif i <= release:
            phase_text = "WHIP"
            phase_color = (255, 40, 40)
        else:
            phase_text = "FOLLOW THROUGH"
            phase_color = (120, 120, 120)

        # Phase pill
        tw = draw.textlength(phase_text, font=FONT_PHASE)
        px = OUT_W // 2 - int(tw) // 2 - 16
        py = 60
        draw.rounded_rectangle(
            (px, py, px + int(tw) + 32, py + 38),
            radius=12, fill=(20, 24, 30),
        )
        draw.text((OUT_W//2, py + 4), phase_text, font=FONT_PHASE,
                   fill=phase_color, anchor="mt")

        # --- Energy bar (bottom section) ---
        bar_y = int(OUT_H * 0.60)
        bar_h = 8
        bar_margin = 60
        bar_w = OUT_W - 2 * bar_margin

        # Draw energy bar background
        draw.rounded_rectangle(
            (bar_margin, bar_y, bar_margin + bar_w, bar_y + bar_h),
            radius=4, fill=(30, 33, 40),
        )

        # Draw filled portion based on total body energy
        fill_w = int(bar_w * min(1.0, total[i] if i < len(total) else 0))
        if fill_w > 0:
            bar_color = energy_color(total[i] if i < len(total) else 0)
            draw.rounded_rectangle(
                (bar_margin, bar_y, bar_margin + fill_w, bar_y + bar_h),
                radius=4, fill=bar_color,
            )

        # --- Segment velocity bars (during delivery) ---
        if is_delivery or is_post:
            seg_bar_y = bar_y + 24
            seg_names = ["hips", "trunk", "upper_arm", "forearm", "wrist"]
            seg_labels = ["Hips", "Trunk", "Arm", "Forearm", "Wrist"]
            for si, (seg, label) in enumerate(zip(seg_names, seg_labels)):
                by = seg_bar_y + si * 28
                e = norm[seg][i] if seg in norm and i < len(norm[seg]) else 0.0
                color = energy_color(e)

                # Label
                draw.text((bar_margin, by), label, font=FONT_SMALL, fill=(140, 140, 140))

                # Bar
                bx = bar_margin + 80
                bw = bar_w - 80
                draw.rounded_rectangle((bx, by + 2, bx + bw, by + 14), radius=4, fill=(30, 33, 40))
                fw = int(bw * min(1.0, e))
                if fw > 0:
                    draw.rounded_rectangle((bx, by + 2, bx + fw, by + 14), radius=4, fill=color)

        # --- Color ramp legend ---
        legend_y = OUT_H - 80
        draw.text((bar_margin, legend_y), "COLD", font=FONT_SMALL, fill=(80, 80, 120))
        draw.text((OUT_W - bar_margin, legend_y), "HOT", font=FONT_SMALL, fill=(255, 80, 80), anchor="rt")

        # Draw gradient bar
        for px_i in range(bar_w):
            t = px_i / max(1, bar_w - 1)
            c = energy_color(t)
            draw.line(
                [(bar_margin + px_i, legend_y + 20), (bar_margin + px_i, legend_y + 30)],
                fill=c,
            )

        # Brand
        draw.text((OUT_W - 20, OUT_H - 20), "wellBowled.ai", font=FONT_BRAND_SMALL,
                   fill=BRAND_TEAL, anchor="rb")

        canvas = cv2.cvtColor(np.array(pil_canvas), cv2.COLOR_RGB2BGR)
        rendered.append(canvas)

    log.info("[render] %d frames rendered", len(rendered))
    return rendered


def _draw_leak_indicators(canvas, lm, transfers, frame_i, vx, vy, new_w, new_h):
    """Draw transfer leak lines between body segments on the video."""
    leaks = transfers["leaks"]

    # Segment anchor joints (approximate body positions)
    anchors = {
        "BFC → FFC":    ([27, 28], [27, 28]),  # ankles
        "FFC → Hips":   ([27, 28], [23, 24]),   # ankles → hips
        "Hips → Trunk":  ([23, 24], [11, 12]),   # hips → shoulders
        "Trunk → Arm":   ([11, 12], [16, 20]),   # shoulders → wrist
    }

    for name, level, gap in leaks:
        if name not in anchors:
            continue
        src_joints, dst_joints = anchors[name]
        thick, color = leak_visual(level)

        # Get midpoints
        sx, sy, sc = 0, 0, 0
        for jid in src_joints:
            if jid < len(lm) and lm[jid][2] > 0.3:
                sx += lm[jid][0]; sy += lm[jid][1]; sc += 1
        dx, dy, dc = 0, 0, 0
        for jid in dst_joints:
            if jid < len(lm) and lm[jid][2] > 0.3:
                dx += lm[jid][0]; dy += lm[jid][1]; dc += 1

        if sc > 0 and dc > 0:
            x1 = int(vx + (sx/sc) * new_w)
            y1 = int(vy + (sy/sc) * new_h)
            x2 = int(vx + (dx/dc) * new_w)
            y2 = int(vy + (dy/dc) * new_h)

            # Draw glow behind
            if level == 0:
                cv2.line(canvas, (x1, y1), (x2, y2), color, thick + 4, cv2.LINE_AA)
            cv2.line(canvas, (x1, y1), (x2, y2), color, thick, cv2.LINE_AA)


# ===================================================================
# STAGE 7: Compose video
# ===================================================================
def compose_video(
    rendered: list[np.ndarray],
    frames_bgr: list[np.ndarray],
    transfers: dict,
    velocities: dict,
    leaks_data: list,
    fps: float,
) -> str:
    """Compose final video with pacing: 1x run-up → slo-mo delivery → verdict → end card."""
    bfc = transfers["bfc_frame"]
    ffc = transfers["ffc_frame"]
    release = transfers["release_frame"]

    annotated_dir = OUTPUT_DIR / "annotated"
    if annotated_dir.exists():
        shutil.rmtree(annotated_dir)
    annotated_dir.mkdir(parents=True)

    frame_idx = 0

    def write_frame(canvas):
        nonlocal frame_idx
        path = annotated_dir / f"{frame_idx:06d}.jpg"
        cv2.imwrite(str(path), canvas, [cv2.IMWRITE_JPEG_QUALITY, 95])
        frame_idx += 1

    # Phase 1: Run-up at 1x (every frame)
    runup_start = max(0, bfc - int(fps * 1.5))  # 1.5s before BFC
    for i in range(runup_start, bfc):
        if i < len(rendered):
            write_frame(rendered[i])

    # Phase 2-5: Delivery at super slo-mo (each frame held for ~0.4s = 12 output frames)
    hold_frames = max(8, int(fps * 0.4))
    delivery_end = min(len(rendered), release + 5)
    for i in range(bfc, delivery_end):
        if i < len(rendered):
            for _ in range(hold_frames):
                write_frame(rendered[i])

    # Phase 6: Verdict card (2.5s)
    verdict_canvas = _render_verdict(
        frames_bgr[min(release, len(frames_bgr)-1)],
        transfers, velocities,
    )
    for _ in range(int(fps * 2.5)):
        write_frame(verdict_canvas)

    # Phase 7: End card (1.5s)
    end_canvas = _render_end_card()
    for _ in range(int(fps * 1.5)):
        write_frame(end_canvas)

    # FFmpeg encode
    out_path = str(OUTPUT_DIR / "speed_gradient.mp4")
    cmd = [
        "ffmpeg", "-y", "-framerate", str(FPS_OUT),
        "-i", str(annotated_dir / "%06d.jpg"),
        "-c:v", "libx264", "-preset", "medium", "-crf", "18",
        "-pix_fmt", "yuv420p", "-movflags", "+faststart",
        out_path,
    ]
    log.info("[ffmpeg] Encoding %d frames ...", frame_idx)
    subprocess.run(cmd, capture_output=True)

    # Verify
    probe = subprocess.run(
        ["ffprobe", "-v", "quiet", "-print_format", "json", "-show_streams", out_path],
        capture_output=True, text=True,
    )
    if probe.returncode == 0:
        info = json.loads(probe.stdout)
        stream = info.get("streams", [{}])[0]
        log.info("[ffmpeg] Output: %sx%s, %s, %sfps, duration=%s",
                 stream.get("width"), stream.get("height"),
                 stream.get("codec_name"), stream.get("r_frame_rate"),
                 stream.get("duration"))

    return out_path


def _render_verdict(peak_frame_bgr: np.ndarray, transfers: dict, velocities: dict) -> np.ndarray:
    """Render verdict card: blurred bg + leak summary."""
    # Blurred background
    fh, fw = peak_frame_bgr.shape[:2]
    scale = max(OUT_W / fw, OUT_H / fh)
    bg = cv2.resize(peak_frame_bgr, (int(fw*scale), int(fh*scale)))
    bg = bg[:OUT_H, :OUT_W]
    if bg.shape[0] < OUT_H or bg.shape[1] < OUT_W:
        canvas_bg = np.full((OUT_H, OUT_W, 3), BG_DARK, dtype=np.uint8)
        canvas_bg[:bg.shape[0], :bg.shape[1]] = bg
        bg = canvas_bg
    bg_pil = Image.fromarray(cv2.cvtColor(bg, cv2.COLOR_BGR2RGB))
    bg_pil = bg_pil.filter(ImageFilter.GaussianBlur(radius=12))
    # Dark overlay
    overlay = Image.new("RGBA", (OUT_W, OUT_H), (13, 17, 23, 190))
    bg_pil = bg_pil.convert("RGBA")
    bg_pil = Image.alpha_composite(bg_pil, overlay).convert("RGB")

    draw = ImageDraw.Draw(bg_pil)

    # Title
    y = 200
    draw.text((OUT_W//2, y), "KINETIC CHAIN ANALYSIS", font=FONT_VERDICT_TITLE,
               fill=(240, 244, 248), anchor="mt")
    y += 60

    # Separator
    draw.line([(OUT_W//4, y), (3*OUT_W//4, y)], fill=(60, 65, 75), width=2)
    y += 30

    # Leak summary for each transfer
    leak_labels = {0: "MINIMAL LEAK", 1: "MODERATE LEAK", 2: "MAJOR LEAK"}
    leak_colors = {0: (50, 255, 80), 1: (255, 200, 50), 2: (255, 50, 50)}

    for name, level, gap in transfers["leaks"]:
        # Transfer name
        draw.text((OUT_W//2, y), name, font=FONT_VERDICT_BODY,
                   fill=(180, 180, 180), anchor="mt")
        y += 36

        # Leak bar
        bar_w = 400
        bx = OUT_W//2 - bar_w//2
        thick, color = leak_visual(level)
        draw.rounded_rectangle((bx, y, bx + bar_w, y + 16), radius=6, fill=(30, 33, 40))
        # Fill based on efficiency (inverse of leak)
        efficiency = max(0.2, 1.0 - level * 0.35)
        fw = int(bar_w * efficiency)
        draw.rounded_rectangle((bx, y, bx + fw, y + 16), radius=6, fill=color)
        y += 24

        # Level label
        draw.text((OUT_W//2, y), leak_labels[level], font=FONT_VERDICT_LEAK,
                   fill=leak_colors[level], anchor="mt")
        y += 50

    # Overall verdict
    y += 20
    draw.line([(OUT_W//4, y), (3*OUT_W//4, y)], fill=(60, 65, 75), width=2)
    y += 30

    total_leak = sum(level for _, level, _ in transfers["leaks"])
    if total_leak <= 1:
        verdict = "ELITE CHAIN"
        vcolor = (50, 255, 80)
        desc = "Tight energy transfer — sequential and explosive"
    elif total_leak <= 4:
        verdict = "GOOD CHAIN"
        vcolor = (255, 200, 50)
        desc = "Minor leaks but effective energy transfer"
    else:
        verdict = "BROKEN CHAIN"
        vcolor = (255, 50, 50)
        desc = "Significant energy leaks — timing needs work"

    draw.text((OUT_W//2, y), verdict, font=FONT_VERDICT_TITLE,
               fill=vcolor, anchor="mt")
    y += 60
    draw.text((OUT_W//2, y), desc, font=FONT_VERDICT_BODY,
               fill=(160, 160, 160), anchor="mt")
    y += 50

    # Brand
    draw.text((OUT_W//2, OUT_H - 100), "wellBowled.ai", font=FONT_BRAND_SMALL,
               fill=BRAND_TEAL, anchor="mt")

    return cv2.cvtColor(np.array(bg_pil), cv2.COLOR_RGB2BGR)


def _render_end_card() -> np.ndarray:
    """Render end card with brand."""
    canvas = Image.new("RGB", (OUT_W, OUT_H), BG_DARK)
    draw = ImageDraw.Draw(canvas)
    draw.text((OUT_W//2, OUT_H//2 - 40), "wellBowled.ai",
               font=FONT_BRAND_BIG, fill=BRAND_TEAL, anchor="mm")
    draw.text((OUT_W//2, OUT_H//2 + 50), "Cricket biomechanics, visualized",
               font=FONT_TAGLINE, fill=(220, 220, 220), anchor="mm")
    return cv2.cvtColor(np.array(canvas), cv2.COLOR_RGB2BGR)


# ===================================================================
# STAGE 8: Review
# ===================================================================
def extract_review(video_path: str, fps: float):
    """Extract QA review frames at key percentages."""
    review_dir = OUTPUT_DIR / "review"
    review_dir.mkdir(parents=True, exist_ok=True)

    cap = cv2.VideoCapture(video_path)
    total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    percentages = [0, 15, 30, 50, 70, 85, 95]

    for pct in percentages:
        idx = min(int(total * pct / 100), total - 1)
        cap.set(cv2.CAP_PROP_POS_FRAMES, idx)
        ok, frame = cap.read()
        if ok:
            path = review_dir / f"review_{pct:02d}.png"
            cv2.imwrite(str(path), frame)

    cap.release()
    log.info("[review] Extracted %d review frames", len(percentages))


# ===================================================================
# MAIN
# ===================================================================
def main():
    parser = argparse.ArgumentParser(description="Speed Gradient v1.0.0")
    parser.add_argument("clip", nargs="?", default=str(DEFAULT_CLIP), help="Input clip path")
    parser.add_argument("--skip-gemini", action="store_true", help="Skip Gemini call")
    parser.add_argument("--output", default=str(OUTPUT_DIR), help="Output directory")
    args = parser.parse_args()

    global OUTPUT_DIR
    OUTPUT_DIR = Path(args.output)
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    logging.basicConfig(level=logging.INFO, format="%(message)s")

    clip_path = args.clip
    log.info("=" * 60)
    log.info("  Speed Gradient v1.0.0")
    log.info("  Input: %s", clip_path)
    log.info("=" * 60)

    # Stage 1: Extract frames
    log.info("\n── Stage 1: Extract frames ──")
    frames_bgr, fps = extract_frames(clip_path)

    # Stage 2: Gemini Pro 3
    gemini_result = None
    if not args.skip_gemini:
        log.info("\n── Stage 2: Gemini Pro 3 ──")
        gemini_result = call_gemini(frames_bgr, fps)

    # Stage 3: Crop + upscale
    log.info("\n── Stage 3: Crop + upscale ──")
    roi = gemini_result.get("bowler_roi") if gemini_result else None
    cropped = crop_and_upscale(frames_bgr, roi, target_h=720)

    # Stage 4: Pose extraction
    log.info("\n── Stage 4: Pose extraction ──")
    landmarks = extract_poses(cropped)

    # Stage 5: Velocity computation
    log.info("\n── Stage 5: Velocity computation ──")
    velocities = compute_velocities(landmarks, fps)

    # Stage 6: Transfer detection + leaks
    log.info("\n── Stage 6: Transfer detection ──")
    transfers = detect_transfers(velocities, gemini_result, fps, len(cropped))

    # Stage 7: Render frames
    log.info("\n── Stage 7: Render frames ──")
    rendered = render_all_frames(cropped, landmarks, velocities, transfers, fps)

    # Stage 8: Compose video
    log.info("\n── Stage 8: Compose video ──")
    out_path = compose_video(rendered, cropped, transfers, velocities, transfers["leaks"], fps)

    # Stage 9: Review
    log.info("\n── Stage 9: Review ──")
    extract_review(out_path, FPS_OUT)

    # Export data
    data_path = OUTPUT_DIR / "velocity_data.json"
    export = {
        "clip": clip_path,
        "fps": fps,
        "n_frames": len(frames_bgr),
        "bfc_frame": transfers["bfc_frame"],
        "ffc_frame": transfers["ffc_frame"],
        "release_frame": transfers["release_frame"],
        "peaks": transfers["peaks"],
        "leaks": [(n, l, g) for n, l, g in transfers["leaks"]],
    }
    with data_path.open("w") as f:
        json.dump(export, f, indent=2)

    log.info("\n" + "=" * 60)
    log.info("  DONE: %s", out_path)
    log.info("  Review: %s", OUTPUT_DIR / "review")
    log.info("=" * 60)


if __name__ == "__main__":
    main()
