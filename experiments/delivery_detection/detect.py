"""
Delivery Detection Experiment Runner
=====================================
Usage:
  python detect.py <video_path> [--ground-truth FRAME] [--runs N] [--config A|B|C|D] [--inline]

Examples:
  python detect.py ../../resources/samples/clip1.mp4 -g 30 -r 3 --config A
  python detect.py ../../resources/samples/clip2.mp4 -g 45,120 -r 5 --config C
"""

import argparse
import json
import time
import statistics
import os
import sys
import tempfile
import base64
import urllib.request

# google.genai SDK for File API upload/delete (REST API for inference)
from google import genai

from configs import CONFIGS, prompt_with_metadata

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(SCRIPT_DIR, ".."))
from shared_config import SCOUT_MODEL as MODEL, FILE_SIZE_THRESHOLD_MB, load_api_key


def get_video_info(video_path):
    try:
        import cv2
        cap = cv2.VideoCapture(video_path)
        fps = cap.get(cv2.CAP_PROP_FPS)
        total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
        width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
        height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
        cap.release()
        return fps, total_frames, width, height
    except ImportError:
        return 30.0, 0, 0, 0


def downscale_video(video_path, target_height):
    import cv2
    cap = cv2.VideoCapture(video_path)
    fps = cap.get(cv2.CAP_PROP_FPS)
    w = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    h = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    if h <= target_height:
        cap.release()
        return video_path
    scale = target_height / h
    new_w = int(w * scale) // 2 * 2
    new_h = target_height // 2 * 2
    tmp = tempfile.NamedTemporaryFile(suffix=".mp4", delete=False)
    tmp_path = tmp.name
    tmp.close()
    fourcc = cv2.VideoWriter_fourcc(*"mp4v")
    out = cv2.VideoWriter(tmp_path, fourcc, fps, (new_w, new_h))
    while True:
        ret, frame = cap.read()
        if not ret:
            break
        out.write(cv2.resize(frame, (new_w, new_h)))
    cap.release()
    out.release()
    return tmp_path


_genai_client = None

def _get_client(api_key):
    global _genai_client
    if _genai_client is None:
        _genai_client = genai.Client(api_key=api_key)
    return _genai_client

def upload_video(video_path, api_key):
    client = _get_client(api_key)
    uploaded = client.files.upload(file=video_path, config={"mime_type": "video/mp4"})
    start = time.time()
    while uploaded.state.name == "PROCESSING":
        if time.time() - start > 120:
            raise Exception("File processing timeout (120s)")
        time.sleep(2)
        uploaded = client.files.get(name=uploaded.name)
    if uploaded.state.name != "ACTIVE":
        raise Exception(f"File processing failed: {uploaded.state.name}")
    return uploaded


def call_gemini_rest(api_key, prompt, config, video_b64=None, file_uri=None):
    """Call Gemini via REST API — supports thinkingConfig unlike the deprecated SDK."""
    url = f"https://generativelanguage.googleapis.com/v1beta/models/{MODEL}:generateContent?key={api_key}"

    gen_config = {
        "temperature": config["temperature"],
        "responseMimeType": "application/json",
    }
    thinking = config.get("thinking")
    if thinking:
        gen_config["thinkingConfig"] = {"thinkingLevel": thinking}
    if config.get("response_schema"):
        gen_config["responseSchema"] = config["response_schema"]

    # Build content parts
    if file_uri:
        video_part = {"fileData": {"mimeType": "video/mp4", "fileUri": file_uri}}
    else:
        video_part = {"inlineData": {"mimeType": "video/mp4", "data": video_b64}}

    payload = {
        "contents": [{"parts": [video_part, {"text": prompt}]}],
        "generationConfig": gen_config,
    }

    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=300) as resp:
        return json.loads(resp.read().decode("utf-8"))


