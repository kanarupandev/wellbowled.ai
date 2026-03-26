from __future__ import annotations

import argparse
import json
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

from render_bowling_analysis import (
    analyze_pose,
    bgr_to_rgba,
    encode_video,
    load_font,
    nearest_frame,
    rounded_panel,
    save_storyboard,
    select_phase_frame,
    write_segment,
    wrap_text,
)
from render_bowler_variants import choose_brace_leg, draw_pose_canvas, overlay_brace_focus
from extract_bowler_frame import PRIMARY_JOINTS


def focus_box(points, fallback: dict | None = None) -> dict:
    if not points:
        return fallback or {"x": 0.08, "y": 0.18, "w": 0.74, "h": 0.72}

    xs = [points[idx][0] for idx in PRIMARY_JOINTS if points[idx][2] > 0.25]
    ys = [points[idx][1] for idx in PRIMARY_JOINTS if points[idx][2] > 0.25]
    if len(xs) < 5 or len(ys) < 5:
        return fallback or {"x": 0.08, "y": 0.18, "w": 0.74, "h": 0.72}

    x1 = max(0.0, min(xs) - 0.16)
    x2 = min(1.0, max(xs) + 0.16)
    y1 = max(0.0, min(ys) - 0.14)
    y2 = min(1.0, max(ys) + 0.10)

    aspect = 480.0 / 848.0
    width = x2 - x1
    height = y2 - y1
    if width / max(height, 1e-6) < aspect:
        target_w = height * aspect
        grow = (target_w - width) / 2
        x1 -= grow
        x2 += grow
    else:
        target_h = width / aspect
        grow = (target_h - height) / 2
        y1 -= grow + 0.03
        y2 += grow - 0.03

    x1 = max(0.0, x1)
    y1 = max(0.0, y1)
    x2 = min(1.0, x2)
    y2 = min(1.0, y2)

    width = x2 - x1
    height = y2 - y1
    if width < 0.48:
        cx = (x1 + x2) / 2
        half = 0.24
        x1 = max(0.0, cx - half)
        x2 = min(1.0, cx + half)
    if height < 0.64:
        cy = (y1 + y2) / 2 - 0.03
        half = 0.32
        y1 = max(0.0, cy - half)
        y2 = min(1.0, cy + half)

    return {"x": x1, "y": y1, "w": x2 - x1, "h": y2 - y1}


def smooth_box(prev_box: dict | None, curr_box: dict, alpha: float = 0.72) -> dict:
    if prev_box is None:
        return curr_box
    return {
        key: prev_box[key] * alpha + curr_box[key] * (1.0 - alpha)
        for key in ("x", "y", "w", "h")
    }


