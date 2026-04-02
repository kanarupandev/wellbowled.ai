"""Video composer: assemble cold open, slo-mo, freeze, verdict, end card.

All text via Pillow with Liberation Sans. FFmpeg re-encode for YouTube.
"""
from __future__ import annotations

import subprocess
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
BG_DARK = (10, 14, 20)       # #0A0E14
BG_BRAND = (13, 17, 23)      # #0D1117
WHITE = (255, 255, 255)
LIGHT_GREY = (180, 190, 200)  # #B4BEC8
ACCENT_RED = (255, 80, 64)    # #FF5040
BRAND_TEAL = (0, 109, 119)    # #006D77
HIP_COLOR = (255, 105, 180)
SHOULDER_COLOR = (0, 206, 209)

OUT_W, OUT_H = 1080, 1920
OUTPUT_FPS = 30.0
SLOW_FACTOR = 4  # 0.25x


# ---------------------------------------------------------------------------
# Font helper (Linux paths)
# ---------------------------------------------------------------------------
_font_cache: dict = {}


def _load_font(size: int, bold: bool = False):
    key = (size, bold)
    if key in _font_cache:
        return _font_cache[key]
    candidates = [
        "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf" if bold
        else "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf" if bold
        else "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    ]
    for c in candidates:
        if Path(c).exists():
            try:
                font = ImageFont.truetype(c, size=size)
                _font_cache[key] = font
                return font
            except OSError:
                pass
    font = ImageFont.load_default()
    _font_cache[key] = font
    return font


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


# ---------------------------------------------------------------------------
# Canvas helpers
# ---------------------------------------------------------------------------
def _make_canvas() -> Image.Image:
    return Image.new("RGB", (OUT_W, OUT_H), BG_DARK)


def fit_frame_to_canvas(frame_bgr: np.ndarray) -> tuple[Image.Image, int]:
    """Fit a BGR frame into 9:16 canvas. Returns (canvas, y_offset)."""
    frame_rgb = cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2RGB)
    img = Image.fromarray(frame_rgb)
    fw, fh = img.size

    scale = OUT_W / fw
    new_w = OUT_W
    new_h = int(fh * scale)
    img = img.resize((new_w, new_h), Image.Resampling.LANCZOS)

    canvas = _make_canvas()
    y_offset = (OUT_H - new_h) // 2
    canvas.paste(img, (0, y_offset))
    return canvas, y_offset


# ---------------------------------------------------------------------------
# Card generators
# ---------------------------------------------------------------------------
def _make_cold_open_frame(frame_bgr: np.ndarray) -> Image.Image:
    """Cold open: raw frame with 'WATCH THE HIPS' pill at bottom."""
    canvas, y_off = fit_frame_to_canvas(frame_bgr)
    draw = ImageDraw.Draw(canvas)
    font = _load_font(24, bold=True)

    label = "WATCH THE HIPS"
    tw = draw.textlength(label, font=font)
    pw = int(tw + 32)
    ph = 40
    px = OUT_W // 2 - pw // 2
    py = OUT_H - 100
    draw.rounded_rectangle(
        (px, py, px + pw, py + ph), radius=14, fill=(10, 14, 20, 200),
    )
    draw.text((px + 16, py + 10), label, font=font, fill=WHITE)
    return canvas


