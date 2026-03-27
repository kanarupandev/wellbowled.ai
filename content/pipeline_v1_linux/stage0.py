#!/usr/bin/env python3
"""Stage 0: Input Validation — verify clip, extract metadata, generate contact sheet."""
import hashlib
import json
import sys
from pathlib import Path

import cv2
import numpy as np


def sha256_file(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for ch in iter(lambda: f.read(65536), b""):
            h.update(ch)
    return f"sha256:{h.hexdigest()}"


def run(clip_path: str, run_root: str):
    clip = Path(clip_path).resolve()
    root = Path(run_root)
    root.mkdir(parents=True, exist_ok=True)
    (root / "stage0").mkdir(exist_ok=True)

    # Verify file
    assert clip.exists(), f"File not found: {clip}"
    cap = cv2.VideoCapture(str(clip))
    assert cap.isOpened(), f"Cannot decode: {clip}"

    w = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    h = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    fps = cap.get(cv2.CAP_PROP_FPS)
    fc = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    dur = fc / fps if fps > 0 else 0
    codec = int(cap.get(cv2.CAP_PROP_FOURCC))
    codec_str = "".join([chr((codec >> 8 * i) & 0xFF) for i in range(4)])

    # Validation gates
    assert 3.0 <= dur <= 60.0, f"Duration {dur:.1f}s outside 3-60s range"
    assert fps >= 15.0, f"FPS {fps} too low (min 15)"
    assert min(w, h) >= 240, f"Resolution {w}x{h} too low (min 240p)"
    assert fc >= 45, f"Frame count {fc} too low"

    # Generate contact sheet (6 frames evenly spaced)
    sheet_times = [dur * i / 5 for i in range(6)]
    tiles = []
    for ts in sheet_times:
        fidx = min(int(ts * fps), fc - 1)
        cap.set(cv2.CAP_PROP_POS_FRAMES, fidx)
        ok, frame = cap.read()
        if ok:
            tile = cv2.resize(frame, (320, int(320 * h / w)))
            tiles.append((round(ts, 3), tile))
    cap.release()

    # Compose contact sheet
    if tiles:
        tw, th = tiles[0][1].shape[1], tiles[0][1].shape[0]
        cols = 3
        rows = 2
        sheet = np.zeros((rows * th + 40, cols * tw, 3), dtype=np.uint8)
        sheet[:] = (20, 14, 10)
        for i, (ts, tile) in enumerate(tiles):
            r, c = i // cols, i % cols
            y = r * th + 40
            sheet[y:y+th, c*tw:(c+1)*tw] = tile
            # Timestamp label
            cv2.putText(sheet, f"F{i+1} {ts:.2f}s", (c*tw+8, y+20),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.5, (255, 255, 255), 1)
        cv2.imwrite(str(root / "stage0" / "contact_sheet.jpg"), sheet, [cv2.IMWRITE_JPEG_QUALITY, 85])

    # Save metadata
    src_hash = sha256_file(str(clip))
    metadata = {
        "source_path": str(clip),
        "source_hash": src_hash,
        "width": w,
        "height": h,
        "fps": round(fps, 2),
        "duration_seconds": round(dur, 3),
        "frame_count": fc,
        "codec": codec_str,
        "contact_sheet_frame_times_s": [t for t, _ in tiles],
    }
    with open(root / "stage0" / "clip_metadata.json", "w") as f:
        json.dump(metadata, f, indent=2)

    print(f"Stage 0 PASSED")
    print(f"  Source: {clip.name}")
    print(f"  Resolution: {w}x{h} @ {fps:.0f}fps")
    print(f"  Duration: {dur:.2f}s ({fc} frames)")
    print(f"  Hash: {src_hash[:20]}...")
    print(f"  Contact sheet: {root}/stage0/contact_sheet.jpg")

    return metadata


if __name__ == "__main__":
    clip = sys.argv[1] if len(sys.argv) > 1 else "resources/samples/steyn_sa_vs_eng_broadcast_5sec.mp4"
    run_root = sys.argv[2] if len(sys.argv) > 2 else "content/pipeline_v1_linux/runs/test_run"
    run(clip, run_root)
