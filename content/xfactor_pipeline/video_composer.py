"""Stage 6: Compose final 9:16 video with speed changes, freeze, and cards."""
from __future__ import annotations

import json
import os
import subprocess
import tempfile
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFont

OUTPUT_DIR = Path(__file__).resolve().parent / "output"
FRAMES_DIR = OUTPUT_DIR / "frames"
ANNOTATED_DIR = OUTPUT_DIR / "annotated"
XFACTOR_FILE = OUTPUT_DIR / "xfactor_data.json"
METADATA_FILE = OUTPUT_DIR / "clip_metadata.json"
INSIGHT_FILE = OUTPUT_DIR / "pro_insight.json"
INPUT_CLIP = Path(__file__).resolve().parents[2] / "resources" / "samples" / "3_sec_1_delivery_nets.mp4"
FINAL_VIDEO = OUTPUT_DIR / "final.mp4"

# Target output dimensions (9:16 portrait for Instagram)
OUT_W, OUT_H = 1080, 1920
FPS = 30

# Brand colors
DARK_BG_RGB = (13, 17, 23)
PEACOCK_RGB = (0, 109, 119)
WHITE_RGB = (255, 255, 255)
GOLD_RGB = (255, 215, 0)


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


def fit_frame_to_canvas(frame: np.ndarray, canvas_w: int = OUT_W, canvas_h: int = OUT_H) -> np.ndarray:
    """Scale and letterbox/pillarbox a frame to fit the target canvas."""
    h, w = frame.shape[:2]
    scale = min(canvas_w / w, canvas_h / h)
    new_w, new_h = int(w * scale), int(h * scale)
    resized = cv2.resize(frame, (new_w, new_h), interpolation=cv2.INTER_LANCZOS4)

    canvas = np.zeros((canvas_h, canvas_w, 3), dtype=np.uint8)
    canvas[:] = (13, 17, 23)  # dark bg in BGR
    x_off = (canvas_w - new_w) // 2
    y_off = (canvas_h - new_h) // 2
    canvas[y_off:y_off + new_h, x_off:x_off + new_w] = resized
    return canvas


def make_text_card(text_lines: list[str], duration_s: float, font_size: int = 40,
                   bg_color: tuple = DARK_BG_RGB, text_color: tuple = WHITE_RGB) -> list[np.ndarray]:
    """Generate frames for a text card."""
    pil_img = Image.new("RGB", (OUT_W, OUT_H), bg_color)
    draw = ImageDraw.Draw(pil_img)
    font = load_font(font_size, bold=True)
    font_small = load_font(font_size - 8, bold=False)

    total_height = 0
    line_data = []
    for i, line in enumerate(text_lines):
        f = font if i == 0 else font_small
        bbox = draw.textbbox((0, 0), line, font=f)
        tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
        line_data.append((line, f, tw, th))
        total_height += th + 16

    y = (OUT_H - total_height) // 2
    for line, f, tw, th in line_data:
        x = (OUT_W - tw) // 2
        draw.text((x, y), line, fill=text_color, font=f)
        y += th + 16

    frame = cv2.cvtColor(np.array(pil_img), cv2.COLOR_RGB2BGR)
    return [frame] * int(duration_s * FPS)


