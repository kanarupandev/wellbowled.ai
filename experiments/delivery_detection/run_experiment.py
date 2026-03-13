"""
Experiment: Delivery Detection Consistency
==========================================
Hypothesis: Gemini 3 Flash can detect bowling deliveries and return
release timestamps within +/- 0.2s consistency across runs.

Input: 3s single-delivery nets video
Runs: 5 identical calls, same prompt, temp=0.1
Success: all release_ts values within 0.2s of each other
"""

import base64
import json
import time
import statistics
import os
import sys
import urllib.request

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(SCRIPT_DIR, ".."))
from shared_config import SCOUT_MODEL as MODEL, load_api_key

API_KEY = load_api_key()
VIDEO_PATH = os.path.join(SCRIPT_DIR, "../../resources/samples/3_sec_1_delivery_nets.mp4")
RUNS = 5
TEMP = 0.1

SCOUT_PROMPT = """Watch the entire video carefully. Track the bowler's state throughout:

STATES:
- IDLE: Standing, walking, or preparing — not actively bowling
- RUN_UP: Moving toward the crease with clear intent to bowl
- DELIVERY: Bowling arm swings over and ball is released (or would be released in shadow bowling)
- FOLLOW_THROUGH: Post-release deceleration and body rotation

DETECTION RULES:
- A delivery = the transition from RUN_UP → DELIVERY
- The release_ts = the exact moment the ball leaves the hand (arm at highest vertical point, fingers opening)
- If shadow bowling (no ball): release_ts = the moment the arm reaches peak height where release WOULD occur

STEP 1: Watch the full video. Count how many delivery actions you see. State the count.
STEP 2: For each delivery, identify the precise release timestamp in seconds.

PHANTOM DETECTION:
- If someone runs up but does NOT rotate the bowling arm over the head, it is NOT a delivery
- Mark as phantom ONLY if the run-up pattern was clearly detected but no arm rotation followed

IMPORTANT:
- Timestamps must be as precise as possible (to 0.1s)
- Confidence reflects how clearly visible the release point is
- Report what you SEE, not what you assume

Output JSON:
{"scan_summary": "description of what you see", "candidates_considered": N, "confirmed_deliveries": N, "phantom_deliveries": N, "deliveries": [{"id": 1, "release_ts": float, "confidence": float}]}"""


def call_gemini(video_b64: str, prompt: str) -> dict:
    """Call Gemini API and return parsed response."""
    url = f"https://generativelanguage.googleapis.com/v1beta/models/{MODEL}:generateContent?key={API_KEY}"

    payload = {
        "contents": [{
            "parts": [
                {"inlineData": {"mimeType": "video/mp4", "data": video_b64}},
                {"text": prompt}
            ]
        }],
        "generationConfig": {
            "temperature": TEMP,
            "responseMimeType": "application/json"
        }
    }

    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json"})

    with urllib.request.urlopen(req, timeout=60) as resp:
        return json.loads(resp.read().decode("utf-8"))


def extract_result(response: dict) -> dict:
    """Extract delivery data from Gemini response."""
    text = response["candidates"][0]["content"]["parts"][0]["text"]
    data = json.loads(text)
    usage = response.get("usageMetadata", {})
    return {
        "data": data,
        "tokens": {
            "prompt": usage.get("promptTokenCount", 0),
            "output": usage.get("candidatesTokenCount", 0),
            "thought": usage.get("thoughtsTokenCount", 0),
            "total": usage.get("totalTokenCount", 0),
        }
    }


