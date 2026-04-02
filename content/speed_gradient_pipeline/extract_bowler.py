#!/usr/bin/env python3
"""Extract ONLY the bowler from a broadcast bowling clip.

Tech stack:
  1. Gemini Pro 3 (1 call) → bowler ROI per camera angle + phases
  2. Crop to ROI + bicubic upscale → bowler fills frame
  3. MediaPipe PoseLandmarker → identify which person is the bowler (first frame)
  4. SAM 2.1 video predictor → pixel-perfect segmentation across all frames
  5. FFmpeg → encode bowler-only video

Usage:
    cd content/speed_gradient_pipeline
    python extract_bowler.py
    python extract_bowler.py /path/to/clip.mp4
    python extract_bowler.py --skip-gemini
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
import numpy as np

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
PIPELINE_DIR = Path(__file__).resolve().parent
REPO_ROOT = PIPELINE_DIR.parents[1]
MODEL_PATH = REPO_ROOT / "resources" / "pose_landmarker_heavy.task"
SAM2_CHECKPOINT = REPO_ROOT / "resources" / "sam2_checkpoints" / "sam2.1_hiera_large.pt"
DEFAULT_CLIP = REPO_ROOT / "resources" / "samples" / "steyn_sa_vs_eng_broadcast_5sec.mp4"
OUTPUT_DIR = PIPELINE_DIR / "output" / "bowler_extract"

PRIMARY_JOINTS = [11, 12, 13, 14, 15, 16, 23, 24, 25, 26, 27, 28]
MIN_BOWLER_HEIGHT = 400

log = logging.getLogger("extract_bowler")


# ===================================================================
# GEMINI PRO 3 (1 call)
# ===================================================================
def _load_api_key() -> str | None:
    key = os.environ.get("GEMINI_API_KEY")
    if key:
        return key
    for env_path in [REPO_ROOT / "linux_content_pipeline_work" / ".env", REPO_ROOT / ".env"]:
        if env_path.exists():
            for line in env_path.read_text().splitlines():
                if line.startswith("GEMINI_API_KEY="):
                    return line.split("=", 1)[1].strip()
    return None


def _build_contact_sheet(frames: list[np.ndarray], fps: float) -> str:
    n = len(frames)
    n_samples = 8
    indices = [min(int(n * i / max(1, n_samples - 1)), n - 1) for i in range(n_samples)]
    h0, w0 = frames[0].shape[:2]
    tw, th = 320, int(320 * h0 / max(1, w0))
    cols, gutter = 4, 8
    rows = 2
    sw = cols * tw + (cols + 1) * gutter
    sh = 40 + rows * th + (rows + 1) * gutter
    canvas = np.full((sh, sw, 3), (13, 17, 23), dtype=np.uint8)
    for i, idx in enumerate(indices):
        r, c = i // cols, i % cols
        x = gutter + c * (tw + gutter)
        y = 40 + gutter + r * (th + gutter)
        canvas[y:y+th, x:x+tw] = cv2.resize(frames[idx], (tw, th))
        cv2.putText(canvas, f"F{i+1} {idx/fps:.2f}s", (x+4, y+18),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.5, (255, 255, 255), 1)
    path = str(OUTPUT_DIR / "contact_sheet.jpg")
    cv2.imwrite(path, canvas, [cv2.IMWRITE_JPEG_QUALITY, 90])
    return path


def call_gemini(frames: list[np.ndarray], fps: float) -> dict | None:
    api_key = _load_api_key()
    if not api_key:
        log.warning("[gemini] No API key")
        return None

    n = len(frames)
    sheet_path = _build_contact_sheet(frames, fps)
    with open(sheet_path, "rb") as f:
        b64 = base64.b64encode(f.read()).decode("utf-8")

    n_samples = 8
    indices = [min(int(n * i / max(1, n_samples - 1)), n - 1) for i in range(n_samples)]
    frame_list = "\n".join(f"- F{i+1}: frame {idx}, {idx/fps:.2f}s" for i, idx in enumerate(indices))

    prompt = f"""Cricket bowling broadcast clip: {n} frames, {fps:.0f}fps, {n/fps:.1f}s.
{frame_list}

