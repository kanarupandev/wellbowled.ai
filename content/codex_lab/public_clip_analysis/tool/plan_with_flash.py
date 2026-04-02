from __future__ import annotations

import argparse
import base64
import json
import math
import os
from pathlib import Path
import urllib.error
import urllib.request

import cv2
from PIL import Image, ImageDraw, ImageFont

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parents[3]
DEFAULT_MODEL = "gemini-3-flash-preview"


def load_api_key() -> str | None:
    env_key = os.environ.get("GEMINI_API_KEY")
    if env_key:
        return env_key
    env_path = REPO_ROOT / ".env"
    if env_path.exists():
        for line in env_path.read_text().splitlines():
            if line.startswith("GEMINI_API_KEY="):
                return line.split("=", 1)[1].strip()
    return None


def load_font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    candidates = []
    if bold:
        candidates.extend([
            "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
            "/System/Library/Fonts/Supplemental/Helvetica.ttc",
        ])
    else:
        candidates.extend([
            "/System/Library/Fonts/Supplemental/Arial.ttf",
            "/System/Library/Fonts/Supplemental/Helvetica.ttc",
        ])
    for candidate in candidates:
        if os.path.exists(candidate):
            try:
                return ImageFont.truetype(candidate, size=size)
            except OSError:
                continue
    return ImageFont.load_default()


def extract_frames(video_path: str, start_s: float, end_s: float, samples: int) -> tuple[list[dict], tuple[int, int], float]:
    cap = cv2.VideoCapture(video_path)
    fps = cap.get(cv2.CAP_PROP_FPS)
    width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    frames = []
    if samples <= 1:
        sample_times = [start_s]
    else:
        duration = max(0.01, end_s - start_s)
        sample_times = [start_s + duration * i / (samples - 1) for i in range(samples)]
    for ts in sample_times:
        frame_idx = int(ts * fps)
        cap.set(cv2.CAP_PROP_POS_FRAMES, frame_idx)
        ok, frame = cap.read()
        if not ok:
            continue
        frames.append({
            "label": f"F{len(frames) + 1}",
            "time": round(ts, 3),
            "frame_index": frame_idx,
            "frame": frame,
        })
    cap.release()
    return frames, (width, height), fps


def make_contact_sheet(frames: list[dict], output_path: str, title: str, subtitle: str):
    if not frames:
        raise ValueError("No frames for contact sheet")
    cols = 2
    rows = math.ceil(len(frames) / cols)
    tile_w = 300
    tile_h = 184
    gutter = 20
    header_h = 120
    width = cols * tile_w + (cols + 1) * gutter
    height = header_h + rows * tile_h + (rows + 1) * gutter
    canvas = Image.new("RGB", (width, height), (10, 14, 20))
    draw = ImageDraw.Draw(canvas)
    title_font = load_font(34, bold=True)
    sub_font = load_font(20, bold=False)
    chip_font = load_font(20, bold=True)

    draw.text((gutter, 20), title, font=title_font, fill=(244, 247, 250))
    draw.text((gutter, 62), subtitle, font=sub_font, fill=(190, 198, 208))

    for idx, item in enumerate(frames):
        row = idx // cols
        col = idx % cols
        x = gutter + col * (tile_w + gutter)
        y = header_h + gutter + row * (tile_h + gutter)
        rgb = cv2.cvtColor(item["frame"], cv2.COLOR_BGR2RGB)
        tile = Image.fromarray(rgb).resize((tile_w, tile_h))
        canvas.paste(tile, (x, y))
        draw.rounded_rectangle((x + 12, y + 12, x + 156, y + 52), radius=14, fill=(10, 14, 20))
        draw.text((x + 22, y + 18), f"{item['label']}  {item['time']:.2f}s", font=chip_font, fill=(255, 255, 255))

    canvas.save(output_path, quality=82)


def image_to_b64(path: str) -> str:
    with open(path, "rb") as f:
        return base64.b64encode(f.read()).decode("utf-8")


def frame_prompt_block(frames: list[dict]) -> str:
    return "\n".join(
        f'- {frame["label"]}: timestamp={frame["time"]:.2f}s frame_index={frame["frame_index"]}'
        for frame in frames
    )


