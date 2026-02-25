"""
Speed Estimation via Gemini 3 Pro
==================================
Sends delivery clips to gemini-3-pro-preview for bowling speed estimation.
Runs 5 times per clip to measure consistency.

Usage:
  python speed_gemini.py [--clip-dir DIR] [--runs N]
"""

import argparse
import base64
import glob
import json
import os
import statistics
import time
import urllib.request

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ENV_PATH = os.path.join(SCRIPT_DIR, "../../.env")
MODEL = "gemini-3-pro-preview"

SPEED_PROMPT = """Analyze this cricket bowling delivery clip and estimate the bowling speed.

CONTEXT:
- This is a backyard/nets session (NOT a regulation ground)
- Pitch distance is typically 16-18m for backyard setups (shorter than regulation 20.12m)
- Infer the distance from visual cues (pitch length, bowler proportions, environment)

ANALYZE:
1. Observe the bowler's run-up speed and arm action
2. Note the ball flight after release (if visible)
3. Consider biomechanical cues: arm speed, body rotation, follow-through energy
4. Estimate the bowling type (fast, medium, spin)

RESPOND with ONLY this JSON:
{"speed_kph": 95, "type": "medium", "confidence": "medium", "reasoning": "short sentence"}

Speed must be a single number (your best estimate). Confidence: low/medium/high.
Type: fast (>130), medium (100-130), medium-slow (80-100), spin (<80)."""


def load_api_key():
    if os.path.exists(ENV_PATH):
        with open(ENV_PATH) as f:
            for line in f:
                if line.startswith("GEMINI_API_KEY="):
                    return line.strip().split("=", 1)[1]
    return os.environ.get("GEMINI_API_KEY")


def call_gemini(api_key, video_b64):
    url = f"https://generativelanguage.googleapis.com/v1beta/models/{MODEL}:generateContent?key={api_key}"

    payload = {
        "contents": [{"parts": [
            {"inlineData": {"mimeType": "video/mp4", "data": video_b64}},
            {"text": SPEED_PROMPT},
        ]}],
        "generationConfig": {
            "temperature": 0.1,
            "responseMimeType": "application/json",
        },
    }

    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=120) as resp:
        return json.loads(resp.read().decode("utf-8"))


def main():
    parser = argparse.ArgumentParser(description="Gemini Pro speed estimation")
    parser.add_argument("--clip-dir", "-d", default=os.path.join(SCRIPT_DIR, "clips"))
    parser.add_argument("--runs", "-r", type=int, default=5)
    args = parser.parse_args()

    api_key = load_api_key()
    clips = sorted(glob.glob(os.path.join(args.clip_dir, "gt_delivery_*.mp4")))

    if not clips:
        print("No GT clips found. Run simulate_live.py first.")
        return

    print(f"Speed estimation: {MODEL}")
    print(f"Clips: {len(clips)}, Runs: {args.runs}")
    print()

    all_results = {}

    for clip_path in clips:
        clip_name = os.path.basename(clip_path)
        size_kb = os.path.getsize(clip_path) / 1024
        print(f"--- {clip_name} ({size_kb:.0f}KB) ---")

        with open(clip_path, "rb") as f:
            video_b64 = base64.b64encode(f.read()).decode("utf-8")

        speeds = []
        types_seen = []
        results = []

        for i in range(args.runs):
            t0 = time.time()
            try:
                resp = call_gemini(api_key, video_b64)
                latency = time.time() - t0

                text = resp["candidates"][0]["content"]["parts"][0]["text"]
                tokens = resp.get("usageMetadata", {}).get("totalTokenCount", 0)
                data = json.loads(text)

                speed = data.get("speed_kph", 0)
                speeds.append(speed)
                types_seen.append(data.get("type", "?"))
                results.append(data)

                print(f"  Run {i+1}: {speed} kph ({data.get('type', '?')}) "
                      f"[{data.get('confidence', '?')}] ({latency:.1f}s, {tokens} tok)")

            except Exception as e:
                print(f"  Run {i+1}: ERROR {e}")
                results.append({"error": str(e)})

            if i < args.runs - 1:
                time.sleep(1)

        if speeds:
            avg = statistics.mean(speeds)
            spread = max(speeds) - min(speeds)
            stdev = statistics.stdev(speeds) if len(speeds) > 1 else 0
            consistent = spread <= 2.0  # user requirement: ±2 kph consistency
            print(f"  Summary: {avg:.0f} kph avg, spread={spread:.0f}, stdev={stdev:.1f}, "
                  f"consistent={consistent}, types={set(types_seen)}")

        all_results[clip_name] = {
            "speeds": speeds,
            "types": types_seen,
            "runs": results,
        }
        print()

    # Save
    result_path = os.path.join(SCRIPT_DIR, "result_speed_gemini.json")
    with open(result_path, "w") as f:
        json.dump({"model": MODEL, "results": all_results}, f, indent=2)
    print(f"Saved: {result_path}")

    # Summary
    print(f"\n{'='*50}")
    print("SPEED ESTIMATION SUMMARY (Gemini Pro)")
    print(f"{'='*50}")
    for clip_name, r in all_results.items():
        if r["speeds"]:
            avg = statistics.mean(r["speeds"])
            spread = max(r["speeds"]) - min(r["speeds"])
            print(f"  {clip_name}: {avg:.0f} kph (spread: {spread:.0f} kph) [{set(r['types'])}]")


if __name__ == "__main__":
    main()