Return STRICT JSON:
{{
  "camera_angles": [
    {{"start_frame": 0, "end_frame": 25, "type": "closeup|wide|medium"}}
  ],
  "bowler_roi_per_angle": {{
    "closeup": {{"x": 0.0, "y": 0.0, "w": 1.0, "h": 1.0}},
    "wide": {{"x": 0.0, "y": 0.0, "w": 1.0, "h": 1.0}}
  }},
  "bowler_center_frame0": {{"x": 0.5, "y": 0.5}},
  "phases": {{
    "back_foot_contact": 0.0,
    "front_foot_contact": 0.0,
    "release": 0.0
  }},
  "bowling_arm": "right|left",
  "bowler_description": "one sentence"
}}

Rules:
- bowler_roi_per_angle: TIGHT box around bowler with 15% padding. For wide shots this will be small.
- bowler_center_frame0: bowler's torso center in FIRST frame (normalized 0-1). Used to seed segmentation.
- Focus ONLY on the primary bowler."""

    payload = {
        "contents": [{"parts": [
            {"inlineData": {"mimeType": "image/jpeg", "data": b64}},
            {"text": prompt},
        ]}],
        "generationConfig": {"temperature": 0.1, "responseMimeType": "application/json"},
    }
    url = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key={api_key}"
    req = urllib.request.Request(url, data=json.dumps(payload).encode("utf-8"),
                                 headers={"Content-Type": "application/json"})
    try:
        log.info("[gemini] Calling gemini-2.5-pro ...")
        with urllib.request.urlopen(req, timeout=120) as resp:
            response = json.loads(resp.read().decode("utf-8"))
    except Exception as exc:
        log.error("[gemini] Error: %s", exc)
        return None

    try:
        text = response["candidates"][0]["content"]["parts"][0]["text"]
        result = json.loads(text)
    except (KeyError, IndexError, json.JSONDecodeError) as exc:
        log.error("[gemini] Parse error: %s", exc)
        return None

    cache = OUTPUT_DIR / "gemini_response.json"
    cache.parent.mkdir(parents=True, exist_ok=True)
    with cache.open("w") as f:
        json.dump({"result": result, "raw": response}, f, indent=2)

    log.info("[gemini] Bowler: %s", result.get("bowler_description"))
    log.info("[gemini] Phases: %s", result.get("phases"))
    for ca in result.get("camera_angles", []):
        log.info("[gemini] Angle: %s frames %s-%s", ca.get("type"), ca.get("start_frame"), ca.get("end_frame"))
    return result


# ===================================================================
# ROI MAP
# ===================================================================
def _build_roi_map(gemini: dict | None, n: int, w: int, h: int) -> list[dict]:
    if gemini is None:
        return [{"x": 0, "y": 0, "w": w, "h": h}] * n

    angles = gemini.get("camera_angles", [])
    rois = gemini.get("bowler_roi_per_angle", {})

    frame_type = ["wide"] * n
    for ca in angles:
        for f in range(max(0, ca.get("start_frame", 0)), min(n, ca.get("end_frame", n) + 1)):
            frame_type[f] = ca.get("type", "wide")

    roi_map = []
    for i in range(n):
        roi = rois.get(frame_type[i], {"x": 0, "y": 0, "w": 1, "h": 1})
        pad = 0.05
        rx = max(0, roi["x"] - pad)
        ry = max(0, roi["y"] - pad)
        rw = min(1.0 - rx, roi["w"] + 2 * pad)
        rh = min(1.0 - ry, roi["h"] + 2 * pad)
        roi_map.append({
            "x": max(0, int(rx * w)),
            "y": max(0, int(ry * h)),
            "w": max(1, min(int(rw * w), w)),
            "h": max(1, min(int(rh * h), h)),
        })
    return roi_map


# ===================================================================
# MEDIAIPE: Find bowler's center point in first frame
# ===================================================================
def find_bowler_center(frame_bgr: np.ndarray) -> tuple[int, int] | None:
    """Use MediaPipe to find the bowler's torso center in a frame."""
    import mediapipe as mp_lib

    if not MODEL_PATH.exists():
        return None

    options = mp_lib.tasks.vision.PoseLandmarkerOptions(
        base_options=mp_lib.tasks.BaseOptions(model_asset_path=str(MODEL_PATH)),
        running_mode=mp_lib.tasks.vision.RunningMode.IMAGE,
        num_poses=4,
        min_pose_detection_confidence=0.3,
    )

    rgb = cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2RGB)
    h, w = frame_bgr.shape[:2]

    with mp_lib.tasks.vision.PoseLandmarker.create_from_options(options) as lm:
        result = lm.detect(mp_lib.Image(image_format=mp_lib.ImageFormat.SRGB, data=rgb))

        if not result.pose_landmarks:
            return None

        # Pick largest person (bowler in close-up)
        best_area = -1
        best_center = None
        for pose in result.pose_landmarks:
            pts = [(p.x, p.y, p.visibility) for p in pose]
            xs = [pts[j][0] for j in PRIMARY_JOINTS if j < len(pts) and pts[j][2] > 0.3]
            ys = [pts[j][1] for j in PRIMARY_JOINTS if j < len(pts) and pts[j][2] > 0.3]
            if len(xs) < 4:
                continue
            area = (max(xs) - min(xs)) * (max(ys) - min(ys))
            if area > best_area:
                best_area = area
                cx = int(sum(xs) / len(xs) * w)
                cy = int(sum(ys) / len(ys) * h)
                best_center = (cx, cy)

    return best_center