def call_flash(api_key: str, model: str, contact_sheet_b64: str, start_s: float, end_s: float, frames: list[dict]) -> dict:
    prompt = f"""
Plan a short cricket bowling analysis video from this timestamped nets storyboard ({start_s:.2f}s to {end_s:.2f}s).
Use the frame ids below when you reference specific moments:
{frame_prompt_block(frames)}

Return STRICT JSON only:
{{
  "clip_summary": {{
    "camera_angle": "string",
    "primary_subject_label": "bowler",
    "primary_subject_description": "string",
    "distractor_people_count_estimate": 0,
    "bowling_arm": "right|left|unknown",
    "confidence": 0.0
  }},
  "subject_strategy": {{
    "ignore_background_people": true,
    "selection_reason": "string",
    "global_bowler_crop": {{
      "x": 0.0,
      "y": 0.0,
      "w": 0.0,
      "h": 0.0
    }},
    "frame_crop_padding": 0.0
  }},
  "phase_hints": {{
    "load": 0.0,
    "release": 0.0,
    "freeze": 0.0,
    "finish": 0.0
  }},
  "phase_frames": {{
    "load_frame": "F1",
    "release_frame": "F2",
    "freeze_frame": "F3",
    "finish_frame": "F4"
  }},
  "frame_analysis": [
    {{
      "frame_id": "F1",
      "timestamp_s": 0.0,
      "phase": "setup|load|release|freeze|finish|post_release",
      "bowler_visible": true,
      "primary_subject_bbox": {{
        "x": 0.0,
        "y": 0.0,
        "w": 0.0,
        "h": 0.0
      }},
      "ignore_regions": [
        {{
          "label": "background person",
          "x": 0.0,
          "y": 0.0,
          "w": 0.0,
          "h": 0.0
        }}
      ],
      "body_parts_visible": ["head", "bowling_shoulder"],
      "body_part_points": {{
        "head": {{"x": 0.0, "y": 0.0}},
        "bowling_shoulder": {{"x": 0.0, "y": 0.0}},
        "non_bowling_shoulder": {{"x": 0.0, "y": 0.0}},
        "bowling_elbow": {{"x": 0.0, "y": 0.0}},
        "bowling_wrist": {{"x": 0.0, "y": 0.0}},
        "hip_center": {{"x": 0.0, "y": 0.0}},
        "front_knee": {{"x": 0.0, "y": 0.0}},
        "front_ankle": {{"x": 0.0, "y": 0.0}}
      }},
      "ball_visible": false,
      "ball_bbox": null,
      "confidence": 0.0
    }}
  ],
  "editorial": {{
    "title": "6 words max",
    "subtitle": "12 words max",
    "freeze_title": "6 words max",
    "callout_left": "5 words max",
    "callout_right": "5 words max",
    "fallback_insight": "24 words max",
    "fallback_takeaway": "16 words max",
    "fallback_release_note": "18 words max",
    "fallback_finish_note": "18 words max"
  }},
  "review_flags": {{
    "background_risk": "low|medium|high",
    "crop_risk": "low|medium|high",
    "pose_risk": "low|medium|high",
    "notes": ["string"]
  }}
}}

Rules:
- Times must be in seconds within the storyboard range.
- All boxes and points must be normalized to the full frame.
- Identify the bowler, not other people in the background.
- Use `ignore_regions` for any distracting people or objects that should not be annotated.
- Keep `frame_analysis` entries aligned to the provided frame ids only.
- Return null for body parts or boxes you cannot confidently infer.
- Focus only on visible mechanics.
- Professional coaching tone only.
"""

    payload = {
        "contents": [{
            "parts": [
                {"text": "Timestamped storyboard image:"},
                {"inlineData": {"mimeType": "image/jpeg", "data": contact_sheet_b64}},
                {"text": prompt},
            ]
        }],
        "generationConfig": {
            "temperature": 0.2,
            "responseMimeType": "application/json",
            "thinkingConfig": {"thinkingLevel": "MINIMAL"},
        },
    }

    url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={api_key}"
    req = urllib.request.Request(url, data=json.dumps(payload).encode("utf-8"), headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            response = json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"HTTP {exc.code}: {body}") from exc

    text = response["candidates"][0]["content"]["parts"][0]["text"]
    data = json.loads(text)
    return {"draft": data, "raw": response}


def merge_config(base_config: dict, draft: dict) -> dict:
    merged = json.loads(json.dumps(base_config))
    for key in ("phase_hints",):
        if key in draft and isinstance(draft[key], dict):
            merged.setdefault(key, {})
            merged[key].update(draft[key])
    pose_crop = None
    if isinstance(draft.get("pose_crop"), dict):
        pose_crop = draft["pose_crop"]
    elif isinstance(draft.get("subject_strategy"), dict) and isinstance(draft["subject_strategy"].get("global_bowler_crop"), dict):
        pose_crop = draft["subject_strategy"]["global_bowler_crop"]
    if pose_crop is not None:
        merged.setdefault("pose_crop", {})
        merged["pose_crop"].update(pose_crop)
    if "editorial" in draft and isinstance(draft["editorial"], dict):
        merged.setdefault("editorial", {})
        merged["editorial"].update(draft["editorial"])
    merged["flash_analysis"] = draft
    return merged


def main():
    parser = argparse.ArgumentParser(description="Create a Flash-planned config from a bowling clip storyboard.")
    parser.add_argument("config", help="Path to base story config JSON")
    parser.add_argument("--samples", type=int, default=5, help="Number of storyboard frames")
    parser.add_argument("--model", default=DEFAULT_MODEL, help="Gemini Flash model ID")
    args = parser.parse_args()

    config_path = Path(args.config)
    with config_path.open() as f:
        config = json.load(f)

    output_dir = Path(config["output_dir"])
    output_dir.mkdir(parents=True, exist_ok=True)
    storyboard_prompt = output_dir / "flash_storyboard_prompt.jpg"

    frames, _, _ = extract_frames(
        config["input_video"],
        config["segment"]["start"],
        config["segment"]["end"],
        args.samples,
    )
    make_contact_sheet(
        frames,
        str(storyboard_prompt),
        "Flash Planning Board",
        "Single-bowler nets clip with timestamps for phase shaping",
    )

    api_key = load_api_key()
    if not api_key:
        raise RuntimeError("Missing GEMINI_API_KEY")

    response = call_flash(
        api_key,
        args.model,
        image_to_b64(str(storyboard_prompt)),
        config["segment"]["start"],
        config["segment"]["end"],
        frames,
    )

    raw_path = output_dir / "gemini_flash_plan.json"
    with raw_path.open("w") as f:
        json.dump(response, f, indent=2)

    merged = merge_config(config, response["draft"])
    merged_path = output_dir / "auto_story_config.json"
    with merged_path.open("w") as f:
        json.dump(merged, f, indent=2)

    print(json.dumps({
        "storyboard_prompt": str(storyboard_prompt),
        "plan": str(raw_path),
        "merged_config": str(merged_path),
        "model": args.model,
    }, indent=2))


if __name__ == "__main__":
    main()
