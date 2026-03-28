#!/usr/bin/env python3
"""Goniogram Pipeline — joint angle overlay on bowling action.

Draws elbow angle, front knee angle, and bowling arm arc directly on the video.
Color-coded: green=good, yellow=borderline, red=concern.
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
ANNOTATED_DIR = OUTPUT_DIR / "annotated"
MODEL_PATH = Path(__file__).resolve().parent / "pose_landmarker_heavy.task"
MODEL_URL = "https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_heavy/float16/latest/pose_landmarker_heavy.task"

OUT_W, OUT_H = 1080, 1920
FPS = 30
DARK_BG = (13, 17, 23)
PEACOCK = (0, 109, 119)
WHITE = (255, 255, 255)

# Landmark indices (right-arm bowler assumed)
R_SHOULDER, R_ELBOW, R_WRIST = 12, 14, 16
L_HIP, L_KNEE, L_ANKLE = 23, 25, 27  # front leg
R_HIP, R_KNEE, R_ANKLE = 24, 26, 28  # back leg

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


def angle_color(angle: float, good_range: tuple[float, float],
                warn_range: tuple[float, float]) -> tuple[int, int, int]:
    """Return BGR color based on angle quality."""
    if good_range[0] <= angle <= good_range[1]:
        return (0, 200, 0)      # green
    elif warn_range[0] <= angle <= warn_range[1]:
        return (0, 200, 255)    # yellow/orange
    else:
        return (0, 0, 220)      # red


def angle_color_rgb(angle: float, good_range: tuple, warn_range: tuple) -> tuple:
    bgr = angle_color(angle, good_range, warn_range)
    return (bgr[2], bgr[1], bgr[0])


def draw_angle_arc(img: np.ndarray, center: tuple[int, int],
                   pt_a: tuple[int, int], pt_c: tuple[int, int],
                   angle_deg: float, color: tuple[int, int, int],
                   radius: int = 40, thickness: int = 2):
    """Draw an arc showing the angle at center between pt_a and pt_c."""
    angle_a = math.degrees(math.atan2(pt_a[1] - center[1], pt_a[0] - center[0]))
    angle_c = math.degrees(math.atan2(pt_c[1] - center[1], pt_c[0] - center[0]))

    start = min(angle_a, angle_c)
    end = max(angle_a, angle_c)
    if end - start > 180:
        start, end = end, start + 360

    cv2.ellipse(img, center, (radius, radius), 0, start, end, color, thickness, cv2.LINE_AA)


def lm_px(landmarks: list[dict], idx: int, w: int, h: int) -> tuple[int, int]:
    """Get pixel coordinates from normalized landmark."""
    return (int(landmarks[idx]["x"] * w), int(landmarks[idx]["y"] * h))


def lm_vis(landmarks: list[dict], idx: int) -> float:
    return landmarks[idx]["vis"]


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
        ["ffmpeg", "-y", "-i", str(INPUT_CLIP), "-vf", "fps=10", "-q:v", "2",
         str(FRAMES_DIR / "f_%04d.jpg")],
        capture_output=True, check=True,
    )
    frames = sorted(FRAMES_DIR.glob("f_*.jpg"))
    meta["extracted"] = len(frames)
    print(f"  [1] Extracted {len(frames)} frames at 10fps")
    return frames, meta


# ── Stage 2: Pose extraction ──────────────────────────────────────────
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
    prev_centroid = None  # track bowler across frames by centroid continuity

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
                        # First frame: pick largest
                        best = max(candidates, key=lambda c: c["size"])
                    else:
                        # Subsequent frames: pick closest to previous centroid
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


# ── Stage 3: Compute angles + render overlays ─────────────────────────
def render_goniogram_frames(pose_data: list[dict]) -> tuple[list[np.ndarray], dict]:
    ANNOTATED_DIR.mkdir(parents=True, exist_ok=True)

    angle_history = {"elbow": [], "front_knee": [], "arm_vertical": []}
    peak_elbow = {"angle": 0, "frame_idx": 0}
    peak_knee = {"angle": 0, "frame_idx": 0}
    all_canvases = []

    # Delivery zone: frames 2-25 (0.2s to 2.5s) — skip pre-runup and post-delivery
    delivery_start, delivery_end = 2, min(25, len(pose_data) - 1)

    for fi, pd in enumerate(pose_data):
        img = cv2.imread(pd["path"])
        h, w = img.shape[:2]
        lm = pd.get("landmarks")

        # Fit to 9:16 canvas
        scale = min(OUT_W / w, OUT_H * 0.78 / h)
        new_w, new_h = int(w * scale), int(h * scale)
        x_off = (OUT_W - new_w) // 2
        y_off = 100

        canvas = np.zeros((OUT_H, OUT_W, 3), dtype=np.uint8)
        canvas[:] = DARK_BG[::-1]
        resized = cv2.resize(img, (new_w, new_h), interpolation=cv2.INTER_LANCZOS4)
        canvas[y_off:y_off + new_h, x_off:x_off + new_w] = resized

        elbow_angle = None
        knee_angle = None
        arm_angle = None

        in_delivery = delivery_start <= fi <= delivery_end

        if lm and in_delivery:
            # Helper to get canvas-space pixel coords
            def px(idx):
                return (x_off + int(lm[idx]["x"] * new_w),
                        y_off + int(lm[idx]["y"] * new_h))

            def vis(idx):
                return lm[idx]["vis"]

            # Draw faded skeleton
            overlay = canvas.copy()
            for j1, j2 in POSE_CONNECTIONS:
                if vis(j1) < 0.3 or vis(j2) < 0.3:
                    continue
                cv2.line(overlay, px(j1), px(j2), (180, 180, 180), 2, cv2.LINE_AA)
            cv2.addWeighted(overlay, 0.3, canvas, 0.7, 0, canvas)

            # === ELBOW ANGLE (bowling arm) ===
            if all(vis(i) > 0.4 for i in [R_SHOULDER, R_ELBOW, R_WRIST]):
                elbow_angle = angle_between(px(R_SHOULDER), px(R_ELBOW), px(R_WRIST))
                # For bowling legality, we care about extension (180° = fully straight)
                # ICC limit: <15° flexion from straight = legal
                extension = 180 - elbow_angle  # how far from straight
                elbow_color = angle_color(extension, (0, 15), (15, 25))

                # Draw arm segments highlighted
                cv2.line(canvas, px(R_SHOULDER), px(R_ELBOW), elbow_color, 6, cv2.LINE_AA)
                cv2.line(canvas, px(R_ELBOW), px(R_WRIST), elbow_color, 6, cv2.LINE_AA)

                # Draw arc at elbow
                draw_angle_arc(canvas, px(R_ELBOW), px(R_SHOULDER), px(R_WRIST),
                               elbow_angle, elbow_color, radius=70, thickness=5)

                # Joint dots
                for idx in [R_SHOULDER, R_ELBOW, R_WRIST]:
                    cv2.circle(canvas, px(idx), 8, elbow_color, -1, cv2.LINE_AA)
                    cv2.circle(canvas, px(idx), 8, (255, 255, 255), 2, cv2.LINE_AA)

                if extension > peak_elbow["angle"] and delivery_start <= fi <= delivery_end:
                    peak_elbow = {"angle": extension, "frame_idx": fi}

            # === FRONT KNEE ANGLE ===
            if all(vis(i) > 0.4 for i in [L_HIP, L_KNEE, L_ANKLE]):
                knee_angle = angle_between(px(L_HIP), px(L_KNEE), px(L_ANKLE))
                # Good brace: 160-180° (near straight). Collapsing: <140°
                knee_color = angle_color(knee_angle, (155, 180), (140, 155))

                cv2.line(canvas, px(L_HIP), px(L_KNEE), knee_color, 6, cv2.LINE_AA)
                cv2.line(canvas, px(L_KNEE), px(L_ANKLE), knee_color, 6, cv2.LINE_AA)

                draw_angle_arc(canvas, px(L_KNEE), px(L_HIP), px(L_ANKLE),
                               knee_angle, knee_color, radius=70, thickness=5)

                for idx in [L_HIP, L_KNEE, L_ANKLE]:
                    cv2.circle(canvas, px(idx), 8, knee_color, -1, cv2.LINE_AA)
                    cv2.circle(canvas, px(idx), 8, (255, 255, 255), 2, cv2.LINE_AA)

                if knee_angle > peak_knee["angle"] and delivery_start <= fi <= delivery_end:
                    peak_knee = {"angle": knee_angle, "frame_idx": fi}

            # === BOWLING ARM ANGLE FROM VERTICAL ===
            if all(vis(i) > 0.4 for i in [R_SHOULDER, R_WRIST]):
                s = px(R_SHOULDER)
                wr = px(R_WRIST)
                # Angle of arm from straight up (vertical)
                vertical_pt = (s[0], s[1] - 100)  # point straight up
                arm_angle = angle_between(vertical_pt, s, wr)

        # Record history
        angle_history["elbow"].append(elbow_angle)
        angle_history["front_knee"].append(knee_angle)
        angle_history["arm_vertical"].append(arm_angle)

        # === TEXT OVERLAYS (Pillow for clean typography) ===
        pil = Image.fromarray(cv2.cvtColor(canvas, cv2.COLOR_BGR2RGB))
        draw = ImageDraw.Draw(pil)

        font_title = load_font(36, bold=True)
        font_angle = load_font(28, bold=True)
        font_label = load_font(18, bold=False)
        font_small = load_font(16, bold=False)

        # Title
        draw.text((OUT_W // 2 - 100, 20), "GONIOGRAM", fill=WHITE, font=font_title)

        # Angle readouts panel (bottom)
        panel_y = y_off + new_h + 20
        panel_x = 40

        if elbow_angle is not None:
            extension = 180 - elbow_angle
            ec = angle_color_rgb(extension, (0, 15), (15, 25))
            verdict = "LEGAL" if extension <= 15 else "BORDERLINE" if extension <= 25 else "ILLEGAL"
            draw.text((panel_x, panel_y), f"Elbow: {extension:.0f}°", fill=ec, font=font_angle)
            draw.text((panel_x + 180, panel_y + 4), verdict, fill=ec, font=font_label)

        if knee_angle is not None:
            kc = angle_color_rgb(knee_angle, (155, 180), (140, 155))
            verdict = "STRONG" if knee_angle >= 155 else "OK" if knee_angle >= 140 else "COLLAPSING"
            draw.text((panel_x, panel_y + 42), f"Front Knee: {knee_angle:.0f}°", fill=kc, font=font_angle)
            draw.text((panel_x + 240, panel_y + 46), verdict, fill=kc, font=font_label)

        if arm_angle is not None:
            draw.text((panel_x, panel_y + 84), f"Arm: {arm_angle:.0f}° from vertical",
                       fill=(180, 180, 180), font=font_small)

        # Phase indicator (time)
        time_s = fi / 10.0
        draw.text((OUT_W - 120, panel_y), f"{time_s:.1f}s", fill=(120, 120, 120), font=font_label)

        # Brand
        brand_font = load_font(20, bold=True)
        draw.text((OUT_W - 180, OUT_H - 45), "wellBowled.ai", fill=PEACOCK, font=brand_font)

        canvas = cv2.cvtColor(np.array(pil), cv2.COLOR_RGB2BGR)

        # Save annotated frame
        cv2.imwrite(str(ANNOTATED_DIR / pd["frame"]), canvas, [cv2.IMWRITE_JPEG_QUALITY, 95])
        all_canvases.append(canvas)

    print(f"  [3] Rendered {len(all_canvases)} goniogram frames")
    print(f"      Peak elbow extension: {peak_elbow['angle']:.0f}° at frame {peak_elbow['frame_idx']}")
    print(f"      Peak knee angle: {peak_knee['angle']:.0f}° at frame {peak_knee['frame_idx']}")

    return all_canvases, {"peak_elbow": peak_elbow, "peak_knee": peak_knee,
                          "history": angle_history}


# ── Stage 4: Compose video ────────────────────────────────────────────
def compose_video(canvases: list[np.ndarray], angle_data: dict) -> Path:
    final_path = OUTPUT_DIR / "goniogram.mp4"

    all_frames = []

    # Segment 1: Full speed raw intro (1.5s)
    raw_frames = sorted(FRAMES_DIR.glob("f_*.jpg"))
    for i in range(min(15, len(raw_frames))):
        img = cv2.imread(str(raw_frames[i]))
        h, w = img.shape[:2]
        scale = min(OUT_W / w, OUT_H * 0.78 / h)
        nw, nh = int(w * scale), int(h * scale)
        canvas = np.zeros((OUT_H, OUT_W, 3), dtype=np.uint8)
        canvas[:] = DARK_BG[::-1]
        resized = cv2.resize(img, (nw, nh), interpolation=cv2.INTER_LANCZOS4)
        xo, yo = (OUT_W - nw) // 2, 100
        canvas[yo:yo + nh, xo:xo + nw] = resized

        # Add "Watch the angles" text
        if i < 12:
            pil = Image.fromarray(cv2.cvtColor(canvas, cv2.COLOR_BGR2RGB))
            d = ImageDraw.Draw(pil)
            f = load_font(32, bold=True)
            text = "Watch the angles."
            bbox = d.textbbox((0, 0), text, font=f)
            tw = bbox[2] - bbox[0]
            d.rounded_rectangle([(OUT_W - tw) // 2 - 16, OUT_H - 140,
                                  (OUT_W + tw) // 2 + 16, OUT_H - 96],
                                 radius=10, fill=(0, 0, 0, 200))
            d.text(((OUT_W - tw) // 2, OUT_H - 136), text, fill=WHITE, font=f)
            canvas = cv2.cvtColor(np.array(pil), cv2.COLOR_RGB2BGR)

        for _ in range(3):  # 10fps → 30fps
            all_frames.append(canvas)

    # Segment 2: Slo-mo with angle overlays (0.25x)
    for canvas in canvases:
        for _ in range(12):  # 10fps × 12 = 0.25x at 30fps
            all_frames.append(canvas)

    # Segment 3: Freeze on peak elbow frame (2s)
    peak_idx = angle_data["peak_elbow"]["frame_idx"]
    if peak_idx < len(canvases):
        peak_frame = canvases[peak_idx]
        # Add "PEAK" badge
        pil = Image.fromarray(cv2.cvtColor(peak_frame, cv2.COLOR_BGR2RGB))
        d = ImageDraw.Draw(pil)
        f = load_font(28, bold=True)
        ext = angle_data["peak_elbow"]["angle"]
        verdict = "LEGAL" if ext <= 15 else "BORDERLINE" if ext <= 25 else "CHECK"
        badge = f"PEAK ELBOW: {ext:.0f}° — {verdict}"
        bbox = d.textbbox((0, 0), badge, font=f)
        tw = bbox[2] - bbox[0]
        bx = (OUT_W - tw) // 2 - 16
        by = OUT_H // 2 - 60
        color = (0, 200, 0) if ext <= 15 else (255, 200, 0) if ext <= 25 else (220, 50, 50)
        d.rounded_rectangle([bx, by, bx + tw + 32, by + 48], radius=12,
                             fill=(0, 0, 0, 220), outline=color, width=2)
        d.text((bx + 16, by + 10), badge, fill=color, font=f)
        peak_canvas = cv2.cvtColor(np.array(pil), cv2.COLOR_RGB2BGR)
        for _ in range(2 * FPS):
            all_frames.append(peak_canvas)

    # Segment 4: Verdict card (2.5s)
    verdict_pil = Image.new("RGB", (OUT_W, OUT_H), DARK_BG)
    d = ImageDraw.Draw(verdict_pil)
    f_big = load_font(44, bold=True)
    f_med = load_font(32, bold=False)
    f_sm = load_font(24, bold=False)

    ext = angle_data["peak_elbow"]["angle"]
    knee = angle_data["peak_knee"]["angle"]

    y = OUT_H // 2 - 120
    d.text((OUT_W // 2 - 150, y), "ANGLE ANALYSIS", fill=WHITE, font=f_big)
    y += 70

    ec = angle_color_rgb(ext, (0, 15), (15, 25))
    d.text((OUT_W // 2 - 180, y), f"Elbow extension: {ext:.0f}°", fill=ec, font=f_med)
    y += 50

    kc = angle_color_rgb(knee, (155, 180), (140, 155))
    d.text((OUT_W // 2 - 180, y), f"Front knee: {knee:.0f}°", fill=kc, font=f_med)
    y += 70

    if ext <= 15:
        d.text((OUT_W // 2 - 180, y), "Legal bowling action.", fill=(0, 200, 0), font=f_sm)
    elif ext <= 25:
        d.text((OUT_W // 2 - 180, y), "Borderline — monitor closely.", fill=(255, 200, 0), font=f_sm)
    else:
        d.text((OUT_W // 2 - 180, y), "Excessive extension — needs correction.", fill=(220, 50, 50), font=f_sm)

    verdict_frame = cv2.cvtColor(np.array(verdict_pil), cv2.COLOR_RGB2BGR)
    for _ in range(int(2.5 * FPS)):
        all_frames.append(verdict_frame)

    # End card (1.5s)
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
    print(f"  [4] Video: {duration:.1f}s, {size_mb:.1f}MB")
    return final_path


# ── Stage 5: Review ───────────────────────────────────────────────────
def review(video_path: Path):
    review_dir = OUTPUT_DIR / "review"
    review_dir.mkdir(exist_ok=True)

    probe = subprocess.run(
        ["ffprobe", "-v", "quiet", "-print_format", "json", "-show_streams", str(video_path)],
        capture_output=True, text=True, check=True,
    )
    vs = next(s for s in json.loads(probe.stdout)["streams"] if s["codec_type"] == "video")
    duration = float(vs["duration"])

    for label, t in [("intro", 0.5), ("angles_early", duration * 0.2),
                     ("angles_mid", duration * 0.4), ("peak", duration * 0.6),
                     ("verdict", duration * 0.8), ("end", duration * 0.95)]:
        subprocess.run(
            ["ffmpeg", "-y", "-ss", f"{t:.2f}", "-i", str(video_path),
             "-frames:v", "1", "-q:v", "2", str(review_dir / f"{label}.jpg")],
            capture_output=True, check=True,
        )

    print(f"  [5] Review: {vs['width']}x{vs['height']}, {duration:.1f}s, "
          f"{video_path.stat().st_size / 1024 / 1024:.1f}MB")


# ── Main ──────────────────────────────────────────────────────────────
def main():
    import time
    start = time.time()

    print("=" * 50)
    print("  GONIOGRAM PIPELINE")
    print("=" * 50)

    frames, meta = extract_frames()
    pose_data = extract_all_poses(frames)
    canvases, angle_data = render_goniogram_frames(pose_data)
    video_path = compose_video(canvases, angle_data)
    review(video_path)

    elapsed = time.time() - start
    print(f"\n{'=' * 50}")
    print(f"  DONE in {elapsed:.1f}s")
    print(f"  Video: {video_path}")
    print(f"{'=' * 50}")


if __name__ == "__main__":
    main()
