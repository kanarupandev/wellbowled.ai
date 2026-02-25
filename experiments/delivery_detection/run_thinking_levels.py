"""
Experiment 002: thinkingLevel Impact on Latency & Accuracy
==========================================================
Hypothesis: Reducing thinkingLevel from default to "low" or "minimal"
cuts latency from ~9s to ~3-5s without degrading detection accuracy.

Baseline (Experiment 001): 5 runs at default thinking
  - Timestamps: [1.4, 1.3, 1.4, 1.4, 1.4], range=0.10s
  - Mean latency: 9.09s
  - Mean confidence: 0.93
  - 5/5 correct, 0 phantoms
"""

import base64
import json
import time
import statistics
import os
import urllib.request

# Config
API_KEY = None
env_path = os.path.join(os.path.dirname(__file__), "../../.env")
if os.path.exists(env_path):
    with open(env_path) as f:
        for line in f:
            if line.startswith("GEMINI_API_KEY="):
                API_KEY = line.strip().split("=", 1)[1]

VIDEO_PATH = os.path.join(os.path.dirname(__file__), "../../resources/samples/3_sec_1_delivery_nets.mp4")
MODEL = "gemini-3-flash-preview"
RUNS_PER_LEVEL = 5
TEMP = 0.1

THINKING_LEVELS = ["low", "minimal"]

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


def call_gemini(video_b64: str, prompt: str, thinking_level: str = None) -> dict:
    url = f"https://generativelanguage.googleapis.com/v1beta/models/{MODEL}:generateContent?key={API_KEY}"

    gen_config = {
        "temperature": TEMP,
        "responseMimeType": "application/json",
    }
    if thinking_level:
        gen_config["thinkingConfig"] = {"thinkingLevel": thinking_level.upper()}

    payload = {
        "contents": [{
            "parts": [
                {"inlineData": {"mimeType": "video/mp4", "data": video_b64}},
                {"text": prompt}
            ]
        }],
        "generationConfig": gen_config
    }

    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json"})

    with urllib.request.urlopen(req, timeout=60) as resp:
        return json.loads(resp.read().decode("utf-8"))


def extract_result(response: dict) -> dict:
    # With thinkingLevel, response may have multiple parts (thought + text)
    # Find the text part that contains JSON
    parts = response["candidates"][0]["content"]["parts"]
    text = None
    for p in parts:
        if "text" in p:
            text = p["text"]

    if not text:
        raise ValueError("No text part in response")

    data = json.loads(text)
    # Handle response being a list (happens with some thinkingLevels)
    if isinstance(data, list):
        data = data[0] if data else {}

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


def run_level(video_b64: str, thinking_level: str) -> list:
    print(f"\n{'='*60}")
    print(f"  thinkingLevel: {thinking_level}")
    print(f"{'='*60}")

    results = []
    for i in range(RUNS_PER_LEVEL):
        print(f"\n--- Run {i+1}/{RUNS_PER_LEVEL} ---")
        start = time.time()
        try:
            response = call_gemini(video_b64, SCOUT_PROMPT, thinking_level)
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
                  f"(thought={result['tokens']['thought']})")
            print(f"  latency: {elapsed:.2f}s")

            results.append({
                "run": i + 1,
                "thinking_level": thinking_level,
                "release_ts": ts,
                "confidence": conf,
                "confirmed_deliveries": data.get("confirmed_deliveries"),
                "phantom_deliveries": data.get("phantom_deliveries"),
                "scan_summary": data.get("scan_summary"),
                "tokens": result["tokens"],
                "latency_s": round(elapsed, 2),
            })
        except Exception as e:
            print(f"  ERROR: {e}")
            results.append({"run": i + 1, "thinking_level": thinking_level, "error": str(e)})

        if i < RUNS_PER_LEVEL - 1:
            time.sleep(2)

    return results


