#!/usr/bin/env python3
"""Stage 1: Scene Understanding — send video to Gemini Pro 3 Preview."""
import base64
import json
import sys
import urllib.error
import urllib.request
from pathlib import Path


def load_api_key():
    for env_path in [Path("linux_content_pipeline_work/.env"), Path(".env")]:
        if env_path.exists():
            for line in env_path.read_text().splitlines():
                if line.startswith("GEMINI_API_KEY="):
                    return line.split("=", 1)[1].strip()
    import os
    return os.environ.get("GEMINI_API_KEY")


PROMPT = """You are a cricket biomechanics analyst. Analyze this bowling video clip.

STEP 1: Watch the video carefully. Count how many people are visible. Identify which person is the PRIMARY BOWLER — the one who runs in and delivers the ball.

STEP 2: Describe what the bowler is wearing (shirt color, pants color) so we can distinguish them from others.

STEP 3: For the bowler ONLY, track their position through the video. At each timestamp below, look at the actual video frame and report where the bowler's torso center is. DO NOT interpolate or guess — look at the actual frame.

STEP 4: Identify the exact moments of the delivery. Watch for:
- back_foot_contact: the frame where the back foot plants at the bowling crease during the delivery stride
- front_foot_contact: the frame where the front foot plants
- release: the frame where the ball visibly leaves the bowler's hand
- follow_through_end: when the bowling arm has completed its swing

Return STRICT JSON:
{
  "bowler_id": "description with clothing",
  "bowling_arm": "right" or "left",
  "bowler_clothing": {"shirt": "color", "pants": "color"},
  "people_in_frame": [
    {"description": "string", "role": "bowler" or "bystander" or "batsman" or "other"}
  ],
  "bowler_positions": [
    {"time_s": float, "x": float 0-1, "y": float 0-1, "visible": true/false, "note": "what bowler is doing at this moment"}
  ],
  "action_window": {
    "start_s": float,
    "end_s": float
  },
  "timestamps_s": {
    "run_up_visible": float,
    "back_foot_contact": float,
    "front_foot_contact": float,
    "release": float,
    "follow_through_end": float
  },
  "camera_angle": "behind" or "side-on" or "front-on" or "elevated" or "mixed",
  "camera_movement": "static" or "panning" or "zooming" or "mixed",
  "clip_quality": int 1-10,
  "people_count": int,
  "confidence": float 0-1,
  "recommended_techniques": []
}

CRITICAL RULES:
- For bowler_positions: report at EVERY 0.1s interval. For each one, actually look at that frame. If the bowler is not visible, set visible=false. The x,y coordinates should reflect the bowler's ACTUAL position in that frame, not a smoothed guess.
- Timestamps to 0.01s precision.
- x=0 is left edge, x=1 is right edge. y=0 is top, y=1 is bottom.
- The bowler runs INTO the frame — their position changes non-linearly.
- If the bowler's arm is up at one moment and down the next, the positions should reflect that the torso moved differently in each.

ADDITIONALLY, identify the BEST frame for object tracking:
- "best_prompt_frame": the timestamp where the bowler is MOST clearly visible, their full torso is in frame, they are NOT overlapping with any other person, and their body area in the frame is largest.
- "best_prompt_point": the x,y of the bowler's TORSO CENTER (between shoulders and hips) in that frame. This must be precise — it will be used to initialize an object tracking model.
- "best_prompt_bbox": bounding box [x1, y1, x2, y2] normalized 0-1 tightly around the bowler's full body in that frame.

Add these three fields to the root of the JSON response.
"""


def run(run_root: str, clip_path: str):
    root = Path(run_root)
    stage_dir = root / "stage1"
    stage_dir.mkdir(parents=True, exist_ok=True)

    # Load Stage 0 metadata
    meta = json.loads((root / "stage0" / "clip_metadata.json").read_text())

    # Load video as base64
    clip = Path(clip_path).resolve()
    with open(clip, "rb") as f:
        video_b64 = base64.b64encode(f.read()).decode("utf-8")
    size_mb = len(video_b64) * 3 / 4 / 1e6
    print(f"Video: {clip.name} ({size_mb:.1f}MB)")

    api_key = load_api_key()
    assert api_key, "No GEMINI_API_KEY found"

    # Send video directly to Gemini
    payload = {
        "contents": [{
            "parts": [
                {"inlineData": {"mimeType": "video/mp4", "data": video_b64}},
                {"text": PROMPT},
            ]
        }],
        "generationConfig": {
            "temperature": 0.1,
            "responseMimeType": "application/json",
        },
    }

    model = "gemini-3-pro-preview"  # Best model first — fail fast
    url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={api_key}"

    print(f"Calling {model}...")
    req = urllib.request.Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
    )

    try:
        with urllib.request.urlopen(req, timeout=600) as resp:
            response = json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")[:500]
        print(f"ERROR: HTTP {exc.code}: {body}")
        sys.exit(1)

    text = response["candidates"][0]["content"]["parts"][0]["text"]
    scene_report = json.loads(text)
    scene_report["model_used"] = model

    # Validate
    assert scene_report.get("bowler_positions") or scene_report.get("bowler_center_points"), "No bowler detected"
    ts = scene_report.get("timestamps_s", {})
    assert ts.get("back_foot_contact", 0) < ts.get("release", 0), "Timestamps not chronological"
    assert scene_report.get("clip_quality", 0) >= 1, "No quality score"

    # Save
    with open(stage_dir / "scene_report.json", "w") as f:
        json.dump(scene_report, f, indent=2)

    # Also save raw Gemini response for debugging
    with open(stage_dir / "gemini_raw.json", "w") as f:
        json.dump(response, f, indent=2)

    print(f"\nStage 1 PASSED")
    print(f"  Bowler: {scene_report.get('bowler_id')}")
    print(f"  Arm: {scene_report.get('bowling_arm')}")
    print(f"  Action window: {scene_report.get('action_window', {}).get('start_s')}s → {scene_report.get('action_window', {}).get('end_s')}s")
    print(f"  BFC: {ts.get('back_foot_contact')}s")
    print(f"  Release: {ts.get('release')}s")
    print(f"  Follow-through: {ts.get('follow_through_end')}s")
    print(f"  Camera: {scene_report.get('camera_angle')}")
    print(f"  Quality: {scene_report.get('clip_quality')}/10")
    print(f"  People: {scene_report.get('people_count')}")
    print(f"  Confidence: {scene_report.get('confidence')}")
    print(f"  Center points: {len(scene_report.get('bowler_center_points', []))}")
    print(f"  Model: {model}")

    return scene_report


if __name__ == "__main__":
    clip = sys.argv[1] if len(sys.argv) > 1 else "resources/samples/3_sec_1_delivery_nets.mp4"
    run_root = sys.argv[2] if len(sys.argv) > 2 else "content/pipeline_v1_linux/runs/test_run"
    run(run_root, clip)