# ===================================================================
# SAM 2: Video segmentation
# ===================================================================
def segment_with_sam2(
    frames_dir: Path,
    frame_count: int,
    bowler_point: tuple[int, int],
    frame_h: int,
    frame_w: int,
) -> list[np.ndarray]:
    """Use SAM 2.1 video predictor to segment the bowler across all frames.

    Args:
        frames_dir: directory with JPEG frames named 000000.jpg, 000001.jpg, ...
        frame_count: number of frames
        bowler_point: (x, y) pixel coordinates of bowler center in first frame
        frame_h, frame_w: frame dimensions

    Returns list of binary masks (one per frame).
    """
    import torch
    from sam2.build_sam import build_sam2_video_predictor

    device = "mps" if torch.backends.mps.is_available() else "cpu"
    log.info("[sam2] Device: %s", device)

    config = "configs/sam2.1/sam2.1_hiera_l.yaml"
    predictor = build_sam2_video_predictor(config, str(SAM2_CHECKPOINT), device=device)

    with torch.inference_mode():
        state = predictor.init_state(video_path=str(frames_dir))

        # Prompt with bowler center point on frame 0
        points = np.array([[bowler_point[0], bowler_point[1]]], dtype=np.float32)
        labels = np.array([1], dtype=np.int32)  # 1 = foreground

        _, obj_ids, mask_logits = predictor.add_new_points_or_box(
            inference_state=state,
            frame_idx=0,
            obj_id=1,
            points=points,
            labels=labels,
        )
        log.info("[sam2] Prompted on frame 0 at (%d, %d)", bowler_point[0], bowler_point[1])

        # Propagate through all frames
        masks = [None] * frame_count
        for frame_idx, obj_ids, mask_logits in predictor.propagate_in_video(state):
            mask = (mask_logits[0] > 0.0).cpu().numpy().squeeze()  # binary mask
            masks[frame_idx] = mask.astype(np.float32)

        predictor.reset_state(state)

    # Fill any None masks with zeros
    for i in range(frame_count):
        if masks[i] is None:
            masks[i] = np.zeros((frame_h, frame_w), dtype=np.float32)

    detected = sum(1 for m in masks if m.max() > 0)
    log.info("[sam2] %d/%d frames with bowler mask", detected, frame_count)
    return masks


