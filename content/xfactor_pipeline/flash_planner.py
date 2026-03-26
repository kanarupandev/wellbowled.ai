"""Gemini Flash planner: identify bowler ROI + phase timing (max 1 API call).

Uses gemini-2.5-flash via REST API (no SDK dependency).
Falls back to heuristics if API key is missing or call fails.
"""
from __future__ import annotations

import base64
import json
import math
import os
import urllib.error
import urllib.request
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFont

PIPELINE_DIR = Path(__file__).resolve().parent
REPO_ROOT = PIPELINE_DIR.parents[1]
DEFAULT_MODEL = "gemini-2.5-flash"


# ---------------------------------------------------------------------------
# Font helper
# ---------------------------------------------------------------------------
def _load_font(size: int, bold: bool = False):
    candidates = [
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


# ---------------------------------------------------------------------------
# API key loader
# ---------------------------------------------------------------------------
def _load_api_key() -> str | None:
    key = os.environ.get("GEMINI_API_KEY")
    if key:
        return key
    # Check linux_content_pipeline_work/.env
    env_path = REPO_ROOT / "linux_content_pipeline_work" / ".env"
    if env_path.exists():
        for line in env_path.read_text().splitlines():
            if line.startswith("GEMINI_API_KEY="):
                return line.split("=", 1)[1].strip()
    # Check repo root .env
    env_path2 = REPO_ROOT / ".env"
    if env_path2.exists():
        for line in env_path2.read_text().splitlines():
            if line.startswith("GEMINI_API_KEY="):
                return line.split("=", 1)[1].strip()
    return None


# ---------------------------------------------------------------------------
# Contact sheet builder
# ---------------------------------------------------------------------------
def _build_contact_sheet(
    video_path: str, num_frames: int = 6, output_dir: str | None = None,
) -> tuple[str, list[dict]]:
    """Extract sample frames and compose a contact sheet.

    Returns (path_to_sheet, frame_metadata).
    """
    cap = cv2.VideoCapture(video_path)
    fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
    total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    duration = total / fps if fps else 1.0
    w = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    h = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))

    sample_times = [duration * i / max(1, num_frames - 1) for i in range(num_frames)]
    frames = []
    for ts in sample_times:
        idx = int(ts * fps)
        cap.set(cv2.CAP_PROP_POS_FRAMES, min(idx, total - 1))
        ok, frame = cap.read()
        if ok:
            frames.append({
                "label": f"F{len(frames) + 1}",
                "time": round(ts, 3),
                "frame": frame,
            })
    cap.release()

    cols = 3
    rows = math.ceil(len(frames) / cols)
    tile_w, tile_h = 320, int(320 * h / max(1, w))
    gutter = 12
    header_h = 60
    sheet_w = cols * tile_w + (cols + 1) * gutter
    sheet_h = header_h + rows * tile_h + (rows + 1) * gutter

    canvas = Image.new("RGB", (sheet_w, sheet_h), (10, 14, 20))
    draw = ImageDraw.Draw(canvas)
    title_font = _load_font(24, bold=True)
    chip_font = _load_font(16, bold=True)
    draw.text((gutter, 16), "Bowling Clip Contact Sheet", font=title_font, fill=(240, 244, 248))

    for i, item in enumerate(frames):
        row, col = i // cols, i % cols
        x = gutter + col * (tile_w + gutter)
        y = header_h + gutter + row * (tile_h + gutter)
        rgb = cv2.cvtColor(item["frame"], cv2.COLOR_BGR2RGB)
        tile = Image.fromarray(rgb).resize((tile_w, tile_h))
        canvas.paste(tile, (x, y))
        draw.rounded_rectangle(
            (x + 8, y + 8, x + 130, y + 36), radius=10, fill=(10, 14, 20),
        )
        draw.text(
            (x + 16, y + 12),
            f"{item['label']}  {item['time']:.2f}s",
            font=chip_font, fill=(255, 255, 255),
        )

    out_dir = output_dir or str(PIPELINE_DIR / "output")
    Path(out_dir).mkdir(parents=True, exist_ok=True)
    sheet_path = str(Path(out_dir) / "flash_contact_sheet.jpg")
    canvas.save(sheet_path, quality=85)
    return sheet_path, frames


# ---------------------------------------------------------------------------
# Gemini Flash call
# ---------------------------------------------------------------------------
def call_flash(
    video_path: str,
    output_dir: str,
    model: str = DEFAULT_MODEL,
) -> dict | None:
    """Single Gemini Flash call to identify the bowler.

    Returns dict with bowler_roi, phases, bowling_arm, or None on failure.
    """
    api_key = _load_api_key()
    if not api_key:
        print("       [flash] No GEMINI_API_KEY -- skipping, will use heuristics")
        return None

    sheet_path, frames = _build_contact_sheet(video_path, output_dir=output_dir)

    with open(sheet_path, "rb") as f:
        sheet_b64 = base64.b64encode(f.read()).decode("utf-8")

    frame_list = "\n".join(f"- {fr['label']}: {fr['time']:.2f}s" for fr in frames)

    prompt = f"""This contact sheet shows frames from a cricket bowling clip at a nets session.
Frames are labeled with timestamps:
{frame_list}

There may be multiple people visible. Identify the PRIMARY BOWLER (the person actively bowling/delivering the ball) and ignore everyone else.

Return STRICT JSON only:
{{
  "bowler_roi": {{
    "x": 0.0,
    "y": 0.0,
    "w": 1.0,
    "h": 1.0
  }},
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
- bowler_roi must be a normalized bounding box (0-1) that contains the bowler across ALL frames. Make it generous (add 15% padding).
- Phases are timestamps in seconds.
- Focus ONLY on the person delivering the ball. Ignore fielders, batsmen, coaches, bystanders.
- If you cannot identify the bowler confidently, set bowler_roi to full frame."""

    payload = {
        "contents": [{"parts": [
            {"text": "Contact sheet of a bowling clip:"},
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
        url,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
    )

    try:
        with urllib.request.urlopen(req, timeout=90) as resp:
            response = json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        print(f"       [flash] HTTP {exc.code}: {body[:300]}")
        return None
    except Exception as exc:
        print(f"       [flash] Error: {exc}")
        return None

    try:
        text = response["candidates"][0]["content"]["parts"][0]["text"]
        result = json.loads(text)
    except (KeyError, IndexError, json.JSONDecodeError) as exc:
        print(f"       [flash] Failed to parse response: {exc}")
        return None

    # Persist for debugging
    plan_path = Path(output_dir) / "flash_plan.json"
    plan_path.parent.mkdir(parents=True, exist_ok=True)
    with plan_path.open("w") as f:
        json.dump({"result": result, "raw": response}, f, indent=2)

    print(f"       [flash] Bowler: {result.get('bowler_description', 'unknown')}")
    print(f"       [flash] ROI: {result.get('bowler_roi')}")
    print(f"       [flash] Arm: {result.get('bowling_arm')}")

    return result
