"""
Live Detection Simulator + Clip Extraction
============================================
Simulates real-time delivery detection by polling generateContent
at ~1 frame per 2 seconds. Extracts clips around detections for
speed analysis.

NOTE: Gemini Live API (native-audio models only) does not support
text-based video detection as of Feb 2026. This uses polling with
generateContent as a practical alternative.

Usage:
  python simulate_live.py <video_path> [--ground-truth FRAMES] [--clip-dir DIR]

Example:
  python simulate_live.py ../../resources/samples/whatsapp_nets_session.mp4 \
    -g 203,565,1127,1770 -d ./clips
"""

import argparse
import base64
import json
import os
import re
import sys
import time
import urllib.request
import cv2

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(SCRIPT_DIR, ".."))
from shared_config import SCOUT_MODEL as MODEL, POLL_INTERVAL_S as POLL_INTERVAL, load_api_key
from shared_config import (
    DEFAULT_JPEG_QUALITY,
    DEFAULT_TEMPERATURE,
    DETECTION_COOLDOWN_S,
    DETECTION_HTTP_TIMEOUT_S,
    POLL_RATE_LIMIT_SLEEP_S,
)


DETECT_PROMPT = """You are watching a live cricket bowling session one frame at a time.

These frames are from the last {interval} seconds (labeled with timestamps).

A bowling delivery = bowler runs up, arm swings over, releases ball. All styles: overarm, side-arm, spin, shadow.

Did a bowling delivery happen in these frames? Be precise about which second.

Reply ONLY with JSON:
{{"delivery": true, "second": 7.0}} or {{"delivery": false}}"""


def call_gemini(api_key, frames_b64, timestamps, interval):
    """Send frames to generateContent and ask about deliveries."""
    url = f"https://generativelanguage.googleapis.com/v1beta/models/{MODEL}:generateContent?key={api_key}"

    parts = []
    for b64, ts in zip(frames_b64, timestamps):
        parts.append({"text": f"Frame at {ts:.1f}s:"})
        parts.append({"inlineData": {"mimeType": "image/jpeg", "data": b64}})

    parts.append({"text": DETECT_PROMPT.format(interval=interval)})

    payload = {
        "contents": [{"parts": parts}],
        "generationConfig": {
            "temperature": DEFAULT_TEMPERATURE,
            "responseMimeType": "application/json",
        },
    }

    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=DETECTION_HTTP_TIMEOUT_S) as resp:
        return json.loads(resp.read().decode("utf-8"))


def extract_clip(video_path, center_time, before=1.0, after=1.5, output_path=None):
    """Extract clip from [center_time - before, center_time + after] at original fps."""
    cap = cv2.VideoCapture(video_path)
    fps = cap.get(cv2.CAP_PROP_FPS)
    width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))

    start_time = max(0, center_time - before)
    end_time = min(total / fps, center_time + after)
    start_frame = int(start_time * fps)
    end_frame = int(end_time * fps)

    fourcc = cv2.VideoWriter_fourcc(*"mp4v")
    out = cv2.VideoWriter(output_path, fourcc, fps, (width, height))

    cap.set(cv2.CAP_PROP_POS_FRAMES, start_frame)
    for _ in range(end_frame - start_frame):
        ret, frame = cap.read()
        if not ret:
            break
        out.write(frame)

    cap.release()
    out.release()
    return end_frame - start_frame, fps