# ===================================================================
# MAIN PIPELINE
# ===================================================================
def extract_bowler(clip_path: str, output_dir: Path, skip_gemini: bool = False) -> str:
    output_dir.mkdir(parents=True, exist_ok=True)

    # --- Read all frames ---
    cap = cv2.VideoCapture(clip_path)
    fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
    width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    all_frames = []
    while True:
        ok, f = cap.read()
        if not ok:
            break
        all_frames.append(f)
    cap.release()
    n = len(all_frames)
    log.info("[input] %dx%d, %.0ffps, %d frames (%.1fs)", width, height, fps, n, n / fps)

    # --- Step 1: Gemini (1 call) ---
    gemini = None
    cache = output_dir / "gemini_response.json"
    if skip_gemini and cache.exists():
        log.info("[gemini] Using cached response")
        with cache.open() as f:
            gemini = json.load(f).get("result")
    else:
        gemini = call_gemini(all_frames, fps)

    # --- Step 2-4: Process each camera angle separately ---
    angles = []
    if gemini and gemini.get("camera_angles"):
        angles = gemini["camera_angles"]
    if not angles:
        angles = [{"start_frame": 0, "end_frame": n - 1, "type": "full"}]

    rois = gemini.get("bowler_roi_per_angle", {}) if gemini else {}

    # Collect all masks in original frame space
    all_masks = [np.zeros((height, width), dtype=np.float32)] * n

    for ai, angle in enumerate(angles):
        atype = angle.get("type", "full")
        start = max(0, angle.get("start_frame", 0))
        end = min(n - 1, angle.get("end_frame", n - 1))
        seg_frames = list(range(start, end + 1))
        if not seg_frames:
            continue

        log.info("\n── Angle %d: %s (frames %d-%d, %d frames) ──",
                 ai + 1, atype, start, end, len(seg_frames))

        # Get ROI for this angle
        roi_norm = rois.get(atype, {"x": 0, "y": 0, "w": 1, "h": 1})
        pad = 0.08
        rx_n = max(0, roi_norm["x"] - pad)
        ry_n = max(0, roi_norm["y"] - pad)
        rw_n = min(1.0 - rx_n, roi_norm["w"] + 2 * pad)
        rh_n = min(1.0 - ry_n, roi_norm["h"] + 2 * pad)
        rx = max(0, int(rx_n * width))
        ry = max(0, int(ry_n * height))
        rw = max(1, min(int(rw_n * width), width - rx))
        rh = max(1, min(int(rh_n * height), height - ry))
        log.info("[crop] ROI: x=%d y=%d w=%d h=%d (%.0f%%x%.0f%% of frame)",
                 rx, ry, rw, rh, rw / width * 100, rh / height * 100)

        # Crop + upscale
        seg_dir = output_dir / f"seg_{ai}"
        if seg_dir.exists():
            shutil.rmtree(seg_dir)
        seg_dir.mkdir(parents=True)

        seg_crop_h = seg_crop_w = 0
        for si, fi in enumerate(seg_frames):
            crop = all_frames[fi][ry:ry+rh, rx:rx+rw]
            ch, cw = crop.shape[:2]
            if ch < MIN_BOWLER_HEIGHT:
                scale = MIN_BOWLER_HEIGHT / ch
                crop = cv2.resize(crop, (int(cw * scale), MIN_BOWLER_HEIGHT),
                                  interpolation=cv2.INTER_CUBIC)
            if si == 0:
                seg_crop_h, seg_crop_w = crop.shape[:2]
            else:
                crop = cv2.resize(crop, (seg_crop_w, seg_crop_h))
            cv2.imwrite(str(seg_dir / f"{si:06d}.jpg"), crop, [cv2.IMWRITE_JPEG_QUALITY, 95])

        log.info("[crop] Segment cropped to %dx%d", seg_crop_w, seg_crop_h)

        # Find bowler center in first frame of this segment
        first_crop = cv2.imread(str(seg_dir / "000000.jpg"))
        bowler_point = find_bowler_center(first_crop)
        if bowler_point is None:
            bowler_point = (seg_crop_w // 2, seg_crop_h // 2)
            log.info("[center] Fallback: (%d, %d)", *bowler_point)
        else:
            log.info("[center] MediaPipe: (%d, %d)", *bowler_point)

        # SAM 2 on this segment
        seg_masks = segment_with_sam2(seg_dir, len(seg_frames), bowler_point, seg_crop_h, seg_crop_w)

        # Map masks back to original frame coordinates
        for si, fi in enumerate(seg_frames):
            mask_crop = seg_masks[si]
            mask_roi = cv2.resize(mask_crop, (rw, rh), interpolation=cv2.INTER_LINEAR)
            mask_full = np.zeros((height, width), dtype=np.float32)
            mask_full[ry:ry+rh, rx:rx+rw] = mask_roi
            all_masks[fi] = mask_full

    # --- Step 5: Apply masks to original frames ---
    log.info("\n── Step 5: Apply masks ──")
    output_frames_dir = output_dir / "output_frames"
    if output_frames_dir.exists():
        shutil.rmtree(output_frames_dir)
    output_frames_dir.mkdir(parents=True)

    for i, frame in enumerate(all_frames):
        mask_3ch = np.stack([all_masks[i]] * 3, axis=2)
        masked = (frame.astype(np.float32) * mask_3ch).astype(np.uint8)
        cv2.imwrite(str(output_frames_dir / f"{i:06d}.jpg"), masked, [cv2.IMWRITE_JPEG_QUALITY, 95])

    # --- Step 6: Encode ---
    log.info("\n── Step 6: Encode ──")
    out_path = str(output_dir / "bowler_only.mp4")
    cmd = [
        "ffmpeg", "-y", "-framerate", str(fps),
        "-i", str(output_frames_dir / "%06d.jpg"),
        "-c:v", "libx264", "-preset", "medium", "-crf", "18",
        "-pix_fmt", "yuv420p", "-movflags", "+faststart",
        out_path,
    ]
    subprocess.run(cmd, capture_output=True)

    # Verify
    probe = subprocess.run(
        ["ffprobe", "-v", "quiet", "-print_format", "json", "-show_streams", out_path],
        capture_output=True, text=True,
    )
    if probe.returncode == 0:
        info = json.loads(probe.stdout)
        s = info.get("streams", [{}])[0]
        log.info("[output] %sx%s, %sfps, duration=%ss", s.get("width"), s.get("height"),
                 s.get("r_frame_rate"), s.get("duration"))

    # --- Review ---
    review_dir = output_dir / "review"
    if review_dir.exists():
        shutil.rmtree(review_dir)
    review_dir.mkdir()
    cap2 = cv2.VideoCapture(out_path)
    total = int(cap2.get(cv2.CAP_PROP_FRAME_COUNT))
    for pct in [0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 95]:
        idx = min(int(total * pct / 100), total - 1)
        cap2.set(cv2.CAP_PROP_POS_FRAMES, idx)
        ok, fr = cap2.read()
        if ok:
            cv2.imwrite(str(review_dir / f"review_{pct:02d}.png"), fr)
    cap2.release()

    # --- Stats ---
    detected = sum(1 for m in all_masks if m.max() > 0)
    stats = {
        "input": clip_path,
        "resolution": f"{width}x{height}",
        "fps": fps,
        "total_frames": n,
        "frames_with_mask": detected,
        "detection_rate": f"{detected/n*100:.1f}%",
        "gemini_calls": 0 if (skip_gemini and cache.exists()) else 1,
        "tech_stack": ["Gemini Pro 3", "MediaPipe PoseLandmarker", "SAM 2.1 (large)", "FFmpeg"],
        "crop_resolution": "per-angle",
        "output": out_path,
    }
    with (output_dir / "stats.json").open("w") as f:
        json.dump(stats, f, indent=2)

    log.info("\n" + "=" * 50)
    log.info("  STATS")
    for k, v in stats.items():
        log.info("  %s: %s", k, v)
    log.info("=" * 50)

    return out_path


# ===================================================================
# CLI
# ===================================================================
def main():
    parser = argparse.ArgumentParser(description="Extract bowler from broadcast clip")
    parser.add_argument("clip", nargs="?", default=str(DEFAULT_CLIP))
    parser.add_argument("--output", default=str(OUTPUT_DIR))
    parser.add_argument("--skip-gemini", action="store_true")
    args = parser.parse_args()

    logging.basicConfig(level=logging.INFO, format="%(message)s")
    output_dir = Path(args.output)

    log.info("=" * 50)
    log.info("  BOWLER EXTRACTION")
    log.info("  Gemini Pro 3 → Crop + Upscale → SAM 2.1")
    log.info("  Input: %s", args.clip)
    log.info("=" * 50)

    extract_bowler(args.clip, output_dir, skip_gemini=args.skip_gemini)


if __name__ == "__main__":
    main()
