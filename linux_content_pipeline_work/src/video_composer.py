"""Stage 6+8: Compose final YouTube-ready 9:16 video."""
from __future__ import annotations

import subprocess
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

BG_DARK = (10, 14, 20)
WHITE = (255, 255, 255)
HIP_COLOR = (255, 105, 180)
SHOULDER_COLOR = (0, 206, 209)


def _load_font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    candidates = []
    if bold:
        candidates = [
            "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
            "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
        ]
    else:
        candidates = [
            "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf",
            "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        ]
    for c in candidates:
        if Path(c).exists():
            try:
                return ImageFont.truetype(c, size=size)
            except OSError:
                continue
    return ImageFont.load_default()


def _wrap_text(draw: ImageDraw.ImageDraw, text: str, font, max_width: int) -> list[str]:
    words = text.split()
    if not words:
        return []
    lines = [words[0]]
    for word in words[1:]:
        trial = f"{lines[-1]} {word}"
        if draw.textlength(trial, font=font) <= max_width:
            lines[-1] = trial
        else:
            lines.append(word)
    return lines


def _make_canvas(width: int, height: int) -> Image.Image:
    """9:16 dark canvas."""
    return Image.new("RGB", (width, height), BG_DARK)


def _fit_frame_to_canvas(frame_bgr: np.ndarray, canvas_w: int, canvas_h: int) -> Image.Image:
    """Fit a frame into 9:16 canvas, letterboxing if needed."""
    frame_rgb = cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2RGB)
    img = Image.fromarray(frame_rgb)
    fw, fh = img.size

    # Scale to fill width, center vertically
    scale = canvas_w / fw
    new_w = canvas_w
    new_h = int(fh * scale)
    img = img.resize((new_w, new_h), Image.Resampling.LANCZOS)

    canvas = _make_canvas(canvas_w, canvas_h)
    y_offset = (canvas_h - new_h) // 2
    canvas.paste(img, (0, y_offset))
    return canvas


def make_intro_card(
    frame_bgr: np.ndarray,
    canvas_w: int,
    canvas_h: int,
) -> Image.Image:
    """Cold open card: raw frame, no overlay, just 'WATCH THIS DELIVERY' badge."""
    canvas = _fit_frame_to_canvas(frame_bgr, canvas_w, canvas_h)
    draw = ImageDraw.Draw(canvas)
    font = _load_font(20, bold=True)
    label = "WATCH THIS DELIVERY"
    tw = draw.textlength(label, font=font)
    pw = int(tw + 32)
    ph = 36
    px = canvas_w // 2 - pw // 2
    py = canvas_h - 80
    draw.rounded_rectangle((px, py, px + pw, py + ph), radius=14, fill=(10, 14, 20, 200))
    draw.text((px + 16, py + 8), label, font=font, fill=WHITE)
    return canvas