def make_freeze_card(
    frame_bgr: np.ndarray,
    peak_separation: float,
) -> Image.Image:
    """Freeze frame at peak: 65% dark overlay, PEAK X-FACTOR + big angle."""
    canvas, _ = fit_frame_to_canvas(frame_bgr)
    overlay = Image.new("RGB", (OUT_W, OUT_H), BG_DARK)
    canvas = Image.blend(canvas, overlay, 0.65)
    draw = ImageDraw.Draw(canvas)

    font_huge = _load_font(72, bold=True)
    font_label = _load_font(28, bold=True)
    font_sub = _load_font(22, bold=False)

    cx = OUT_W // 2
    cy = OUT_H // 2 - 60

    # "PEAK X-FACTOR" label
    peak_label = "PEAK X-FACTOR"
    ptw = draw.textlength(peak_label, font=font_label)
    draw.text((cx - ptw // 2, cy - 50), peak_label, font=font_label, fill=WHITE)

    # Big angle number
    angle_text = f"{peak_separation:.0f}\u00b0"
    tw = draw.textlength(angle_text, font=font_huge)
    draw.text((cx - tw // 2, cy), angle_text, font=font_huge, fill=ACCENT_RED)

    # Sub text
    sub = "hip-shoulder separation"
    stw = draw.textlength(sub, font=font_sub)
    draw.text((cx - stw // 2, cy + 80), sub, font=font_sub, fill=LIGHT_GREY)

    # Legend at bottom
    ly = OUT_H - 80
    font_leg = _load_font(18, bold=False)
    draw.ellipse((cx - 110, ly, cx - 96, ly + 14), fill=HIP_COLOR)
    draw.text((cx - 88, ly - 1), "hips", font=font_leg, fill=(200, 200, 200))
    draw.ellipse((cx + 20, ly, cx + 34, ly + 14), fill=SHOULDER_COLOR)
    draw.text((cx + 42, ly - 1), "shoulders", font=font_leg, fill=(200, 200, 200))

    return canvas


def make_verdict_card(
    frame_bgr: np.ndarray,
    peak_separation: float,
    insight_lines: list[str],
) -> Image.Image:
    """Verdict card: blurred bg, rating, comparison scale bar, coaching insight."""
    frame_rgb = cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2RGB)
    bg = Image.fromarray(frame_rgb).resize((OUT_W, OUT_H), Image.Resampling.LANCZOS)
    bg = bg.filter(ImageFilter.GaussianBlur(radius=6))
    overlay = Image.new("RGB", (OUT_W, OUT_H), BG_DARK)
    canvas = Image.blend(bg, overlay, 0.75)
    draw = ImageDraw.Draw(canvas)

    font_title = _load_font(36, bold=True)
    font_body = _load_font(20, bold=False)
    font_label = _load_font(16, bold=True)
    font_brand = _load_font(14, bold=False)
    font_ref = _load_font(14, bold=False)
    font_note = _load_font(16, bold=False)

    cx = OUT_W // 2
    # Vertically center the content block (approx 500px tall) in the canvas
    base_y = (OUT_H - 500) // 2

    # Title
    title = "X-FACTOR VERDICT"
    tw = draw.textlength(title, font=font_title)
    draw.text((cx - tw // 2, base_y), title, font=font_title, fill=ACCENT_RED)

    # Angle line
    angle_text = f"{peak_separation:.0f}\u00b0 peak separation"
    atw = draw.textlength(angle_text, font=font_body)
    draw.text((cx - atw // 2, base_y + 50), angle_text, font=font_body, fill=WHITE)

    # Rating
    if peak_separation >= 45:
        rating, rating_color = "ELITE", (100, 255, 100)
        rating_note = "World-class rotational mechanics"
    elif peak_separation >= 35:
        rating, rating_color = "VERY GOOD", (130, 230, 130)
        rating_note = "Strong rotational mechanics"
    elif peak_separation >= 28:
        rating, rating_color = "DEVELOPING", (255, 220, 80)
        rating_note = "Room to lead more with the hip"
    else:
        rating, rating_color = "WORK ON IT", (255, 140, 60)
        rating_note = "Focus on hip pre-rotation drills"

    rtw = draw.textlength(rating, font=font_title)
    draw.text((cx - rtw // 2, base_y + 90), rating, font=font_title, fill=rating_color)

    # --- Comparison scale bar ---
    bar_y = base_y + 150
    bar_x = 60
    bar_w = OUT_W - 120
    bar_h = 40
    draw.rounded_rectangle(
        (bar_x, bar_y, bar_x + bar_w, bar_y + bar_h),
        radius=8, fill=(30, 34, 44),
    )

    def angle_to_x(a: float) -> int:
        return bar_x + int((min(60, max(0, a)) / 60) * bar_w)

    # Reference markers: Untrained 12, Amateur 20, Good 30, Elite 42, Peak 50+
    markers = [
        ("Untrained", 12, (150, 150, 150)),
        ("Amateur", 20, (255, 140, 60)),
        ("Good", 30, (255, 220, 80)),
        ("Elite", 42, (100, 255, 100)),
        ("Peak", 50, (255, 80, 64)),
    ]
    for label, angle, color in markers:
        x = angle_to_x(angle)
        draw.line((x, bar_y + 4, x, bar_y + bar_h - 4), fill=color, width=2)
        lbl_text = f"{label} {angle}\u00b0"
        lw = draw.textlength(lbl_text, font=font_ref)
        draw.text((x - lw // 2, bar_y + bar_h + 4), lbl_text, font=font_ref, fill=color)

    # "You" marker
    you_x = angle_to_x(peak_separation)
    draw.line((you_x, bar_y + 2, you_x, bar_y + bar_h - 2), fill=WHITE, width=3)
    you_label = "You"
    yw = draw.textlength(you_label, font=font_label)
    draw.text((you_x - yw // 2, bar_y - 22), you_label, font=font_label, fill=WHITE)

    # Rating note
    nw = draw.textlength(rating_note, font=font_note)
    draw.text((cx - nw // 2, bar_y + bar_h + 30), rating_note, font=font_note, fill=LIGHT_GREY)

    # Coaching insight lines
    y = bar_y + bar_h + 60
    for line in insight_lines[:3]:
        wrapped = _wrap_text(draw, line, font_body, OUT_W - 80)
        for wl in wrapped:
            wlw = draw.textlength(wl, font=font_body)
            draw.text((cx - wlw // 2, y), wl, font=font_body, fill=(220, 225, 235))
            y += 28

    # Brand
    brand = "wellBowled.ai"
    bw = draw.textlength(brand, font=font_brand)
    draw.text((cx - bw // 2, OUT_H - 50), brand, font=font_brand, fill=(100, 110, 120))

    return canvas


def make_end_card() -> Image.Image:
    """End card: wellBowled.ai at 72px, tagline at 36px, 1s."""
    canvas = Image.new("RGB", (OUT_W, OUT_H), BG_BRAND)
    draw = ImageDraw.Draw(canvas)

    font_brand = _load_font(72, bold=True)
    font_tag = _load_font(36, bold=False)

    cx = OUT_W // 2

    text = "wellBowled.ai"
    tw = draw.textlength(text, font=font_brand)
    draw.text((cx - tw // 2, OUT_H // 2 - 50), text, font=font_brand, fill=BRAND_TEAL)

    tag = "Cricket biomechanics, visualized"
    ttw = draw.textlength(tag, font=font_tag)
    draw.text((cx - ttw // 2, OUT_H // 2 + 40), tag, font=font_tag, fill=WHITE)

    return canvas


# ---------------------------------------------------------------------------
# Phase labelling
# ---------------------------------------------------------------------------
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


# ---------------------------------------------------------------------------
# Main composition
# ---------------------------------------------------------------------------
def compose_video(
    frames: list[dict],
    peak_frame: dict | None,
    phases: dict,
    output_path: str,
    fps: float,
    insight_lines: list[str] | None = None,
) -> str:
    """Compose final YouTube-ready 9:16 video.

    Structure:
        1. Cold open: all frames at 1x (raw footage)
        2. 0.3s black transition
        3. Slo-mo: all frames at 0.25x with overlays during delivery window
        4. Freeze at peak: 2.5s hold, 65% dark, PEAK X-FACTOR + big angle
        5. Verdict card: 3s, blurred bg, rating + scale bar
        6. End card: 1s
    """
    from xfactor_pipeline.overlay_renderer import render_frame_overlay, render_legend

    if insight_lines is None:
        insight_lines = [
            "The gap between hips and shoulders generates pace.",
            "Bigger separation = more stored energy at release.",
            "Work on leading with the hip, letting the shoulder lag.",
        ]

    rendered_frames: list[Image.Image] = []
    peak_sep = peak_frame["separation"] if peak_frame else 0
    peak_idx = peak_frame["index"] if peak_frame else -1

    # Delivery window for overlay gating
    overlay_start = max(0, phases.get("back_foot_contact", 0) - 0.15)
    overlay_end = phases.get("follow_through", frames[-1]["time"] if frames else 1.0) + 0.2

    # -----------------------------------------------------------------------
    # 1. COLD OPEN -- all frames at 1x speed, raw footage (cap at ~2s)
    # -----------------------------------------------------------------------
    max_cold_open_frames = int(OUTPUT_FPS * 2.0)  # 2s max
    cold_open_count = min(len(frames), max_cold_open_frames)
    for frame in frames[:cold_open_count]:
        canvas = _make_cold_open_frame(frame["frame_bgr"])
        rendered_frames.append(canvas)

    # -----------------------------------------------------------------------
    # 2. TRANSITION -- 0.3s black
    # -----------------------------------------------------------------------
    black = _make_canvas()
    transition_count = int(OUTPUT_FPS * 0.3)
    rendered_frames.extend([black] * transition_count)

    # -----------------------------------------------------------------------
    # 3. SLO-MO REPLAY -- 0.25x with overlays during delivery window
    # -----------------------------------------------------------------------
    for frame in frames:
        sep = frame.get("separation")
        phase = _current_phase(frame["time"], phases)
        is_peak = (frame["index"] == peak_idx)
        in_delivery_window = overlay_start <= frame["time"] <= overlay_end

        if in_delivery_window:
            # Scale landmarks to canvas coordinates for overlay
            canvas, y_off = fit_frame_to_canvas(frame["frame_bgr"])
            canvas_bgr = cv2.cvtColor(np.array(canvas), cv2.COLOR_RGB2BGR)

            # Remap landmarks to canvas space
            fw = frame["frame_bgr"].shape[1]
            fh = frame["frame_bgr"].shape[0]
            scale = OUT_W / fw
            new_h = int(fh * scale)

            if frame.get("landmarks"):
                canvas_landmarks = []
                for lx, ly, lv in frame["landmarks"]:
                    cx_px = lx * fw * scale
                    cy_px = ly * fh * scale + y_off
                    canvas_landmarks.append((cx_px / OUT_W, cy_px / OUT_H, lv))
            else:
                canvas_landmarks = None

            annotated = render_frame_overlay(
                canvas_bgr, canvas_landmarks, sep, phase,
                canvas_w=OUT_W, canvas_h=OUT_H, y_offset=y_off,
            )
            annotated = render_legend(annotated)
            canvas = Image.fromarray(cv2.cvtColor(annotated, cv2.COLOR_BGR2RGB))
        else:
            canvas, _ = fit_frame_to_canvas(frame["frame_bgr"])

        # Each source frame -> SLOW_FACTOR output frames
        rendered_frames.extend([canvas] * SLOW_FACTOR)

        # ---------------------------------------------------------------
        # 4. FREEZE AT PEAK -- 2.5s hold with dramatic card
        # ---------------------------------------------------------------
        if is_peak and peak_sep is not None:
            freeze = make_freeze_card(frame["frame_bgr"], peak_sep)
            rendered_frames.extend([freeze] * int(OUTPUT_FPS * 2.5))

    # -----------------------------------------------------------------------
    # 5. VERDICT CARD -- 3s
    # -----------------------------------------------------------------------
    verdict_bgr = (
        peak_frame["frame_bgr"] if peak_frame
        else frames[len(frames) // 2]["frame_bgr"]
    )
    verdict = make_verdict_card(verdict_bgr, peak_sep or 0, insight_lines)
    rendered_frames.extend([verdict] * int(OUTPUT_FPS * 3))

    # -----------------------------------------------------------------------
    # 6. END CARD -- 1s
    # -----------------------------------------------------------------------
    end = make_end_card()
    rendered_frames.extend([end] * int(OUTPUT_FPS * 1))

    # -----------------------------------------------------------------------
    # Encode to raw MP4, then re-encode with FFmpeg
    # -----------------------------------------------------------------------
    raw_path = output_path.replace(".mp4", "_raw.mp4")
    writer = cv2.VideoWriter(
        raw_path,
        cv2.VideoWriter_fourcc(*"mp4v"),
        OUTPUT_FPS,
        (OUT_W, OUT_H),
    )
    for img in rendered_frames:
        bgr = cv2.cvtColor(np.array(img), cv2.COLOR_RGB2BGR)
        writer.write(bgr)
    writer.release()

    _reencode_for_youtube(raw_path, output_path)
    Path(raw_path).unlink(missing_ok=True)

    total_duration = len(rendered_frames) / OUTPUT_FPS
    print(f"       [compose] {len(rendered_frames)} frames, {total_duration:.1f}s")
    return output_path


def _reencode_for_youtube(input_path: str, output_path: str):
    """Re-encode: H.264, CRF 17, yuv420p, faststart, silent AAC."""
    cmd = [
        "ffmpeg", "-y",
        "-i", input_path,
        "-f", "lavfi", "-i", "anullsrc=r=44100:cl=stereo",
        "-map", "0:v:0", "-map", "1:a:0",
        "-c:v", "libx264",
        "-preset", "medium",
        "-crf", "15",
        "-pix_fmt", "yuv420p",
        "-movflags", "+faststart",
        "-shortest",
        "-c:a", "aac", "-b:a", "128k",
        output_path,
    ]
    subprocess.run(cmd, check=True, capture_output=True)