def apply_focus(frame: np.ndarray, box: dict) -> Image.Image:
    image = bgr_to_rgba(frame)
    blurred = image.filter(ImageFilter.GaussianBlur(radius=10))
    dark_bg = Image.alpha_composite(blurred, Image.new("RGBA", image.size, (6, 10, 15, 150)))

    width, height = image.size
    x = box["x"] * width
    y = box["y"] * height
    w = box["w"] * width
    h = box["h"] * height

    mask = Image.new("L", image.size, 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle((x, y, x + w, y + h), radius=44, fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(radius=34))
    focused = Image.composite(image, dark_bg, mask)

    glow = Image.new("RGBA", image.size, (0, 0, 0, 0))
    draw_glow = ImageDraw.Draw(glow)
    draw_glow.rounded_rectangle((x, y, x + w, y + h), radius=44, outline=(75, 224, 255, 92), width=4)
    return Image.alpha_composite(focused, glow)


def overlay_live_brace_frame(base_img: Image.Image, frame_entry: dict, title: str, note: str, style: dict) -> Image.Image:
    img = base_img.copy().convert("RGBA")
    width, height = img.size
    overlay = Image.new("RGBA", img.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)

    bg = tuple(style["background"])
    accent = tuple(style["accent"])
    accent_secondary = tuple(style["accent_secondary"])

    chip_font = load_font(20, bold=True)
    title_font = load_font(30, bold=True)
    body_font = load_font(20, bold=False)
    phase_font = load_font(20, bold=True)

    rounded_panel(draw, (20, 18, width - 20, 126), fill=(*bg, 182), outline=(*accent, 96), width=2, radius=26)
    draw.text((36, 30), "PACE BOWLING ANALYSIS", font=chip_font, fill=(*accent_secondary, 255))
    for idx, line in enumerate(wrap_text(draw, title, title_font, width - 72)[:2]):
        draw.text((36, 56 + idx * 34), line, font=title_font, fill=(246, 248, 252, 255))
    for idx, line in enumerate(wrap_text(draw, note, body_font, width - 72)[:2]):
        draw.text((36, 92 + idx * 22), line, font=body_font, fill=(212, 220, 230, 255))

    rounded_panel(draw, (28, height - 82, 160, height - 28), fill=(*bg, 210), radius=18)
    draw.text((44, height - 64), f"{frame_entry['time']:.2f}s", font=phase_font, fill=(248, 250, 252, 255))

    return Image.alpha_composite(img, overlay)


def _callout(draw: ImageDraw.ImageDraw, anchor: tuple[float, float], text: str, dx: int, dy: int, font):
    x, y = anchor
    text_box = draw.textbbox((0, 0), text, font=font)
    box_w = max(124, text_box[2] - text_box[0] + 26)
    box_h = 32
    left = max(14, min(int(x + dx), int(draw.im.size[0] - box_w - 14)))
    top = max(14, min(int(y + dy), int(draw.im.size[1] - box_h - 14)))
    rounded_panel(draw, (left, top, left + box_w, top + box_h), fill=(10, 14, 20, 228), radius=16)
    draw.text((left + 12, top + 8), text, font=font, fill=(245, 247, 250, 255))


def overlay_pose_freeze(points, size: tuple[int, int], style: dict, headline: str, summary: str) -> Image.Image:
    base = draw_pose_canvas(size, points)
    img = Image.fromarray(cv2.cvtColor(base, cv2.COLOR_BGR2RGB)).convert("RGBA")
    width, height = img.size
    overlay = Image.new("RGBA", img.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)

    accent = tuple(style["accent"])
    accent_secondary = tuple(style["accent_secondary"])
    accent_tertiary = tuple(style.get("accent_tertiary", [142, 242, 92]))
    bg = tuple(style["background"])

    rounded_panel(draw, (20, 20, width - 20, 186), fill=(*bg, 194), outline=(*accent, 108), width=2, radius=30)
    rounded_panel(draw, (20, height - 258, width - 20, height - 24), fill=(*bg, 216), radius=30)

    chip_font = load_font(22, bold=True)
    title_font = load_font(36, bold=True)
    body_font = load_font(26, bold=False)
    small_font = load_font(20, bold=False)
    label_font = load_font(16, bold=True)

    draw.text((38, 34), "POSE-ONLY FREEZE", font=chip_font, fill=(*accent_secondary, 255))
    for idx, line in enumerate(wrap_text(draw, headline, title_font, width - 76)[:2]):
        draw.text((38, 64 + idx * 38), line, font=title_font, fill=(248, 250, 252, 255))
    for idx, line in enumerate(wrap_text(draw, "Front-leg brace at release. Clean look, no background noise.", small_font, width - 76)[:2]):
        draw.text((38, 64 + 38 * 2 + idx * 24), line, font=small_font, fill=(208, 216, 226, 255))

    brace = choose_brace_leg(points)
    if brace:
        hip_idx, knee_idx, ankle_idx = brace["brace_triplet"]
        trail_ankle_idx = brace["trail_triplet"][2]
        hip = (points[hip_idx][0] * width, points[hip_idx][1] * height)
        knee = (points[knee_idx][0] * width, points[knee_idx][1] * height)
        ankle = (points[ankle_idx][0] * width, points[ankle_idx][1] * height)
        trail = (points[trail_ankle_idx][0] * width, points[trail_ankle_idx][1] * height)

        draw.line((hip[0], hip[1], knee[0], knee[1]), fill=(*accent_tertiary, 255), width=8)
        draw.line((knee[0], knee[1], ankle[0], ankle[1]), fill=(*accent_tertiary, 255), width=8)
        draw.ellipse((knee[0] - 8, knee[1] - 8, knee[0] + 8, knee[1] + 8), fill=(*accent_tertiary, 255))
        draw.ellipse((ankle[0] - 8, ankle[1] - 8, ankle[0] + 8, ankle[1] + 8), fill=(*accent, 255))
        draw.ellipse((trail[0] - 8, trail[1] - 8, trail[0] + 8, trail[1] + 8), fill=(*accent_secondary, 255))

        _callout(draw, knee, "brace knee", 18, -16, label_font)
        _callout(draw, ankle, "front ankle", 18, 10, label_font)
        _callout(draw, trail, "trail ankle", -138, -4, label_font)

        rounded_panel(draw, (30, height - 116, 186, height - 34), fill=(*bg, 228), outline=(*accent_tertiary, 255), width=2, radius=20)
        draw.text((44, height - 102), "BRACE", font=chip_font, fill=(210, 218, 228, 255))
        draw.text((44, height - 70), f"{brace['brace_knee_angle']}deg", font=load_font(28, bold=True), fill=(248, 250, 252, 255))

    for idx, line in enumerate(wrap_text(draw, summary, body_font, width - 84)):
        draw.text((40, height - 228 + idx * 30), line, font=body_font, fill=(248, 250, 252, 255))
    draw.text((40, height - 116), "Tracked pose on device. Final framing shaped for upload.", font=small_font, fill=(176, 186, 198, 255))

    return Image.alpha_composite(img, overlay)


def render_upload_clip(config_path: str):
    with open(config_path) as f:
        config = json.load(f)

    output_dir = Path(config["output_dir"])
    output_dir.mkdir(parents=True, exist_ok=True)

    segment_path = output_dir / "upload_segment.mp4"
    write_segment(config["input_video"], config["segment"]["start"], config["segment"]["end"], str(segment_path))

    frames, fps, size = analyze_pose(
        str(segment_path),
        config["arm_hint"],
        config.get("pose_crop"),
        config.get("flash_analysis"),
    )
    width, height = size
    hints = config["phase_hints"]
    release_frame = nearest_frame(frames, hints["release"])
    freeze_frame = select_phase_frame(frames, hints.get("freeze", hints["release"]), window=hints.get("freeze_window", 0.12), require_pose=True)

    style = config["style"]
    title = "Front-Leg Brace"
    subtitle = "Knee stacks over the front ankle through release."
    summary = "The knee stays tall over the front foot, then the trail side whips across to finish the action."

    rendered = []
    storyboard_cards = []

    prev_box = None
    release_preview = None
    for frame in frames:
        curr_box = focus_box(frame["points"], fallback=prev_box)
        prev_box = smooth_box(prev_box, curr_box)
        focused = apply_focus(frame["frame"], prev_box)
        note = subtitle if abs(frame["time"] - hints["release"]) <= 0.18 else "Watch the front side load into release."
        live = overlay_live_brace_frame(focused, frame, title, note, style)
        live_bgr = cv2.cvtColor(np.array(live.convert("RGB")), cv2.COLOR_RGB2BGR)
        live_bgr = overlay_brace_focus(live_bgr, frame["points"], frame["time"], hints)
        live = Image.fromarray(cv2.cvtColor(live_bgr, cv2.COLOR_BGR2RGB)).convert("RGBA")
        rendered.append(live)
        if release_preview is None and frame["time"] >= hints["release"]:
            release_preview = live

    freeze = overlay_pose_freeze(freeze_frame["points"], (width, height), style, "Front-Leg Brace", summary)
    storyboard_cards.extend([
        ("Release", release_preview if release_preview is not None else rendered[min(len(rendered) - 1, 0)]),
        ("Freeze", freeze),
    ])

    output_video = output_dir / "upload_ready_brace_overlay.mp4"
    output_storyboard = output_dir / "upload_ready_brace_storyboard.jpg"
    encode_video(rendered, str(output_video), max(1.0, fps / max(1, int(config.get("render", {}).get("slow_factor", 4)))))
    save_storyboard(storyboard_cards, str(output_storyboard))

    manifest = {
        "video": str(output_video),
        "storyboard": str(output_storyboard),
        "release_time": release_frame["time"],
        "freeze_time": freeze_frame["time"],
    }
    with (output_dir / "upload_ready_brace_manifest.json").open("w") as f:
        json.dump(manifest, f, indent=2)
    print(json.dumps(manifest, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Render a cleaner upload-ready brace breakdown clip.")
    parser.add_argument("config", help="Path to the story config")
    args = parser.parse_args()
    render_upload_clip(args.config)
