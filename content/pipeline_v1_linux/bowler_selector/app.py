#!/usr/bin/env python3
"""Bowler Selector — Click on the bowler, SAM 2 tracks them.

Usage:
    python app.py <video.mp4>
    Open http://localhost:8765 in browser
    Click on the bowler → SAM 2 isolates them
"""
import base64
import json
import sys
import time
from http.server import HTTPServer, SimpleHTTPRequestHandler
from io import BytesIO
from pathlib import Path
from threading import Thread
from urllib.parse import parse_qs, urlparse

import cv2
import numpy as np

SCRIPT_DIR = Path(__file__).resolve().parent
VIDEO_PATH = None
FRAMES = []
MASKS = {}
W, H, FPS, FC = 0, 0, 0, 0
SAM_READY = False
PREDICTOR = None
STATE = None


def extract_frames(video_path):
    global FRAMES, W, H, FPS, FC
    cap = cv2.VideoCapture(str(video_path))
    W = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    H = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    FPS = cap.get(cv2.CAP_PROP_FPS)
    FC = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    FRAMES.clear()
    while True:
        ok, f = cap.read()
        if not ok:
            break
        FRAMES.append(f)
    cap.release()
    print(f"Loaded {len(FRAMES)} frames ({W}x{H} @ {FPS}fps)")


def init_sam2(frames_dir):
    global PREDICTOR, STATE, SAM_READY
    import torch
    from sam2.build_sam import build_sam2_video_predictor

    repo_root = SCRIPT_DIR.parents[2]
    ckpt = repo_root / "resources" / "sam2_checkpoints" / "sam2.1_hiera_large.pt"
    if not ckpt.exists():
        ckpt = repo_root / "resources" / "sam2_checkpoints" / "sam2.1_hiera_tiny.pt"
    cfg = "configs/sam2.1/sam2.1_hiera_l.yaml" if "large" in ckpt.name else "configs/sam2.1/sam2.1_hiera_t.yaml"

    print(f"Loading SAM 2 ({ckpt.name}) on CPU...")
    device = torch.device("cpu")
    PREDICTOR = build_sam2_video_predictor(cfg, str(ckpt), device=device)
    STATE = PREDICTOR.init_state(video_path=str(frames_dir))
    SAM_READY = True
    print("SAM 2 ready!")