def main():
    parser = argparse.ArgumentParser(description="Simulated live delivery detection")
    parser.add_argument("video", help="Path to video file")
    parser.add_argument("--ground-truth", "-g", help="Ground truth frames, comma-separated")
    parser.add_argument("--clip-dir", "-d", default=None, help="Directory for clips")
    parser.add_argument("--interval", "-i", type=int, default=POLL_INTERVAL, help="Poll interval in seconds")
    args = parser.parse_args()

    video_path = os.path.abspath(args.video)
    clip_dir = os.path.abspath(args.clip_dir) if args.clip_dir else os.path.join(SCRIPT_DIR, "clips")
    api_key = load_api_key()
    interval = args.interval

    gt_frames = [int(x.strip()) for x in args.ground_truth.split(",")] if args.ground_truth else []

    cap = cv2.VideoCapture(video_path)
    fps = cap.get(cv2.CAP_PROP_FPS)
    total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    duration = total_frames / fps
    cap.release()

    gt_timestamps = [f / fps for f in gt_frames]

    print(f"Video: {os.path.basename(video_path)} ({fps}fps, {duration:.1f}s)")
    print(f"Model: {MODEL}, poll every {interval}s")
    if gt_timestamps:
        print(f"Ground truth: {[f'{t:.2f}s' for t in gt_timestamps]}")
    print()

    # Simulate live polling
    detections = []
    cooldown_until = 0  # avoid double-detecting same delivery
    total_tokens = 0
    start_time = time.time()

    for window_start in range(0, int(duration), interval):
        window_end = min(window_start + interval, int(duration))

        # Extract 1 frame per second in this window
        cap = cv2.VideoCapture(video_path)
        frames_b64 = []
        timestamps = []

        for sec in range(window_start, window_end):
            frame_num = int(sec * fps)
            cap.set(cv2.CAP_PROP_POS_FRAMES, frame_num)
            ret, frame = cap.read()
            if not ret:
                break
            _, buf = cv2.imencode(".jpg", frame, [cv2.IMWRITE_JPEG_QUALITY, DEFAULT_JPEG_QUALITY])
            frames_b64.append(base64.b64encode(buf.tobytes()).decode("utf-8"))
            timestamps.append(float(sec))

        cap.release()

        if not frames_b64:
            continue

        # Skip if in cooldown (just detected a delivery)
        if window_start < cooldown_until:
            print(f"  [{window_start}-{window_end}s] (cooldown, skipping)")
            continue

        t0 = time.time()
        try:
            resp = call_gemini(api_key, frames_b64, timestamps, interval)
            latency = time.time() - t0

            text = resp["candidates"][0]["content"]["parts"][0]["text"]
            tokens = resp.get("usageMetadata", {}).get("totalTokenCount", 0)
            total_tokens += tokens

            data = json.loads(text)

            if data.get("delivery"):
                det_sec = data.get("second", window_start + interval / 2)
                detections.append({"time": det_sec, "window": [window_start, window_end]})
                cooldown_until = det_sec + DETECTION_COOLDOWN_S
                print(f"  [{window_start}-{window_end}s] >>> DELIVERY at {det_sec}s (latency: {latency:.1f}s, tokens: {tokens})")
            else:
                print(f"  [{window_start}-{window_end}s] no delivery (latency: {latency:.1f}s, tokens: {tokens})")

        except Exception as e:
            print(f"  [{window_start}-{window_end}s] ERROR: {e}")

        time.sleep(POLL_RATE_LIMIT_SLEEP_S)

    elapsed = time.time() - start_time

    # Results
    print(f"\n{'='*50}")
    print(f"DETECTION RESULTS")
    print(f"{'='*50}")
    print(f"Video: {duration:.1f}s processed in {elapsed:.1f}s")
    print(f"Polls: {int(duration) // interval}, Total tokens: {total_tokens}")
    print(f"Detections: {len(detections)}")

    for i, d in enumerate(detections):
        print(f"  D{i+1}: {d['time']}s")

    if gt_timestamps:
        print(f"\nGround truth comparison (±2.0s):")
        matched = 0
        for gi, gt in enumerate(gt_timestamps):
            best = min(detections, key=lambda d: abs(d["time"] - gt)) if detections else None
            delta = abs(best["time"] - gt) if best else float("inf")
            if delta <= 2.0:
                matched += 1
                print(f"  GT D{gi+1} ({gt:.2f}s) ← detected {best['time']}s (delta: {delta:.1f}s) MATCH")
            else:
                print(f"  GT D{gi+1} ({gt:.2f}s) ← {'nearest: ' + str(best['time']) + 's' if best else 'none'} MISS")
        print(f"  Score: {matched}/{len(gt_timestamps)}")

    # Extract clips
    if detections:
        os.makedirs(clip_dir, exist_ok=True)
        print(f"\nExtracting clips to {clip_dir}/")
        for i, d in enumerate(detections):
            clip_path = os.path.join(clip_dir, f"delivery_{i+1}_{d['time']:.0f}s.mp4")
            n_frames, clip_fps = extract_clip(video_path, d["time"], before=1.0, after=1.5, output_path=clip_path)
            size_kb = os.path.getsize(clip_path) / 1024
            print(f"  Clip {i+1}: {clip_path} ({n_frames} frames @ {clip_fps}fps, {size_kb:.0f}KB)")

    # Save
    result = {
        "video": os.path.basename(video_path),
        "fps": fps, "duration": duration,
        "model": MODEL, "poll_interval": interval,
        "ground_truth_frames": gt_frames,
        "ground_truth_timestamps": gt_timestamps,
        "detections": detections,
        "total_tokens": total_tokens,
        "elapsed": round(elapsed, 1),
    }
    result_path = os.path.join(SCRIPT_DIR, "result_live_detection.json")
    with open(result_path, "w") as f:
        json.dump(result, f, indent=2)
    print(f"\nSaved: {result_path}")


if __name__ == "__main__":
    main()