def make_freeze_card(
    frame_bgr: np.ndarray,
    peak_separation: float,
    canvas_w: int,
    canvas_h: int,
) -> Image.Image:
    """Freeze frame at peak separation with PEAK X-FACTOR badge."""
    canvas = _fit_frame_to_canvas(frame_bgr, canvas_w, canvas_h)

    # Heavy darken for dramatic freeze effect
    overlay = Image.new("RGB", (canvas_w, canvas_h), BG_DARK)
    canvas = Image.blend(canvas, overlay, 0.65)
    draw = ImageDraw.Draw(canvas)

    font_huge = _load_font(72, bold=True)
    font_label = _load_font(28, bold=True)
    font_sub = _load_font(22, bold=False)

    cx = canvas_w // 2
    cy = canvas_h // 2 - 60

    # PEAK X-FACTOR label
    peak_label = "PEAK X-FACTOR"
    ptw = draw.textlength(peak_label, font=font_label)
    draw.text((cx - ptw // 2, cy - 50), peak_label, font=font_label, fill=WHITE)

    # Big angle number center — large and dramatic
    angle_text = f"{peak_separation:.0f}\u00b0"
    tw = draw.textlength(angle_text, font=font_huge)
    draw.text((cx - tw // 2, cy), angle_text, font=font_huge, fill=(255, 80, 60))

    # Sub text
    sub = "Hip-shoulder separation at maximum"
    stw = draw.textlength(sub, font=font_sub)
    draw.text((cx - stw // 2, cy + 80), sub, font=font_sub, fill=(180, 190, 200))

    # Legend at bottom
    ly = canvas_h - 60
    draw.ellipse((cx - 110, ly, cx - 96, ly + 14), fill=HIP_COLOR)
    draw.text((cx - 88, ly - 1), "hips", font=font_sub, fill=(200, 200, 200))
    draw.ellipse((cx + 20, ly, cx + 34, ly + 14), fill=SHOULDER_COLOR)
    draw.text((cx + 42, ly - 1), "shoulders", font=font_sub, fill=(200, 200, 200))

    return canvas


def make_verdict_card(
    frame_bgr: np.ndarray,
    peak_separation: float,
    insight_lines: list[str],
    canvas_w: int,
    canvas_h: int,
) -> Image.Image:
    """End card with verdict and coaching insight."""
    frame_rgb = cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2RGB)
    bg = Image.fromarray(frame_rgb).resize((canvas_w, canvas_h), Image.Resampling.LANCZOS)
    bg = bg.filter(ImageFilter.GaussianBlur(radius=6))
    overlay = Image.new("RGB", (canvas_w, canvas_h), BG_DARK)
    canvas = Image.blend(bg, overlay, 0.75)
    draw = ImageDraw.Draw(canvas)

    font_title = _load_font(36, bold=True)
    font_body = _load_font(20, bold=False)
    font_label = _load_font(16, bold=True)
    font_brand = _load_font(14, bold=False)

    cx = canvas_w // 2

    # Title
    title = "X-FACTOR VERDICT"
    tw = draw.textlength(title, font=font_title)
    draw.text((cx - tw // 2, 100), title, font=font_title, fill=(255, 80, 60))

    # Angle
    angle_text = f"{peak_separation:.0f}\u00b0 peak separation"
    atw = draw.textlength(angle_text, font=font_body)
    draw.text((cx - atw // 2, 150), angle_text, font=font_body, fill=WHITE)

    # Rating — calibrated against elite fast bowlers
    # Brett Lee: ~40-50°, Steyn: ~35-45°, Good club: ~30-35°
    if peak_separation >= 45:
        rating = "ELITE"
        rating_color = (100, 255, 100)
        rating_note = "Brett Lee / Steyn territory"
    elif peak_separation >= 35:
        rating = "VERY GOOD"
        rating_color = (130, 230, 130)
        rating_note = "Strong rotational mechanics"
    elif peak_separation >= 28:
        rating = "DEVELOPING"
        rating_color = (255, 220, 80)
        rating_note = "Room to lead more with the hip"
    else:
        rating = "WORK ON IT"
        rating_color = (255, 140, 60)
        rating_note = "Focus on hip pre-rotation drills"

    rtw = draw.textlength(rating, font=font_title)
    draw.text((cx - rtw // 2, 190), rating, font=font_title, fill=rating_color)

    # Reference comparison bar
    font_ref = _load_font(14, bold=False)
    bar_y = 240
    bar_x = 60
    bar_w = canvas_w - 120
    draw.rounded_rectangle((bar_x, bar_y, bar_x + bar_w, bar_y + 40), radius=8, fill=(30, 34, 44))

    # Scale: 0-60°
    def angle_to_x(a: float) -> int:
        return bar_x + int((min(60, max(0, a)) / 60) * bar_w)

    # Reference markers
    for label, angle, color in [
        ("You", peak_separation, (255, 255, 255)),
        ("Steyn", 40, SHOULDER_COLOR),
        ("Lee", 47, HIP_COLOR),
    ]:
        x = angle_to_x(angle)
        draw.line((x, bar_y + 2, x, bar_y + 38), fill=color, width=3)
        lw = draw.textlength(label, font=font_ref)
        draw.text((x - lw // 2, bar_y + 42), label, font=font_ref, fill=color)

    # Rating note
    font_note = _load_font(16, bold=False)
    nw = draw.textlength(rating_note, font=font_note)
    draw.text((cx - nw // 2, bar_y + 62), rating_note, font=font_note, fill=(180, 190, 200))

    # Insight lines (below comparison bar)
    y = bar_y + 90
    for line in insight_lines[:3]:
        wrapped = _wrap_text(draw, line, font_body, canvas_w - 60)
        for wl in wrapped:
            wlw = draw.textlength(wl, font=font_body)
            draw.text((cx - wlw // 2, y), wl, font=font_body, fill=(220, 225, 235))
            y += 28

    # Brand watermark
    brand = "wellBowled.ai"
    bw = draw.textlength(brand, font=font_brand)
    draw.text((cx - bw // 2, canvas_h - 40), brand, font=font_brand, fill=(100, 110, 120))

    return canvas


def compose_video(
    frames: list[dict],
    peak_frame: dict | None,
    phases: dict,
    output_path: str,
    fps: float,
    insight_lines: list[str] | None = None,
) -> str:
    """Compose the final video.

    Structure:
    1. Cold open (1x speed, ~1s)
    2. Slow-mo replay with overlays (0.25x)
    3. Freeze at peak separation (~2s)
    4. Resume slow-mo to follow-through
    5. Verdict card (~3s)
    """
    if insight_lines is None:
        insight_lines = [
            "The gap between hips and shoulders generates pace.",
            "Bigger separation = more stored energy at release.",
            "Work on leading with the hip, letting the shoulder lag.",
        ]

    # Target 9:16 canvas
    canvas_w = 1080
    canvas_h = 1920

    output_fps = 30.0
    slow_factor = 4  # 0.25x

    rendered_frames: list[Image.Image] = []

    # 1. Cold open — real full-speed frames, no overlay, just raw action
    from .overlay_renderer import render_frame_overlay, render_legend

    # Play all frames at 1x speed with just a subtle "WATCH THIS" badge
    for frame in frames:
        canvas = _fit_frame_to_canvas(frame["frame_bgr"], canvas_w, canvas_h)
        rendered_frames.append(canvas)

    # Brief transition hold (0.3s black)
    black = _make_canvas(canvas_w, canvas_h)
    rendered_frames.extend([black] * int(output_fps * 0.3))

    # 2. Slow-mo replay with overlays

    peak_sep = peak_frame["separation"] if peak_frame else None
    peak_idx = peak_frame["index"] if peak_frame else -1

    # Delivery window: only show overlays between back_foot_contact and follow_through
    overlay_start = phases.get("back_foot_contact", 0)
    overlay_end = phases.get("follow_through", frames[-1]["time"] if frames else 1.0)
    # Add small buffer before/after
    overlay_start = max(0, overlay_start - 0.15)
    overlay_end = overlay_end + 0.2

    for frame in frames:
        sep = frame.get("separation")
        phase = _current_phase(frame["time"], phases)
        is_peak = (frame["index"] == peak_idx)
        in_delivery_window = overlay_start <= frame["time"] <= overlay_end

        if in_delivery_window:
            annotated = render_frame_overlay(
                frame["frame_bgr"],
                frame.get("landmarks"),
                sep,
                phase,
                is_peak=is_peak,
                peak_separation=peak_sep,
            )
            annotated = render_legend(annotated)
        else:
            # Outside delivery window: raw frame, no overlays
            annotated = frame["frame_bgr"]

        canvas = _fit_frame_to_canvas(annotated, canvas_w, canvas_h)

        # Each source frame → slow_factor output frames (0.25x speed)
        rendered_frames.extend([canvas] * slow_factor)

        # 3. Freeze at peak — extra hold with the overlay frame
        if is_peak:
            freeze_card = make_freeze_card(frame["frame_bgr"], peak_sep, canvas_w, canvas_h)
            rendered_frames.extend([freeze_card] * int(output_fps * 2.5))  # 2.5s hold

    # 5. Verdict card
    verdict_frame_bgr = peak_frame["frame_bgr"] if peak_frame else frames[len(frames) // 2]["frame_bgr"]
    verdict = make_verdict_card(
        verdict_frame_bgr,
        peak_sep or 0,
        insight_lines,
        canvas_w,
        canvas_h,
    )
    rendered_frames.extend([verdict] * int(output_fps * 3))  # 3s hold

    # Encode to MP4
    raw_path = output_path.replace(".mp4", "_raw.mp4")
    writer = cv2.VideoWriter(
        raw_path,
        cv2.VideoWriter_fourcc(*"mp4v"),
        output_fps,
        (canvas_w, canvas_h),
    )
    for img in rendered_frames:
        bgr = cv2.cvtColor(np.array(img), cv2.COLOR_RGB2BGR)
        writer.write(bgr)
    writer.release()

    # Re-encode with FFmpeg for YouTube compatibility (H.264 + AAC)
    _reencode_for_youtube(raw_path, output_path)

    # Clean up raw
    Path(raw_path).unlink(missing_ok=True)

    return output_path


def _current_phase(time_s: float, phases: dict) -> str:
    if time_s < phases.get("back_foot_contact", 0):
        return "approach"
    elif time_s < phases.get("front_foot_contact", 0):
        return "back foot contact"
    elif time_s < phases.get("release", 0):
        return "front foot contact"
    elif time_s < phases.get("follow_through", 999):
        return "release"
    else:
        return "follow through"


def _reencode_for_youtube(input_path: str, output_path: str):
    """Re-encode to H.264 + AAC for YouTube/Instagram upload readiness."""
    cmd = [
        "ffmpeg", "-y",
        "-i", input_path,
        "-f", "lavfi", "-i", "anullsrc=r=44100:cl=stereo",
        "-map", "0:v:0", "-map", "1:a:0",
        "-c:v", "libx264",
        "-preset", "medium",
        "-crf", "17",
        "-pix_fmt", "yuv420p",
        "-movflags", "+faststart",
        "-shortest",
        "-c:a", "aac", "-b:a", "128k",
        output_path,
    ]
    subprocess.run(cmd, check=True, capture_output=True)