HTML = """<!DOCTYPE html>
<html>
<head>
<title>Bowler Selector — wellBowled.ai</title>
<style>
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body { background: #0d1117; color: #fff; font-family: -apple-system, sans-serif; }
  .header { padding: 16px 24px; display: flex; align-items: center; gap: 16px; border-bottom: 1px solid #1a1f2b; }
  .header h1 { font-size: 18px; color: #006d77; }
  .header .status { font-size: 14px; color: #8b949e; }
  .main { display: flex; padding: 16px; gap: 16px; }
  .video-panel { flex: 1; }
  .controls { width: 300px; }
  canvas { cursor: crosshair; border: 2px solid #30363d; border-radius: 8px; }
  .btn { padding: 10px 20px; border: none; border-radius: 8px; font-size: 14px; cursor: pointer; width: 100%; margin-bottom: 8px; }
  .btn-primary { background: #006d77; color: #fff; }
  .btn-primary:hover { background: #008a96; }
  .btn-danger { background: #da3633; color: #fff; }
  .btn-secondary { background: #21262d; color: #c9d1d9; border: 1px solid #30363d; }
  .info { background: #161b22; border: 1px solid #30363d; border-radius: 8px; padding: 12px; margin-bottom: 12px; font-size: 13px; }
  .info label { color: #8b949e; display: block; margin-bottom: 4px; }
  .info span { color: #c9d1d9; }
  .slider-row { display: flex; align-items: center; gap: 8px; margin-bottom: 12px; }
  .slider-row input { flex: 1; }
  .slider-row span { font-size: 13px; min-width: 50px; text-align: right; }
  .clicks-list { max-height: 200px; overflow-y: auto; }
  .click-item { display: flex; justify-content: space-between; padding: 4px 8px; background: #161b22; border-radius: 4px; margin-bottom: 4px; font-size: 12px; }
  .click-pos { color: #58a6ff; }
  .click-neg { color: #f85149; }
  #progress { display: none; background: #161b22; border: 1px solid #30363d; border-radius: 8px; padding: 16px; margin-top: 12px; text-align: center; }
  #progress .bar { height: 6px; background: #30363d; border-radius: 3px; margin-top: 8px; }
  #progress .bar-fill { height: 100%; background: #006d77; border-radius: 3px; transition: width 0.3s; }
  .overlay-toggle { display: flex; gap: 8px; margin-bottom: 12px; }
  .overlay-toggle label { font-size: 13px; cursor: pointer; }
</style>
</head>
<body>
<div class="header">
  <h1>wellBowled.ai</h1>
  <div class="status" id="samStatus">Loading SAM 2...</div>
</div>
<div class="main">
  <div class="video-panel">
    <canvas id="canvas" width="0" height="0"></canvas>
    <div class="slider-row" style="margin-top:8px">
      <span style="font-size:12px">Frame</span>
      <input type="range" id="frameSlider" min="0" max="0" value="0">
      <span id="frameNum" style="font-size:12px">0/0</span>
    </div>
  </div>
  <div class="controls">
    <div class="info">
      <label>Video</label>
      <span id="videoInfo">Loading...</span>
    </div>
    <div class="info">
      <label>Instructions</label>
      <span>1. Scrub to a frame where bowler is clearly visible<br>
      2. LEFT click on the bowler (green = include)<br>
      3. RIGHT click to exclude areas (red = exclude)<br>
      4. Click "Track Bowler" to propagate</span>
    </div>
    <div class="overlay-toggle">
      <input type="checkbox" id="showMask" checked>
      <label for="showMask">Show mask overlay</label>
    </div>
    <div class="info">
      <label>Clicks on frame <span id="clickFrame">0</span></label>
      <div class="clicks-list" id="clicksList"></div>
    </div>
    <button class="btn btn-primary" id="trackBtn" disabled onclick="trackBowler()">Track Bowler</button>
    <button class="btn btn-danger" onclick="clearClicks()">Clear Clicks</button>
    <button class="btn btn-secondary" onclick="saveMasks()">Save Masks & Continue</button>
    <div id="progress">
      <div>Tracking... <span id="progressPct">0%</span></div>
      <div class="bar"><div class="bar-fill" id="progressBar" style="width:0%"></div></div>
    </div>
  </div>
</div>
<script>
const canvas = document.getElementById('canvas');
const ctx = canvas.getContext('2d');
const slider = document.getElementById('frameSlider');
const frameNum = document.getElementById('frameNum');
let frames = [];
let masks = {};
let clicks = {};  // {frame_idx: [{x, y, label}]}
let currentFrame = 0;
let showMask = true;

document.getElementById('showMask').addEventListener('change', e => {
  showMask = e.target.checked;
  drawFrame(currentFrame);
});

// Load frames
fetch('/api/info').then(r => r.json()).then(info => {
  document.getElementById('videoInfo').textContent =
    `${info.width}x${info.height} @ ${info.fps}fps, ${info.frame_count} frames`;
  slider.max = info.frame_count - 1;
  frameNum.textContent = `0/${info.frame_count}`;
  canvas.width = info.width;
  canvas.height = info.height;
  loadFrame(0);
});

// Check SAM status
function checkSam() {
  fetch('/api/sam_status').then(r => r.json()).then(d => {
    document.getElementById('samStatus').textContent = d.ready ? 'SAM 2 Ready ✓' : 'Loading SAM 2...';
    document.getElementById('trackBtn').disabled = !d.ready;
    if (!d.ready) setTimeout(checkSam, 2000);
  });
}
checkSam();

function loadFrame(idx) {
  const img = new Image();
  img.onload = () => {
    frames[idx] = img;
    drawFrame(idx);
  };
  img.src = `/api/frame/${idx}`;
}

function drawFrame(idx) {
  currentFrame = idx;
  if (!frames[idx]) { loadFrame(idx); return; }
  ctx.drawImage(frames[idx], 0, 0);

  // Draw mask overlay
  if (showMask && masks[idx]) {
    const maskImg = new Image();
    maskImg.onload = () => {
      ctx.globalAlpha = 0.4;
      ctx.drawImage(maskImg, 0, 0);
      ctx.globalAlpha = 1.0;
      drawClicks(idx);
    };
    maskImg.src = masks[idx];
  } else {
    drawClicks(idx);
  }
  document.getElementById('clickFrame').textContent = idx;
}

function drawClicks(idx) {
  (clicks[idx] || []).forEach(c => {
    ctx.beginPath();
    ctx.arc(c.x, c.y, 8, 0, Math.PI * 2);
    ctx.fillStyle = c.label === 1 ? '#00ff88' : '#ff4444';
    ctx.fill();
    ctx.strokeStyle = '#fff';
    ctx.lineWidth = 2;
    ctx.stroke();
  });
}

slider.addEventListener('input', e => {
  const idx = parseInt(e.target.value);
  frameNum.textContent = `${idx}/${slider.max}`;
  loadFrame(idx);
});

canvas.addEventListener('click', e => {
  if (!document.getElementById('trackBtn').disabled === false && !SAM_READY) return;
  const rect = canvas.getBoundingClientRect();
  const scaleX = canvas.width / rect.width;
  const scaleY = canvas.height / rect.height;
  const x = Math.round((e.clientX - rect.left) * scaleX);
  const y = Math.round((e.clientY - rect.top) * scaleY);
  addClick(currentFrame, x, y, 1);
});

canvas.addEventListener('contextmenu', e => {
  e.preventDefault();
  const rect = canvas.getBoundingClientRect();
  const scaleX = canvas.width / rect.width;
  const scaleY = canvas.height / rect.height;
  const x = Math.round((e.clientX - rect.left) * scaleX);
  const y = Math.round((e.clientY - rect.top) * scaleY);
  addClick(currentFrame, x, y, 0);
});

function addClick(frame, x, y, label) {
  if (!clicks[frame]) clicks[frame] = [];
  clicks[frame].push({x, y, label});
  drawFrame(frame);
  updateClicksList();
}

function updateClicksList() {
  const list = document.getElementById('clicksList');
  const frameClicks = clicks[currentFrame] || [];
  list.innerHTML = frameClicks.map((c, i) =>
    `<div class="click-item">
      <span class="${c.label ? 'click-pos' : 'click-neg'}">${c.label ? '+ Include' : '- Exclude'}</span>
      <span>(${c.x}, ${c.y})</span>
    </div>`
  ).join('');
}

function clearClicks() {
  clicks = {};
  masks = {};
  drawFrame(currentFrame);
  updateClicksList();
}

function trackBowler() {
  const allClicks = {};
  Object.entries(clicks).forEach(([frame, pts]) => {
    allClicks[frame] = pts;
  });
  if (Object.keys(allClicks).length === 0) {
    alert('Click on the bowler first!');
    return;
  }

  document.getElementById('progress').style.display = 'block';
  document.getElementById('progressPct').textContent = '0%';
  document.getElementById('progressBar').style.width = '0%';

  fetch('/api/track', {
    method: 'POST',
    headers: {'Content-Type': 'application/json'},
    body: JSON.stringify({clicks: allClicks})
  }).then(r => r.json()).then(d => {
    if (d.status === 'started') {
      pollProgress();
    }
  });
}

function pollProgress() {
  fetch('/api/progress').then(r => r.json()).then(d => {
    document.getElementById('progressPct').textContent = `${d.pct}%`;
    document.getElementById('progressBar').style.width = `${d.pct}%`;
    if (d.done) {
      document.getElementById('progress').style.display = 'none';
      // Load mask overlays
      for (let i = 0; i < parseInt(slider.max); i++) {
        masks[i] = `/api/mask/${i}`;
      }
      drawFrame(currentFrame);
    } else {
      setTimeout(pollProgress, 1000);
    }
  });
}

function saveMasks() {
  fetch('/api/save', {method: 'POST'}).then(r => r.json()).then(d => {
    alert(`Masks saved to ${d.path}. ${d.count} masks.`);
  });
}
</script>
</body>
</html>"""


