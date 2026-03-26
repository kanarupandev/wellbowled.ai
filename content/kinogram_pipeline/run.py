#!/usr/bin/env python3
"""Kinogram Pipeline — stroboscopic bowling action composite.

Takes a 3-10s bowling clip → produces a kinogram image + animated video
showing 6-8 key body positions overlaid on a single frame.
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

# ── Paths ──────────────────────────────────────────────────────────────
ROOT = Path(__file__).resolve().parents[2]
INPUT_CLIP = ROOT / "resources" / "samples" / "3_sec_1_delivery_nets.mp4"
OUTPUT_DIR = Path(__file__).resolve().parent / "output"
FRAMES_DIR = OUTPUT_DIR / "frames"
MODEL_PATH = Path(__file__).resolve().parent / "pose_landmarker_heavy.task"
MODEL_URL = "https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_heavy/float16/latest/pose_landmarker_heavy.task"

# ── Constants ──────────────────────────────────────────────────────────
OUT_W, OUT_H = 1080, 1920
FPS = 30
NUM_KEY_FRAMES = 7
PHASE_LABELS = ["RUN UP", "GATHER", "BACK FOOT", "FRONT FOOT", "RELEASE", "FOLLOW", "FINISH"]
DARK_BG = (13, 17, 23)
PEACOCK = (0, 109, 119)
WHITE = (255, 255, 255)
CYAN = (0, 206, 209)
ACCENT_COLORS = [
    (255, 105, 180),  # pink
    (255, 165, 0),    # orange
    (255, 215, 0),    # gold
    (0, 255, 127),    # spring green
    (0, 206, 209),    # cyan
    (100, 149, 237),  # cornflower
    (186, 85, 211),   # orchid
]
POSE_CONNECTIONS = [
    (11, 12), (11, 13), (13, 15), (12, 14), (14, 16),
    (11, 23), (12, 24), (23, 24), (23, 25), (25, 27),
    (24, 26), (26, 28),
]


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


# ── Stage 1: Extract all frames ───────────────────────────────────────
def extract_frames(clip: Path) -> tuple[list[Path], dict]:
    FRAMES_DIR.mkdir(parents=True, exist_ok=True)

    probe = subprocess.run(
        ["ffprobe", "-v", "quiet", "-print_format", "json", "-show_streams", str(clip)],
        capture_output=True, text=True, check=True,
    )
    vs = next(s for s in json.loads(probe.stdout)["streams"] if s["codec_type"] == "video")
    meta = {"fps": eval(vs["r_frame_rate"]), "duration": float(vs["duration"]),
            "nb_frames": int(vs["nb_frames"])}

    # Extract at original fps for smooth animation
    subprocess.run(
        ["ffmpeg", "-y", "-i", str(clip), "-q:v", "2", str(FRAMES_DIR / "f_%04d.jpg")],
        capture_output=True, check=True,
    )
    frames = sorted(FRAMES_DIR.glob("f_*.jpg"))
    meta["extracted"] = len(frames)
    print(f"  [1] Extracted {len(frames)} frames")
    return frames, meta


# ── Stage 2: Select key frames evenly across delivery ─────────────────
def select_key_frames(frames: list[Path], n: int = NUM_KEY_FRAMES) -> list[int]:
    # Focus on the delivery stride — roughly frames 20-80% of the clip
    # For a 3.7s nets clip at 30fps (111 frames), the delivery action is ~frame 20-90
    total = len(frames)
    start = int(total * 0.18)  # skip early run-up (bowler too far)
    end = int(total * 0.82)    # skip post-delivery standing
    span = end - start
    indices = [start + int(i * span / (n - 1)) for i in range(n)]
    print(f"  [2] Key frames: {indices} (delivery zone {start}-{end} of {total})")
    return indices


# ── Stage 3: Pose + segmentation ──────────────────────────────────────
def extract_poses(frames: list[Path], key_indices: list[int]) -> list[dict]:
    if not MODEL_PATH.exists():
        print("  Downloading pose model...")
        urllib.request.urlretrieve(MODEL_URL, MODEL_PATH)

    options = mp.tasks.vision.PoseLandmarkerOptions(
        base_options=mp.tasks.BaseOptions(model_asset_path=str(MODEL_PATH)),
        output_segmentation_masks=True,
        num_poses=2,  # detect multiple so we can pick the bowler
        min_pose_detection_confidence=0.4,
    )

    results = []
    with mp.tasks.vision.PoseLandmarker.create_from_options(options) as landmarker:
        for idx in key_indices:
            img = cv2.imread(str(frames[idx]))
            rgb = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
            mp_img = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)
            result = landmarker.detect(mp_img)

            entry = {"index": idx, "frame_path": str(frames[idx]),
                     "landmarks": None, "mask": None}

            best_idx = 0
            if result.pose_landmarks and len(result.pose_landmarks) > 1:
                # Pick largest pose (bowler, not bystander)
                best_size = 0
                for pi, pose_lms in enumerate(result.pose_landmarks):
                    xs = [lm.x for lm in pose_lms if lm.visibility > 0.3]
                    ys = [lm.y for lm in pose_lms if lm.visibility > 0.3]
                    if xs and ys:
                        size = (max(xs) - min(xs)) * (max(ys) - min(ys))
                        if size > best_size:
                            best_size = size
                            best_idx = pi

            if result.pose_landmarks:
                entry["landmarks"] = [
                    {"x": lm.x, "y": lm.y, "z": lm.z, "vis": lm.visibility}
                    for lm in result.pose_landmarks[best_idx]
                ]
            if result.segmentation_masks:
                mi = min(best_idx, len(result.segmentation_masks) - 1)
                entry["mask"] = result.segmentation_masks[mi].numpy_view().copy()

            results.append(entry)

    detected = sum(1 for r in results if r["landmarks"])
    masked = sum(1 for r in results if r["mask"] is not None)
    print(f"  [3] Pose: {detected}/{len(key_indices)}, Masks: {masked}/{len(key_indices)}")
    return results


# ── Stage 4: Build kinogram composite ─────────────────────────────────
def build_kinogram(pose_results: list[dict]) -> np.ndarray:
    """Overlay segmented bowler figures from each key frame onto one canvas."""
    # Use the first frame as background base (darken it)
    bg_img = cv2.imread(pose_results[0]["frame_path"])
    h, w = bg_img.shape[:2]

    # Darken background significantly
    bg_dark = (bg_img.astype(np.float32) * 0.25).astype(np.uint8)

    # Scale to fit 9:16 canvas
    scale = min(OUT_W / w, OUT_H * 0.75 / h)  # leave room for labels at bottom
    new_w, new_h = int(w * scale), int(h * scale)

    canvas = np.zeros((OUT_H, OUT_W, 3), dtype=np.uint8)
    canvas[:] = DARK_BG[::-1]  # BGR

    bg_resized = cv2.resize(bg_dark, (new_w, new_h), interpolation=cv2.INTER_LANCZOS4)
    x_off = (OUT_W - new_w) // 2
    y_off = 80  # top padding for title
    canvas[y_off:y_off + new_h, x_off:x_off + new_w] = bg_resized

    # Overlay each key frame's bowler
    for i, pr in enumerate(pose_results):
        if pr["mask"] is None or pr["landmarks"] is None:
            continue

        frame = cv2.imread(pr["frame_path"])
        mask = pr["mask"]

        # Threshold mask
        binary_mask = (mask > 0.5).astype(np.float32)

        # Slight dilation to fill gaps
        kernel = np.ones((5, 5), np.uint8)
        binary_mask = cv2.dilate(binary_mask, kernel, iterations=1)

        # Smooth edges
        binary_mask = cv2.GaussianBlur(binary_mask, (7, 7), 0)

        # Resize frame and mask to canvas scale
        frame_resized = cv2.resize(frame, (new_w, new_h), interpolation=cv2.INTER_LANCZOS4)
        mask_resized = cv2.resize(binary_mask, (new_w, new_h), interpolation=cv2.INTER_LINEAR)

        # Tint the figure slightly with its accent color
        color = ACCENT_COLORS[i % len(ACCENT_COLORS)]
        tint = np.zeros_like(frame_resized)
        tint[:] = color[::-1]  # BGR
        frame_tinted = cv2.addWeighted(frame_resized, 0.8, tint, 0.2, 0)

        # Alpha for this layer — earlier figures are more transparent
        alpha_base = 0.4 + 0.6 * (i / max(len(pose_results) - 1, 1))
        alpha_3ch = np.stack([mask_resized * alpha_base] * 3, axis=-1)

        # Composite onto canvas
        roi = canvas[y_off:y_off + new_h, x_off:x_off + new_w].astype(np.float32)
        fg = frame_tinted.astype(np.float32)
        blended = roi * (1 - alpha_3ch) + fg * alpha_3ch
        canvas[y_off:y_off + new_h, x_off:x_off + new_w] = blended.astype(np.uint8)

        # Draw skeleton in accent color
        lms = pr["landmarks"]
        for j1, j2 in POSE_CONNECTIONS:
            if lms[j1]["vis"] < 0.4 or lms[j2]["vis"] < 0.4:
                continue
            pt1 = (x_off + int(lms[j1]["x"] * new_w), y_off + int(lms[j1]["y"] * new_h))
            pt2 = (x_off + int(lms[j2]["x"] * new_w), y_off + int(lms[j2]["y"] * new_h))
            cv2.line(canvas, pt1, pt2, color[::-1], 2, cv2.LINE_AA)

    # Add title and labels with Pillow
    pil = Image.fromarray(cv2.cvtColor(canvas, cv2.COLOR_BGR2RGB))
    draw = ImageDraw.Draw(pil)

    # Title
    title_font = load_font(44, bold=True)
    title = "KINOGRAM"
    bbox = draw.textbbox((0, 0), title, font=title_font)
    tw = bbox[2] - bbox[0]
    draw.text(((OUT_W - tw) // 2, 20), title, fill=WHITE, font=title_font)

    # Phase labels at bottom
    label_font = load_font(18, bold=False)
    label_y = y_off + new_h + 20
    label_w = OUT_W // len(pose_results)
    for i, pr in enumerate(pose_results):
        if i < len(PHASE_LABELS):
            label = PHASE_LABELS[i]
        else:
            label = f"PHASE {i+1}"
        color = ACCENT_COLORS[i % len(ACCENT_COLORS)]

        # Color dot + label
        cx = label_w * i + label_w // 2
        draw.ellipse([cx - 6, label_y, cx + 6, label_y + 12], fill=color)
        bbox = draw.textbbox((0, 0), label, font=label_font)
        ltw = bbox[2] - bbox[0]
        draw.text((cx - ltw // 2, label_y + 18), label, fill=WHITE, font=label_font)

    # Branding
    brand_font = load_font(24, bold=True)
    draw.text((OUT_W - 200, OUT_H - 50), "wellBowled.ai", fill=PEACOCK, font=brand_font)

    canvas = cv2.cvtColor(np.array(pil), cv2.COLOR_RGB2BGR)

    # Save hero image
    hero_path = OUTPUT_DIR / "kinogram_hero.jpg"
    cv2.imwrite(str(hero_path), canvas, [cv2.IMWRITE_JPEG_QUALITY, 95])
    print(f"  [4] Kinogram hero: {hero_path.name}")

    return canvas


# ── Stage 5: Animate — reveal each figure one at a time ───────────────
def animate_kinogram(pose_results: list[dict], meta: dict) -> list[np.ndarray]:
    """Build video frames: progressive reveal of each figure."""
    bg_img = cv2.imread(pose_results[0]["frame_path"])
    h, w = bg_img.shape[:2]
    bg_dark = (bg_img.astype(np.float32) * 0.25).astype(np.uint8)

    scale = min(OUT_W / w, OUT_H * 0.75 / h)
    new_w, new_h = int(w * scale), int(h * scale)
    x_off = (OUT_W - new_w) // 2
    y_off = 80

    # Pre-compute per-figure data
    figures = []
    for i, pr in enumerate(pose_results):
        if pr["mask"] is None:
            figures.append(None)
            continue

        frame = cv2.imread(pr["frame_path"])
        mask = pr["mask"]
        binary_mask = (mask > 0.5).astype(np.float32)
        kernel = np.ones((5, 5), np.uint8)
        binary_mask = cv2.dilate(binary_mask, kernel, iterations=1)
        binary_mask = cv2.GaussianBlur(binary_mask, (7, 7), 0)

        frame_resized = cv2.resize(frame, (new_w, new_h), interpolation=cv2.INTER_LANCZOS4)
        mask_resized = cv2.resize(binary_mask, (new_w, new_h), interpolation=cv2.INTER_LINEAR)

        color = ACCENT_COLORS[i % len(ACCENT_COLORS)]
        tint = np.zeros_like(frame_resized)
        tint[:] = color[::-1]
        frame_tinted = cv2.addWeighted(frame_resized, 0.8, tint, 0.2, 0)

        figures.append({
            "frame": frame_tinted, "mask": mask_resized,
            "landmarks": pr["landmarks"], "color": color,
        })

    # Base canvas (dark bg)
    base = np.zeros((OUT_H, OUT_W, 3), dtype=np.uint8)
    base[:] = DARK_BG[::-1]
    bg_resized = cv2.resize(bg_dark, (new_w, new_h), interpolation=cv2.INTER_LANCZOS4)
    base[y_off:y_off + new_h, x_off:x_off + new_w] = bg_resized

    # Add title to base
    base_pil = Image.fromarray(cv2.cvtColor(base, cv2.COLOR_BGR2RGB))
    draw = ImageDraw.Draw(base_pil)
    title_font = load_font(44, bold=True)
    title = "KINOGRAM"
    bbox = draw.textbbox((0, 0), title, font=title_font)
    draw.text(((OUT_W - bbox[2] + bbox[0]) // 2, 20), title, fill=WHITE, font=title_font)
    brand_font = load_font(24, bold=True)
    draw.text((OUT_W - 200, OUT_H - 50), "wellBowled.ai", fill=PEACOCK, font=brand_font)
    base = cv2.cvtColor(np.array(base_pil), cv2.COLOR_RGB2BGR)

    all_frames = []

    # Intro: show raw clip frames (1.5s at original speed, scaled to canvas)
    raw_frames_paths = sorted(FRAMES_DIR.glob("f_*.jpg"))
    intro_count = min(int(1.5 * meta["fps"]), len(raw_frames_paths))
    # Resample to 30fps
    intro_indices = [int(i * meta["fps"] / FPS) for i in range(int(1.5 * FPS))]
    intro_indices = [min(idx, intro_count - 1) for idx in intro_indices]

    for idx in intro_indices:
        raw = cv2.imread(str(raw_frames_paths[idx]))
        canvas = np.zeros((OUT_H, OUT_W, 3), dtype=np.uint8)
        canvas[:] = DARK_BG[::-1]
        raw_resized = cv2.resize(raw, (new_w, new_h), interpolation=cv2.INTER_LANCZOS4)
        canvas[y_off:y_off + new_h, x_off:x_off + new_w] = raw_resized
        all_frames.append(canvas)

    print(f"  [5a] Intro: {len(intro_indices)} frames")

    # Progressive reveal: each figure fades in over 0.5s, holds 0.3s
    FADE_FRAMES = int(0.5 * FPS)  # 15 frames
    HOLD_FRAMES = int(0.3 * FPS)  # 9 frames

    current = base.copy()
    label_font = load_font(18, bold=False)
    label_w = OUT_W // len(figures)

    for i, fig in enumerate(figures):
        if fig is None:
            # Still hold
            for _ in range(HOLD_FRAMES):
                all_frames.append(current.copy())
            continue

        alpha_target = 0.4 + 0.6 * (i / max(len(figures) - 1, 1))

        # Fade in
        for f in range(FADE_FRAMES):
            t = (f + 1) / FADE_FRAMES  # 0→1
            alpha = alpha_target * t
            alpha_3ch = np.stack([fig["mask"] * alpha] * 3, axis=-1)

            frame_out = current.copy()
            roi = frame_out[y_off:y_off + new_h, x_off:x_off + new_w].astype(np.float32)
            fg = fig["frame"].astype(np.float32)
            blended = roi * (1 - alpha_3ch) + fg * alpha_3ch
            frame_out[y_off:y_off + new_h, x_off:x_off + new_w] = blended.astype(np.uint8)

            # Draw skeleton at current alpha
            if t > 0.5:
                lms = fig["landmarks"]
                for j1, j2 in POSE_CONNECTIONS:
                    if lms[j1]["vis"] < 0.4 or lms[j2]["vis"] < 0.4:
                        continue
                    pt1 = (x_off + int(lms[j1]["x"] * new_w), y_off + int(lms[j1]["y"] * new_h))
                    pt2 = (x_off + int(lms[j2]["x"] * new_w), y_off + int(lms[j2]["y"] * new_h))
                    cv2.line(frame_out, pt1, pt2, fig["color"][::-1], 2, cv2.LINE_AA)

            all_frames.append(frame_out)

        # Commit this figure permanently
        alpha_3ch = np.stack([fig["mask"] * alpha_target] * 3, axis=-1)
        roi = current[y_off:y_off + new_h, x_off:x_off + new_w].astype(np.float32)
        fg = fig["frame"].astype(np.float32)
        blended = roi * (1 - alpha_3ch) + fg * alpha_3ch
        current[y_off:y_off + new_h, x_off:x_off + new_w] = blended.astype(np.uint8)

        # Draw skeleton permanently
        lms = fig["landmarks"]
        for j1, j2 in POSE_CONNECTIONS:
            if lms[j1]["vis"] < 0.4 or lms[j2]["vis"] < 0.4:
                continue
            pt1 = (x_off + int(lms[j1]["x"] * new_w), y_off + int(lms[j1]["y"] * new_h))
            pt2 = (x_off + int(lms[j2]["x"] * new_w), y_off + int(lms[j2]["y"] * new_h))
            cv2.line(current, pt1, pt2, fig["color"][::-1], 2, cv2.LINE_AA)

        # Add phase label via Pillow
        pil_cur = Image.fromarray(cv2.cvtColor(current, cv2.COLOR_BGR2RGB))
        draw_cur = ImageDraw.Draw(pil_cur)
        label_y = y_off + new_h + 20
        cx = label_w * i + label_w // 2
        color_rgb = fig["color"]
        label = PHASE_LABELS[i] if i < len(PHASE_LABELS) else f"PHASE {i+1}"
        draw_cur.ellipse([cx - 6, label_y, cx + 6, label_y + 12], fill=color_rgb)
        bbox = draw_cur.textbbox((0, 0), label, font=label_font)
        ltw = bbox[2] - bbox[0]
        draw_cur.text((cx - ltw // 2, label_y + 18), label, fill=WHITE, font=label_font)
        current = cv2.cvtColor(np.array(pil_cur), cv2.COLOR_RGB2BGR)

        # Hold
        for _ in range(HOLD_FRAMES):
            all_frames.append(current.copy())

    # Final hold on complete kinogram (3s)
    for _ in range(3 * FPS):
        all_frames.append(current.copy())

    print(f"  [5b] Animation: {len(all_frames)} total frames")

    # End card (1.5s)
    end_pil = Image.new("RGB", (OUT_W, OUT_H), DARK_BG)
    draw_end = ImageDraw.Draw(end_pil)
    bf = load_font(56, bold=True)
    tf = load_font(28, bold=False)
    text = "wellBowled.ai"
    bbox = draw_end.textbbox((0, 0), text, font=bf)
    draw_end.text(((OUT_W - bbox[2] + bbox[0]) // 2, OUT_H // 2 - 40), text, fill=PEACOCK, font=bf)
    tag = "Cricket biomechanics, visualized"
    bbox = draw_end.textbbox((0, 0), tag, font=tf)
    draw_end.text(((OUT_W - bbox[2] + bbox[0]) // 2, OUT_H // 2 + 30), tag, fill=WHITE, font=tf)
    end_frame = cv2.cvtColor(np.array(end_pil), cv2.COLOR_RGB2BGR)
    for _ in range(int(1.5 * FPS)):
        all_frames.append(end_frame)

    return all_frames


# ── Stage 6: Encode video ─────────────────────────────────────────────
def encode_video(frames: list[np.ndarray]) -> Path:
    final_path = OUTPUT_DIR / "kinogram.mp4"

    with tempfile.TemporaryDirectory() as tmpdir:
        for i, frame in enumerate(frames):
            cv2.imwrite(f"{tmpdir}/f_{i:06d}.jpg", frame, [cv2.IMWRITE_JPEG_QUALITY, 95])

        subprocess.run(
            [
                "ffmpeg", "-y",
                "-framerate", str(FPS),
                "-i", f"{tmpdir}/f_%06d.jpg",
                "-c:v", "libx264", "-preset", "medium", "-crf", "20",
                "-pix_fmt", "yuv420p", "-movflags", "+faststart",
                str(final_path),
            ],
            capture_output=True, check=True,
        )

    size_mb = final_path.stat().st_size / (1024 * 1024)
    duration = len(frames) / FPS
    print(f"  [6] Video: {final_path.name}, {duration:.1f}s, {size_mb:.1f}MB")
    return final_path


# ── Stage 7: Review ───────────────────────────────────────────────────
def review(video_path: Path):
    review_dir = OUTPUT_DIR / "review"
    review_dir.mkdir(exist_ok=True)

    probe = subprocess.run(
        ["ffprobe", "-v", "quiet", "-print_format", "json", "-show_streams", str(video_path)],
        capture_output=True, text=True, check=True,
    )
    vs = next(s for s in json.loads(probe.stdout)["streams"] if s["codec_type"] == "video")
    duration = float(vs["duration"])

    for label, t in [("start", 0.5), ("build", duration * 0.4), ("complete", duration * 0.7),
                     ("hold", duration * 0.85), ("end", duration * 0.95)]:
        subprocess.run(
            ["ffmpeg", "-y", "-ss", f"{t:.2f}", "-i", str(video_path),
             "-frames:v", "1", "-q:v", "2", str(review_dir / f"{label}.jpg")],
            capture_output=True, check=True,
        )

    print(f"  [7] Review: {vs['width']}x{vs['height']}, {duration:.1f}s, "
          f"{video_path.stat().st_size / 1024 / 1024:.1f}MB, {vs['codec_name']}")


# ── Main ──────────────────────────────────────────────────────────────
def main():
    import time
    start = time.time()

    print("=" * 50)
    print("  KINOGRAM PIPELINE")
    print("=" * 50)

    frames, meta = extract_frames(INPUT_CLIP)
    key_indices = select_key_frames(frames)
    pose_results = extract_poses(frames, key_indices)
    kinogram_img = build_kinogram(pose_results)
    anim_frames = animate_kinogram(pose_results, meta)
    video_path = encode_video(anim_frames)
    review(video_path)

    elapsed = time.time() - start
    print(f"\n{'=' * 50}")
    print(f"  DONE in {elapsed:.1f}s")
    print(f"  Hero: {OUTPUT_DIR / 'kinogram_hero.jpg'}")
    print(f"  Video: {video_path}")
    print(f"{'=' * 50}")


if __name__ == "__main__":
    main()