def parse_response(response):
    parts = response["candidates"][0]["content"]["parts"]
    text = next(p["text"] for p in parts if "text" in p)
    data = json.loads(text)
    if isinstance(data, list):
        data = data[0] if data else {}
    usage = response.get("usageMetadata", {})
    return data, {
        "prompt": usage.get("promptTokenCount", 0),
        "output": usage.get("candidatesTokenCount", 0),
        "thought": usage.get("thoughtsTokenCount", 0),
        "total": usage.get("totalTokenCount", 0),
    }


def extract_timestamps(data):
    ts = data.get("deliveries_detected_at_time", [])
    if ts:
        return ts
    deliveries = data.get("deliveries", [])
    if deliveries:
        return [d.get("timestamp", d.get("release_ts", 0)) for d in deliveries]
    return []


def main():
    parser = argparse.ArgumentParser(description="Delivery detection experiment")
    parser.add_argument("video", help="Path to video file")
    parser.add_argument("--ground-truth", "-g", help="Ground truth release frame(s), comma-separated")
    parser.add_argument("--runs", "-r", type=int, default=5, help="Number of runs (default: 5)")
    parser.add_argument("--config", "-c", default="A", choices=CONFIGS.keys(), help="Config to use")
    parser.add_argument("--inline", action="store_true", help="Force inline mode")
    parser.add_argument("--threshold", type=float, default=0.3, help="PASS threshold in seconds")
    args = parser.parse_args()

    video_path = os.path.abspath(args.video)
    api_key = load_api_key()
    config = CONFIGS[args.config].copy()

    fps, total_frames, width, height = get_video_info(video_path)
    duration = total_frames / fps if fps else 0

    # Ground truth
    gt_frames = []
    gt_timestamps = []
    if args.ground_truth:
        gt_frames = [int(x.strip()) for x in args.ground_truth.split(",")]
        gt_timestamps = [f / fps for f in gt_frames]

    # Resolve prompt
    if config["prompt"] == "METADATA":
        prompt = prompt_with_metadata(fps, duration, total_frames)
    else:
        prompt = config["prompt"]

    # Preprocessing
    actual_video = video_path
    preprocessed = False
    if config.get("downscale"):
        print(f"Downscaling to {config['downscale']}p... ", end="", flush=True)
        actual_video = downscale_video(video_path, config["downscale"])
        preprocessed = actual_video != video_path
        if preprocessed:
            new_size = os.path.getsize(actual_video) / (1024 * 1024)
            print(f"done ({new_size:.1f}MB)")
        else:
            print("skipped (already small)")

    # File API vs inline
    size_mb = os.path.getsize(actual_video) / (1024 * 1024)
    use_file_api = not args.inline and size_mb > FILE_SIZE_THRESHOLD_MB

    name = os.path.basename(video_path)
    mode = "File API" if use_file_api else "Inline"
    print(f"Video: {name} ({fps}fps, {total_frames} frames, {width}x{height})")
    print(f"Config {args.config}: {config['name']} | Temp: {config['temperature']}, Mode: {mode}, Thinking: {config.get('thinking', 'MINIMAL')}")
    if gt_timestamps:
        print(f"Ground truth: frames {gt_frames} = {[f'{t:.3f}s' for t in gt_timestamps]}")
    print()

    # Prepare video data
    uploaded_file = None
    video_b64 = None
    file_uri = None

    if use_file_api:
        print("Uploading via File API... ", end="", flush=True)
        uploaded_file = upload_video(actual_video, api_key)
        file_uri = uploaded_file.uri
        print(f"ACTIVE")
    else:
        with open(actual_video, "rb") as f:
            video_b64 = base64.b64encode(f.read()).decode("utf-8")

    # Run experiments
    results = []
    for i in range(args.runs):
        print(f"Run {i+1}/{args.runs}... ", end="", flush=True)
        start = time.time()
        try:
            resp = call_gemini_rest(api_key, prompt, config, video_b64=video_b64, file_uri=file_uri)
            data, tokens = parse_response(resp)
            elapsed = time.time() - start
            timestamps = extract_timestamps(data)

            print(f"ts={timestamps}, count={data.get('total_count', len(timestamps))}, "
                  f"latency={elapsed:.1f}s, tokens={tokens['total']}")

            results.append({
                "run": i + 1,
                "timestamps": timestamps,
                "confirmed": data.get("total_count", len(timestamps)),
                "tokens": tokens,
                "latency": round(elapsed, 2),
            })
        except Exception as e:
            print(f"ERROR: {e}")
            results.append({"run": i + 1, "error": str(e)})

        if i < args.runs - 1:
            time.sleep(1)

    # Cleanup
    if uploaded_file:
        try:
            _get_client(api_key).files.delete(name=uploaded_file.name)
        except Exception:
            pass
    if preprocessed:
        os.unlink(actual_video)

    # Analysis
    print(f"\n{'='*50}")
    print(f"ANALYSIS — Config {args.config}: {config['name']}")
    print(f"{'='*50}")

    threshold = args.threshold
    valid = [r for r in results if "latency" in r]

    if gt_timestamps:
        pass_count = 0
        total_count = len(gt_timestamps)
        for gi, gt in enumerate(gt_timestamps):
            matched = []
            for r in valid:
                ts_list = r.get("timestamps", [])
                if ts_list:
                    nearest = min(ts_list, key=lambda t: abs(t - gt))
                    matched.append(nearest)
            if matched:
                mean_ts = statistics.mean(matched)
                delta = abs(mean_ts - gt)
                spread = max(matched) - min(matched)
                passed = delta <= threshold
                if passed:
                    pass_count += 1
                print(f"\nD{gi+1} (GT: {gt:.3f}s): mean={mean_ts:.3f}s, delta={delta:.3f}s, "
                      f"spread={spread:.2f}s -> {'PASS' if passed else 'FAIL'}")

        # Phantoms
        for r in valid:
            ts_list = r.get("timestamps", [])
            phantoms = [t for t in ts_list
                        if min(abs(t - g) for g in gt_timestamps) > 1.0]
            if phantoms:
                print(f"  Phantoms run {r['run']}: {phantoms}")

        print(f"\nScore: {pass_count}/{total_count} PASS (threshold: {threshold}s)")
    else:
        all_ts = [r["timestamps"] for r in valid if "timestamps" in r]
        if all_ts:
            for di in range(max(len(t) for t in all_ts)):
                vals = [t[di] for t in all_ts if di < len(t)]
                if vals:
                    print(f"\nD{di+1}: {vals}, mean={statistics.mean(vals):.3f}s, spread={max(vals)-min(vals):.2f}s")

    if valid:
        latencies = [r["latency"] for r in valid]
        tok_totals = [r["tokens"]["total"] for r in valid]
        print(f"\nLatency: {statistics.mean(latencies):.1f}s avg ({min(latencies):.1f}-{max(latencies):.1f}s)")
        print(f"Tokens: {statistics.mean(tok_totals):.0f} avg ({min(tok_totals)}-{max(tok_totals)})")

    counts = [r.get("confirmed", 0) for r in valid]
    if counts:
        print(f"Count: {counts} (consistent: {len(set(counts)) == 1})")

    # Save
    out_name = os.path.splitext(os.path.basename(video_path))[0]
    out_path = os.path.join(SCRIPT_DIR, f"result_{args.config}_{out_name}.json")
    with open(out_path, "w") as f:
        json.dump({
            "video": name, "fps": fps, "frames": total_frames,
            "ground_truth_frames": gt_frames, "ground_truth_ts": gt_timestamps,
            "config": args.config, "config_name": config["name"],
            "temperature": config["temperature"],
            "thinking": config.get("thinking", "MINIMAL"),
            "runs": args.runs, "model": MODEL, "mode": mode,
            "downscale": config.get("downscale"),
            "results": results,
        }, f, indent=2)
    print(f"\nSaved: {out_path}")


if __name__ == "__main__":
    main()