class Handler(SimpleHTTPRequestHandler):
    def do_GET(self):
        parsed = urlparse(self.path)
        path = parsed.path

        if path == "/":
            self.send_response(200)
            self.send_header("Content-Type", "text/html")
            self.end_headers()
            self.wfile.write(HTML.encode())

        elif path == "/api/info":
            self.json_response({"width": W, "height": H, "fps": FPS, "frame_count": len(FRAMES)})

        elif path == "/api/sam_status":
            self.json_response({"ready": SAM_READY})

        elif path.startswith("/api/frame/"):
            idx = int(path.split("/")[-1])
            if 0 <= idx < len(FRAMES):
                _, buf = cv2.imencode(".jpg", FRAMES[idx], [cv2.IMWRITE_JPEG_QUALITY, 85])
                self.send_response(200)
                self.send_header("Content-Type", "image/jpeg")
                self.end_headers()
                self.wfile.write(buf.tobytes())
            else:
                self.send_error(404)

        elif path.startswith("/api/mask/"):
            idx = int(path.split("/")[-1])
            mask = MASKS.get(idx)
            if mask is not None:
                # Create colored overlay: green where mask is 255
                overlay = np.zeros((H, W, 3), dtype=np.uint8)
                overlay[mask > 0] = [0, 200, 100]
                _, buf = cv2.imencode(".png", overlay)
                self.send_response(200)
                self.send_header("Content-Type", "image/png")
                self.end_headers()
                self.wfile.write(buf.tobytes())
            else:
                self.send_error(404)

        elif path == "/api/progress":
            total = len(FRAMES)
            done = len(MASKS)
            self.json_response({"pct": int(done / total * 100) if total > 0 else 0, "done": done >= total - 1, "masked": done})

        else:
            self.send_error(404)

    def do_POST(self):
        parsed = urlparse(self.path)
        path = parsed.path

        if path == "/api/track":
            content_len = int(self.headers.get("Content-Length", 0))
            body = json.loads(self.rfile.read(content_len)) if content_len > 0 else {}
            clicks_data = body.get("clicks", {})

            # Run SAM 2 tracking in background thread
            Thread(target=run_tracking, args=(clicks_data,), daemon=True).start()
            self.json_response({"status": "started"})

        elif path == "/api/save":
            save_dir = SCRIPT_DIR / "output" / "masks"
            save_dir.mkdir(parents=True, exist_ok=True)
            count = 0
            for idx, mask in MASKS.items():
                cv2.imwrite(str(save_dir / f"{idx:06d}.png"), mask)
                count += 1
            self.json_response({"path": str(save_dir), "count": count})

        else:
            self.send_error(404)

    def json_response(self, data):
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps(data).encode())

    def log_message(self, format, *args):
        pass  # Suppress request logging


