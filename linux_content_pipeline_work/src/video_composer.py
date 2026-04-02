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


# ---------------------------------------------------------------------------
# Frame Battle composition — for comparison-format content
# ---------------------------------------------------------------------------

def _apply_colour_grade(img: Image.Image) -> Image.Image:
    """Desaturate slightly, lift blacks, add subtle vignette. Unifies clips."""
    from PIL import ImageEnhance

    # Slight desaturation
    img = ImageEnhance.Color(img).enhance(0.75)
    # Lift blacks slightly — blend with dark grey
    lift = Image.new("RGB", img.size, (20, 22, 28))
    img = Image.blend(img, lift, 0.08)
    # Subtle vignette
    w, h = img.size
    vignette = Image.new("L", (w, h), 255)
    draw_v = ImageDraw.Draw(vignette)
    cx, cy = w // 2, h // 2
    max_r = int((cx**2 + cy**2) ** 0.5)
    for r in range(max_r, max_r - max_r // 3, -1):
        alpha = int(255 * (1.0 - (max_r - r) / (max_r // 3) * 0.35))
        draw_v.ellipse((cx - r, cy - r, cx + r, cy + r), fill=alpha)
    img = Image.composite(img, Image.new("RGB", img.size, BG_DARK), vignette)
    return img


def _apply_ken_burns(img: Image.Image, progress: float, zoom_range: float = 0.03) -> Image.Image:
    """Subtle zoom drift on a still frame. progress 0.0-1.0 over the hold."""
    w, h = img.size
    scale = 1.0 + zoom_range * progress
    new_w, new_h = int(w * scale), int(h * scale)
    zoomed = img.resize((new_w, new_h), Image.Resampling.LANCZOS)
    left = (new_w - w) // 2
    top = (new_h - h) // 2
    return zoomed.crop((left, top, left + w, top + h))


def _render_text_on_canvas(
    canvas: Image.Image,
    lines: list[str],
    y_start: int | None = None,
    font_size: int = 36,
    line_spacing: int = 16,
    center: bool = True,
) -> Image.Image:
    """Render text lines on canvas. Clean, no effects."""
    canvas = canvas.copy()
    draw = ImageDraw.Draw(canvas)
    font = _load_font(font_size, bold=False)
    w = canvas.size[0]

    if y_start is None:
        total_h = len(lines) * (font_size + line_spacing)
        y_start = canvas.size[1] - total_h - 120  # lower third

    y = y_start
    for line in lines:
        tw = draw.textlength(line, font=font)
        x = (w - tw) // 2 if center else 60
        draw.text((x, y), line, font=font, fill=WHITE)
        y += font_size + line_spacing
    return canvas


def _make_hook_card(
    frame_bgr: np.ndarray,
    text: str,
    canvas_w: int,
    canvas_h: int,
) -> Image.Image:
    """Beat 1: freeze frame + vignette + zoom + text."""
    canvas = _fit_frame_to_canvas(frame_bgr, canvas_w, canvas_h)
    canvas = _apply_colour_grade(canvas)
    # Heavier vignette for drama
    dark = Image.new("RGB", (canvas_w, canvas_h), BG_DARK)
    canvas = Image.blend(canvas, dark, 0.2)
    return _render_text_on_canvas(canvas, [text], font_size=42)


def _make_dissolve_sequence(
    frames_bgr: list[np.ndarray],
    text_per_frame: list[str],
    canvas_w: int,
    canvas_h: int,
    hold_frames: int = 60,
    dissolve_frames: int = 10,
) -> list[Image.Image]:
    """Beat 2: N frames dissolving in order with staggered text."""
    output = []
    canvases = []
    for frame_bgr in frames_bgr:
        c = _fit_frame_to_canvas(frame_bgr, canvas_w, canvas_h)
        c = _apply_colour_grade(c)
        canvases.append(c)

    for i, canvas in enumerate(canvases):
        text_lines = text_per_frame[:i + 1]  # stagger: accumulate lines
        with_text = _render_text_on_canvas(canvas, text_lines, font_size=34)

        # Ken Burns drift during hold
        for f in range(hold_frames):
            progress = f / max(1, hold_frames - 1)
            drifted = _apply_ken_burns(with_text, progress)
            output.append(drifted)

        # Dissolve to next (if not last)
        if i < len(canvases) - 1:
            next_text = text_per_frame[:i + 2]
            next_with_text = _render_text_on_canvas(canvases[i + 1], next_text, font_size=34)
            for d in range(dissolve_frames):
                alpha = d / max(1, dissolve_frames - 1)
                blended = Image.blend(with_text, next_with_text, alpha)
                output.append(blended)

    return output


def _make_side_by_side_card(
    left_bgr: np.ndarray,
    right_bgr: np.ndarray,
    canvas_w: int,
    canvas_h: int,
) -> Image.Image:
    """Two frames side by side with thin divider."""
    half_w = canvas_w // 2

    def fit_half(frame_bgr: np.ndarray) -> Image.Image:
        rgb = cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2RGB)
        img = Image.fromarray(rgb)
        fw, fh = img.size
        scale = half_w / fw
        new_h = int(fh * scale)
        img = img.resize((half_w, new_h), Image.Resampling.LANCZOS)
        # Center vertically on dark bg
        panel = Image.new("RGB", (half_w, canvas_h), BG_DARK)
        y_off = (canvas_h - new_h) // 2
        panel.paste(img, (0, y_off))
        return panel

    left = fit_half(left_bgr)
    right = fit_half(right_bgr)

    left = _apply_colour_grade(left)
    right = _apply_colour_grade(right)

    canvas = _make_canvas(canvas_w, canvas_h)
    canvas.paste(left, (0, 0))
    canvas.paste(right, (half_w, 0))

    # Thin divider
    draw = ImageDraw.Draw(canvas)
    draw.line(
        [(half_w, 0), (half_w, canvas_h)],
        fill=(255, 255, 255, 128),
        width=2,
    )
    return canvas


def _make_text_card(
    lines: list[str],
    canvas_w: int,
    canvas_h: int,
    font_size: int = 38,
    brand: str | None = None,
) -> Image.Image:
    """Text on dark background — for payoff and close."""
    canvas = _make_canvas(canvas_w, canvas_h)
    total_h = len(lines) * (font_size + 16)
    y_start = (canvas_h - total_h) // 2
    canvas = _render_text_on_canvas(canvas, lines, y_start=y_start, font_size=font_size)

    if brand:
        draw = ImageDraw.Draw(canvas)
        font_brand = _load_font(20, bold=False)
        bw = draw.textlength(brand, font=font_brand)
        draw.text(
            ((canvas_w - bw) // 2, canvas_h - 60),
            brand, font=font_brand, fill=(100, 110, 120),
        )
    return canvas


def _apply_pulse_timing(
    base_frames: list[Image.Image],
    landmarks_left: list[tuple[float, float, float]] | None,
    landmarks_right: list[tuple[float, float, float]] | None,
    canvas_w: int,
    canvas_h: int,
    bowling_side_left: str = "left",
    bowling_side_right: str = "right",
    pulse_start_frac: float = 0.3,
    pulse_duration_frac: float = 0.25,
) -> list[Image.Image]:
    """Apply timed pulse/glow on side-by-side frames.

    Owns the TIMING: when the glow starts, how many frames it spans,
    fade-in/out curve. Calls render_pulse_glow from the renderer for
    the visual per-frame.
    """
    from .overlay_renderer import render_pulse_glow

    total = len(base_frames)
    pulse_start = int(total * pulse_start_frac)
    pulse_len = int(total * pulse_duration_frac)
    pulse_end = pulse_start + pulse_len
    half_w = canvas_w // 2

    output = []
    for i, frame_img in enumerate(base_frames):
        if pulse_start <= i < pulse_end:
            # Fade in first half, fade out second half
            local_t = (i - pulse_start) / max(1, pulse_len - 1)
            if local_t < 0.5:
                opacity = local_t * 2.0 * 0.5  # max 0.5
            else:
                opacity = (1.0 - local_t) * 2.0 * 0.5

            frame_bgr = cv2.cvtColor(np.array(frame_img), cv2.COLOR_RGB2BGR)

            # Split left/right halves, apply glow separately
            left_half = frame_bgr[:, :half_w]
            right_half = frame_bgr[:, half_w:]

            if landmarks_left is not None:
                left_half = render_pulse_glow(
                    left_half, landmarks_left, opacity, bowling_side_left,
                )
            if landmarks_right is not None:
                right_half = render_pulse_glow(
                    right_half, landmarks_right, opacity, bowling_side_right,
                )

            combined = np.hstack([left_half, right_half])
            frame_img = Image.fromarray(cv2.cvtColor(combined, cv2.COLOR_BGR2RGB))

        output.append(frame_img)
    return output


def compose_frame_battle(
    bumrah_frames: dict,
    steyn_frames: dict,
    output_path: str,
) -> str:
    """Compose a Frame Battle video per the approved script.

    Args:
        bumrah_frames: dict with keys:
            - "hook": BGR frame for Beat 1
            - "sequence": list of BGR frames for Beat 2 [gather, FFC, release]
            - "sequence_overlaid": list of BGR frames for Beat 2 with overlays
            - "hero": BGR frame for side-by-side (with overlay)
            - "hero_landmarks": landmarks for the hero frame
            - "hero_bowling_side": "left" or "right"
            - "realtime": list of BGR frames at original speed
        steyn_frames: dict with same structure
        output_path: output MP4 path

    Returns path to final MP4.
    """
    canvas_w = 1080
    canvas_h = 1920
    output_fps = 30.0

    rendered: list[Image.Image] = []

    # --- Beat 1: Hook (0:00-0:03) = ~90 frames ---
    hook_card = _make_hook_card(
        bumrah_frames["hook"], "Why does this work?", canvas_w, canvas_h,
    )
    for f in range(int(output_fps * 3)):
        progress = f / (output_fps * 3)
        rendered.append(_apply_ken_burns(hook_card, progress, zoom_range=0.02))

    # --- Beat 2: Show the unusual (0:03-0:10) = ~210 frames ---
    # Use overlaid frames for last two, raw for first
    seq_bgr = []
    seq_bgr.append(bumrah_frames["sequence"][0])  # gather — no overlay
    for frame in bumrah_frames["sequence_overlaid"][1:]:  # FFC + release with overlay
        seq_bgr.append(frame)

    beat2 = _make_dissolve_sequence(
        seq_bgr,
        ["Short run-up.", "Little wind-up.", "Still explosive."],
        canvas_w, canvas_h,
        hold_frames=int(output_fps * 2),     # 2s per frame
        dissolve_frames=int(output_fps * 0.4),  # 0.4s dissolve
    )
    rendered.extend(beat2)

    # --- Beat 3: The contrast (0:10-0:22) = ~360 frames ---
    # Steyn solo: 2 frames, ~2s each
    steyn_solo = _make_dissolve_sequence(
        [steyn_frames["sequence"][0], steyn_frames["sequence"][-1]],
        ["", ""],
        canvas_w, canvas_h,
        hold_frames=int(output_fps * 2),
        dissolve_frames=int(output_fps * 0.3),
    )
    rendered.extend(steyn_solo)

    # Side-by-side hero card: hold ~5s with text
    sbs_card = _make_side_by_side_card(
        bumrah_frames["hero"], steyn_frames["hero"], canvas_w, canvas_h,
    )
    sbs_with_text = _render_text_on_canvas(
        sbs_card,
        ["Same job.", "Completely different engines."],
        font_size=36,
    )
    sbs_hold = int(output_fps * 5)
    sbs_frames = [sbs_with_text] * sbs_hold

    # Apply pulse/glow timing
    sbs_frames = _apply_pulse_timing(
        sbs_frames,
        bumrah_frames.get("hero_landmarks"),
        steyn_frames.get("hero_landmarks"),
        canvas_w, canvas_h,
        bumrah_frames.get("hero_bowling_side", "left"),
        steyn_frames.get("hero_bowling_side", "right"),
    )
    rendered.extend(sbs_frames)

    # --- Beat 4: The reframe (0:22-0:33) = ~330 frames ---
    # Real-time replay: ~1.5s
    for frame_bgr in bumrah_frames.get("realtime", [])[:int(output_fps * 1.5)]:
        c = _fit_frame_to_canvas(frame_bgr, canvas_w, canvas_h)
        c = _apply_colour_grade(c)
        rendered.append(c)

    # Text card hold: ~9.5s
    payoff = _make_text_card(
        ["Fast bowling is not one shape.", "", "It is force, timing,", "and repeatability."],
        canvas_w, canvas_h,
        font_size=38,
    )
    rendered.extend([payoff] * int(output_fps * 9.5))

    # --- Beat 5: Close (0:33-0:38) = ~150 frames ---
    close = _make_text_card(
        ["Different is not broken."],
        canvas_w, canvas_h,
        font_size=42,
        brand="wellBowled.ai",
    )
    rendered.extend([close] * int(output_fps * 5))

    # --- Encode ---
    raw_path = output_path.replace(".mp4", "_raw.mp4")
    writer = cv2.VideoWriter(
        raw_path,
        cv2.VideoWriter_fourcc(*"mp4v"),
        output_fps,
        (canvas_w, canvas_h),
    )
    for img in rendered:
        bgr = cv2.cvtColor(np.array(img), cv2.COLOR_RGB2BGR)
        writer.write(bgr)
    writer.release()

    _reencode_for_youtube(raw_path, output_path)
    Path(raw_path).unlink(missing_ok=True)

    return output_path