def analyze(label: str, results: list):
    timestamps = [r["release_ts"] for r in results if r.get("release_ts") is not None]
    confidences = [r["confidence"] for r in results if r.get("confidence") is not None]
    latencies = [r["latency_s"] for r in results if r.get("latency_s") is not None]
    thoughts = [r["tokens"]["thought"] for r in results if r.get("tokens")]

    if not timestamps:
        print(f"\n  {label}: NO VALID RESULTS")
        return {}

    ts_mean = statistics.mean(timestamps)
    ts_range = max(timestamps) - min(timestamps)
    all_detected = all(r.get("confirmed_deliveries") == 1 for r in results if "confirmed_deliveries" in r)
    no_phantoms = all(r.get("phantom_deliveries") == 0 for r in results if "phantom_deliveries" in r)

    summary = {
        "thinking_level": label,
        "timestamps": timestamps,
        "ts_mean": round(ts_mean, 2),
        "ts_range": round(ts_range, 2),
        "confidence_mean": round(statistics.mean(confidences), 2),
        "latency_mean": round(statistics.mean(latencies), 2),
        "latency_min": round(min(latencies), 2),
        "latency_max": round(max(latencies), 2),
        "thought_tokens_mean": round(statistics.mean(thoughts)),
        "detection_correct": all_detected,
        "no_phantoms": no_phantoms,
        "passed": all_detected and no_phantoms and ts_range <= 0.4,
    }

    print(f"\n  {label}:")
    print(f"    Timestamps: {timestamps} (range={ts_range:.2f}s)")
    print(f"    Confidence: {round(statistics.mean(confidences), 2)}")
    print(f"    Latency: {round(statistics.mean(latencies), 2)}s "
          f"(min={round(min(latencies), 2)}, max={round(max(latencies), 2)})")
    print(f"    Thought tokens: {round(statistics.mean(thoughts))}")
    print(f"    Detection: {'PASS' if all_detected else 'FAIL'}")
    print(f"    Phantoms: {'PASS' if no_phantoms else 'FAIL'}")
    print(f"    Overall: {'PASS' if summary['passed'] else 'FAIL'}")

    return summary


def main():
    print("=" * 60)
    print("  Experiment 002: thinkingLevel Impact")
    print("=" * 60)
    print(f"Model: {MODEL}")
    print(f"Runs per level: {RUNS_PER_LEVEL}")
    print(f"Levels: {THINKING_LEVELS}")
    print(f"Baseline (exp 001): latency=9.09s, range=0.10s, confidence=0.93")

    with open(VIDEO_PATH, "rb") as f:
        video_b64 = base64.b64encode(f.read()).decode("utf-8")

    all_results = {}
    for level in THINKING_LEVELS:
        results = run_level(video_b64, level)
        all_results[level] = results

    # Analysis
    print("\n" + "=" * 60)
    print("  COMPARISON")
    print("=" * 60)

    baseline = {
        "thinking_level": "default (exp 001)",
        "timestamps": [1.4, 1.3, 1.4, 1.4, 1.4],
        "ts_mean": 1.38,
        "ts_range": 0.10,
        "confidence_mean": 0.93,
        "latency_mean": 9.09,
        "latency_min": 7.89,
        "latency_max": 9.74,
        "thought_tokens_mean": 765,
        "detection_correct": True,
        "no_phantoms": True,
        "passed": True,
    }

    summaries = [baseline]
    print(f"\n  default (exp 001 baseline):")
    print(f"    Latency: 9.09s, Range: 0.10s, Confidence: 0.93, Thoughts: 765")
    print(f"    Overall: PASS")

    for level in THINKING_LEVELS:
        s = analyze(level, all_results[level])
        if s:
            summaries.append(s)

    # Summary table
    print("\n" + "=" * 60)
    print("  SUMMARY TABLE")
    print("=" * 60)
    print(f"{'Level':<15} {'Latency':>8} {'Range':>8} {'Conf':>6} {'Thoughts':>10} {'Result':>8}")
    print("-" * 60)
    for s in summaries:
        print(f"{s['thinking_level']:<15} {s['latency_mean']:>7.2f}s {s['ts_range']:>7.2f}s "
              f"{s['confidence_mean']:>5.2f} {s['thought_tokens_mean']:>9} "
              f"{'PASS' if s['passed'] else 'FAIL':>8}")

    # Recommendation
    print("\n" + "=" * 60)
    print("  RECOMMENDATION")
    print("=" * 60)
    passed_levels = [s for s in summaries if s["passed"]]
    if passed_levels:
        best = min(passed_levels, key=lambda s: s["latency_mean"])
        print(f"  Best passing level: {best['thinking_level']}")
        print(f"  Latency: {best['latency_mean']}s (vs 9.09s baseline)")
        if best["latency_mean"] < 9.09:
            savings = ((9.09 - best["latency_mean"]) / 9.09) * 100
            print(f"  Latency reduction: {savings:.0f}%")

    # Save
    output_path = os.path.join(os.path.dirname(__file__), "002_results.json")
    with open(output_path, "w") as f:
        json.dump({
            "config": {"model": MODEL, "runs_per_level": RUNS_PER_LEVEL, "temp": TEMP, "levels": THINKING_LEVELS},
            "baseline": baseline,
            "results": {level: all_results[level] for level in THINKING_LEVELS},
            "summaries": summaries,
        }, f, indent=2)
    print(f"\nResults saved to: {output_path}")


if __name__ == "__main__":
    main()