def make_end_card(duration_s: float = 1.5) -> list[np.ndarray]:
    """wellBowled.ai end card."""
    pil_img = Image.new("RGB", (OUT_W, OUT_H), DARK_BG_RGB)
    draw = ImageDraw.Draw(pil_img)

    font_brand = load_font(56, bold=True)
    font_tag = load_font(28, bold=False)

    # Brand name
    text = "wellBowled.ai"
    bbox = draw.textbbox((0, 0), text, font=font_brand)
    tw = bbox[2] - bbox[0]
    draw.text(((OUT_W - tw) // 2, OUT_H // 2 - 40), text, fill=PEACOCK_RGB, font=font_brand)

    # Tagline
    tag = "Cricket biomechanics, visualized"
    bbox = draw.textbbox((0, 0), tag, font=font_tag)
    tw = bbox[2] - bbox[0]
    draw.text(((OUT_W - tw) // 2, OUT_H // 2 + 30), tag, fill=WHITE_RGB, font=font_tag)

    frame = cv2.cvtColor(np.array(pil_img), cv2.COLOR_RGB2BGR)
    return [frame] * int(duration_s * FPS)


def make_legend_bar(frame: np.ndarray) -> np.ndarray:
    """Add a color legend bar at the bottom of a frame."""
    pil_img = Image.fromarray(cv2.cvtColor(frame, cv2.COLOR_BGR2RGB))
    draw = ImageDraw.Draw(pil_img)
    font = load_font(20, bold=False)

    bar_y = OUT_H - 50
    # Pink = Hips
    draw.rectangle([OUT_W // 2 - 200, bar_y, OUT_W // 2 - 170, bar_y + 20], fill=(255, 105, 180))
    draw.text((OUT_W // 2 - 165, bar_y - 2), "Hips", fill=WHITE_RGB, font=font)

    # Cyan = Shoulders
    draw.rectangle([OUT_W // 2 + 40, bar_y, OUT_W // 2 + 70, bar_y + 20], fill=(0, 206, 209))
    draw.text((OUT_W // 2 + 75, bar_y - 2), "Shoulders", fill=WHITE_RGB, font=font)

    return cv2.cvtColor(np.array(pil_img), cv2.COLOR_RGB2BGR)


def run() -> Path:
    xfactor = json.loads(XFACTOR_FILE.read_text())
    peak_idx = xfactor["peak_separation_frame"]
    peak_angle = xfactor["peak_separation_angle"]

    # Load insight text
    insight_lines = []
    if INSIGHT_FILE.exists():
        insight = json.loads(INSIGHT_FILE.read_text())
        insight_lines = [insight.get("hook", ""), insight.get("explanation", ""), insight.get("verdict", "")]
        insight_lines = [l for l in insight_lines if l]

    if not insight_lines:
        # Fallback based on angle
        if peak_angle > 40:
            insight_lines = ["Elite separation.", "This is where express pace comes from."]
        elif peak_angle > 25:
            insight_lines = ["Good separation.", "Room to unlock more pace with hip mobility work."]
        else:
            insight_lines = ["Limited separation.", "Hip mobility and delayed shoulder rotation", "are the keys to more speed."]

    # Load raw frames (for full-speed intro)
    raw_frames = sorted(FRAMES_DIR.glob("frame_*.jpg"))
    annotated_frames = sorted(ANNOTATED_DIR.glob("frame_*.jpg"))

    all_output_frames = []

    # --- Segment 1: Full speed raw (first ~1.5s worth of raw frames) ---
    # Raw frames are at 10fps, we need 30fps → triplicate each
    intro_count = min(15, len(raw_frames))  # ~1.5s at 10fps
    print(f"  Seg 1 (intro): {intro_count} raw frames → {intro_count * 3} output frames")
    for i in range(intro_count):
        img = cv2.imread(str(raw_frames[i]))
        canvas = fit_frame_to_canvas(img)

        # Add "Watch the hips and shoulders" text on first few frames
        if i < 10:
            pil = Image.fromarray(cv2.cvtColor(canvas, cv2.COLOR_BGR2RGB))
            draw = ImageDraw.Draw(pil)
            font = load_font(32, bold=True)
            text = "Watch the hips and shoulders."
            bbox = draw.textbbox((0, 0), text, font=font)
            tw = bbox[2] - bbox[0]
            draw.rounded_rectangle(
                [(OUT_W - tw) // 2 - 16, OUT_H - 140, (OUT_W + tw) // 2 + 16, OUT_H - 96],
                radius=10, fill=(0, 0, 0, 200),
            )
            draw.text(((OUT_W - tw) // 2, OUT_H - 136), text, fill=WHITE_RGB, font=font)
            canvas = cv2.cvtColor(np.array(pil), cv2.COLOR_RGB2BGR)

        # Triplicate for 30fps from 10fps source
        for _ in range(3):
            all_output_frames.append(canvas)

    # --- Segment 2: Slow-mo with overlays (0.25x = 12 copies per frame) ---
    # Show from start to peak
    slomo_frames = annotated_frames[:peak_idx + 1]
    print(f"  Seg 2 (slo-mo to peak): {len(slomo_frames)} frames × 12 = {len(slomo_frames) * 12} output frames")
    for frame_path in slomo_frames:
        img = cv2.imread(str(frame_path))
        canvas = fit_frame_to_canvas(img)
        canvas = make_legend_bar(canvas)
        for _ in range(12):  # 0.25x at 30fps from 10fps = 12 copies
            all_output_frames.append(canvas)

    # --- Segment 3: Freeze at peak (2s) ---
    peak_frame = cv2.imread(str(annotated_frames[peak_idx]))
    peak_canvas = fit_frame_to_canvas(peak_frame)
    peak_canvas = make_legend_bar(peak_canvas)
    freeze_count = int(2.0 * FPS)
    print(f"  Seg 3 (freeze): {freeze_count} frames (2s)")
    for _ in range(freeze_count):
        all_output_frames.append(peak_canvas)

    # --- Segment 4: Resume slo-mo from peak to end ---
    resume_frames = annotated_frames[peak_idx + 1:]
    resume_count = min(len(resume_frames), 15)  # Cap at ~1.5s of source
    print(f"  Seg 4 (resume): {resume_count} frames × 12 = {resume_count * 12} output frames")
    for frame_path in resume_frames[:resume_count]:
        img = cv2.imread(str(frame_path))
        canvas = fit_frame_to_canvas(img)
        canvas = make_legend_bar(canvas)
        for _ in range(12):
            all_output_frames.append(canvas)

    # --- Segment 5: Verdict card (2.5s) ---
    verdict_frames = make_text_card(
        [f"X-FACTOR: {peak_angle:.0f}°", ""] + insight_lines,
        duration_s=2.5, font_size=48,
    )
    print(f"  Seg 5 (verdict): {len(verdict_frames)} frames")
    all_output_frames.extend(verdict_frames)

    # --- Segment 6: End card (1.5s) ---
    end_frames = make_end_card(1.5)
    print(f"  Seg 6 (end card): {len(end_frames)} frames")
    all_output_frames.extend(end_frames)

    total_duration = len(all_output_frames) / FPS
    print(f"  Total: {len(all_output_frames)} frames = {total_duration:.1f}s")

    # Write frames to temp dir, then encode with FFmpeg
    with tempfile.TemporaryDirectory() as tmpdir:
        print("  Writing temp frames...")
        for i, frame in enumerate(all_output_frames):
            cv2.imwrite(f"{tmpdir}/f_{i:06d}.jpg", frame, [cv2.IMWRITE_JPEG_QUALITY, 95])

        print("  Encoding with FFmpeg...")
        subprocess.run(
            [
                "ffmpeg", "-y",
                "-framerate", str(FPS),
                "-i", f"{tmpdir}/f_%06d.jpg",
                "-c:v", "libx264",
                "-preset", "medium",
                "-crf", "20",
                "-pix_fmt", "yuv420p",
                "-movflags", "+faststart",
                str(FINAL_VIDEO),
            ],
            capture_output=True, check=True,
        )

    size_mb = FINAL_VIDEO.stat().st_size / (1024 * 1024)
    print(f"  Output: {FINAL_VIDEO}")
    print(f"  Size: {size_mb:.1f} MB, Duration: {total_duration:.1f}s")

    return FINAL_VIDEO


if __name__ == "__main__":
    run()