def run_tracking(clicks_data):
    import traceback
    global MASKS, STATE
    MASKS.clear()

    try:
        # Re-init state for fresh tracking
        frames_dir = SCRIPT_DIR / "output" / "frames"
        STATE = PREDICTOR.init_state(video_path=str(frames_dir))

        # Add all click prompts
        for frame_str, pts in clicks_data.items():
            frame_idx = int(frame_str)
            points = np.array([[p["x"], p["y"]] for p in pts], dtype=np.float32)
            labels = np.array([p["label"] for p in pts], dtype=np.int32)
            print(f"Adding {len(pts)} clicks on frame {frame_idx}")
            PREDICTOR.add_new_points_or_box(
                inference_state=STATE,
                frame_idx=frame_idx,
                obj_id=1,
                points=points,
                labels=labels,
            )

        # Propagate
        print("Propagating masks...")
        for fi, obj_ids, mask_logits in PREDICTOR.propagate_in_video(STATE):
            mask = (mask_logits[0] > 0.0).cpu().numpy().squeeze().astype(np.uint8) * 255
            if mask.shape != (H, W):
                mask = cv2.resize(mask, (W, H), interpolation=cv2.INTER_NEAREST)
            MASKS[fi] = mask

        print(f"Done! {len(MASKS)} masks generated")
    except Exception as e:
        print(f"TRACKING ERROR: {e}")
        traceback.print_exc()


def main():
    global VIDEO_PATH
    video = sys.argv[1] if len(sys.argv) > 1 else "resources/samples/3_sec_1_delivery_nets.mp4"
    VIDEO_PATH = Path(video).resolve()

    # Extract frames
    extract_frames(VIDEO_PATH)

    # Extract frames as JPEG for SAM 2
    frames_dir = SCRIPT_DIR / "output" / "frames"
    frames_dir.mkdir(parents=True, exist_ok=True)
    for i, f in enumerate(FRAMES):
        cv2.imwrite(str(frames_dir / f"{i:06d}.jpg"), f)

    # Init SAM 2 in background
    Thread(target=init_sam2, args=(frames_dir,), daemon=True).start()

    # Start server
    port = 8765
    server = HTTPServer(("0.0.0.0", port), Handler)
    print(f"\n  Open http://localhost:{port} in your browser")
    print(f"  Click on the bowler → Track → Save\n")
    server.serve_forever()


if __name__ == "__main__":
    main()