def main():
    print(f"=== Delivery Detection Experiment ===")
    print(f"Model: {MODEL}")
    print(f"Video: {os.path.basename(VIDEO_PATH)}")
    print(f"Runs: {RUNS}")
    print(f"Temperature: {TEMP}")
    print(f"Success criteria: all release_ts within +/- 0.2s")
    print()

    # Load and encode video
    with open(VIDEO_PATH, "rb") as f:
        video_b64 = base64.b64encode(f.read()).decode("utf-8")
    print(f"Video size: {len(video_b64)} bytes (base64)")
    print()

    results = []
    for i in range(RUNS):
        print(f"--- Run {i+1}/{RUNS} ---")
        start = time.time()
        try:
            response = call_gemini(video_b64, SCOUT_PROMPT)
            result = extract_result(response)
            elapsed = time.time() - start

            data = result["data"]
            deliveries = data.get("deliveries", [])
            ts = deliveries[0]["release_ts"] if deliveries else None
            conf = deliveries[0]["confidence"] if deliveries else None

            print(f"  release_ts={ts}, confidence={conf}, "
                  f"confirmed={data.get('confirmed_deliveries')}, "
                  f"phantoms={data.get('phantom_deliveries')}")
            print(f"  tokens: {result['tokens']['total']} total "
                  f"({result['tokens']['prompt']} in, {result['tokens']['output']} out, "
                  f"{result['tokens']['thought']} thought)")
            print(f"  latency: {elapsed:.2f}s")
            print(f"  summary: {data.get('scan_summary', '')[:80]}")

            results.append({
                "run": i + 1,
                "release_ts": ts,
                "confidence": conf,
                "confirmed_deliveries": data.get("confirmed_deliveries"),
                "phantom_deliveries": data.get("phantom_deliveries"),
                "scan_summary": data.get("scan_summary"),
                "tokens": result["tokens"],
                "latency_s": round(elapsed, 2),
                "full_response": data,
            })
        except Exception as e:
            print(f"  ERROR: {e}")
            results.append({"run": i + 1, "error": str(e)})

        if i < RUNS - 1:
            time.sleep(2)
        print()

    # Analysis
    print("=" * 50)
    print("ANALYSIS")
    print("=" * 50)

    timestamps = [r["release_ts"] for r in results if "release_ts" in r and r["release_ts"] is not None]
    confidences = [r["confidence"] for r in results if "confidence" in r and r["confidence"] is not None]
    latencies = [r["latency_s"] for r in results if "latency_s" in r]

    if timestamps:
        ts_mean = statistics.mean(timestamps)
        ts_range = max(timestamps) - min(timestamps)
        ts_stdev = statistics.stdev(timestamps) if len(timestamps) > 1 else 0

        print(f"\nTimestamps: {timestamps}")
        print(f"  Mean: {ts_mean:.2f}s")
        print(f"  Range: {ts_range:.2f}s (max - min)")
        print(f"  Stdev: {ts_stdev:.3f}s")
        print(f"  All within +/- 0.2s of mean: {all(abs(t - ts_mean) <= 0.2 for t in timestamps)}")

        print(f"\nConfidences: {confidences}")
        print(f"  Mean: {statistics.mean(confidences):.2f}")

        print(f"\nLatencies: {latencies}")
        print(f"  Mean: {statistics.mean(latencies):.2f}s")

        # Verdict
        within_threshold = ts_range <= 0.4  # +/- 0.2s means total range <= 0.4s
        all_detected = all(r.get("confirmed_deliveries") == 1 for r in results if "confirmed_deliveries" in r)
        no_phantoms = all(r.get("phantom_deliveries") == 0 for r in results if "phantom_deliveries" in r)

        print(f"\n{'=' * 50}")
        print(f"VERDICT")
        print(f"{'=' * 50}")
        print(f"  Detection correct (1 delivery): {'PASS' if all_detected else 'FAIL'}")
        print(f"  No phantom false positives:     {'PASS' if no_phantoms else 'FAIL'}")
        print(f"  Timestamp range <= 0.4s:        {'PASS' if within_threshold else 'FAIL'} ({ts_range:.2f}s)")
        print(f"  Overall: {'VERIFIED' if (all_detected and no_phantoms and within_threshold) else 'NEEDS INVESTIGATION'}")

    # Save raw results
    output_path = os.path.join(os.path.dirname(__file__), "001_results.json")
    with open(output_path, "w") as f:
        json.dump({"config": {"model": MODEL, "runs": RUNS, "temp": TEMP, "prompt": SCOUT_PROMPT}, "results": results}, f, indent=2)
    print(f"\nRaw results saved to: {output_path}")


if __name__ == "__main__":
    main()
