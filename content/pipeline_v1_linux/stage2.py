#!/usr/bin/env python3
"""Stage 2: Bowler Isolation — SAM 2 on CPU."""
import json
import sys
import time
from math import floor
from pathlib import Path

import cv2
import numpy as np


def run(run_root: str, clip_path: str):
    root = Path(run_root)
    stage_dir = root / "stage2"
    masks_dir = stage_dir / "masks"
    frames_dir = stage_dir / "frames"
    stage_dir.mkdir(parents=True, exist_ok=True)
    masks_dir.mkdir(exist_ok=True)
    frames_dir.mkdir(exist_ok=True)

    # Load Stage 0 + Stage 1 outputs
    meta = json.loads((root / "stage0" / "clip_metadata.json").read_text())
    scene = json.loads((root / "stage1" / "scene_report.json").read_text())

    W, H = meta["width"], meta["height"]
    fps = meta["fps"]
    fc = meta["frame_count"]

    # Extract all frames as JPEG for SAM 2
    print(f"Extracting {fc} frames...")
    cap = cv2.VideoCapture(str(Path(clip_path).resolve()))
    idx = 0
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        cv2.imwrite(str(frames_dir / f"{idx:06d}.jpg"), frame)
        idx += 1
    cap.release()
    print(f"  {idx} frames extracted")

    # Get prompt from Stage 1
    prompt_time = scene.get("best_prompt_frame", 1.0)
    prompt_point = scene.get("best_prompt_point", [0.5, 0.5])
    prompt_bbox = scene.get("best_prompt_bbox")
    prompt_frame_idx = min(floor(prompt_time * fps + 1e-6), idx - 1)

    print(f"  Prompt frame: {prompt_frame_idx} (t={prompt_time}s)")
    print(f"  Prompt point: ({prompt_point[0]:.2f}, {prompt_point[1]:.2f})")
    if prompt_bbox:
        print(f"  Prompt bbox: {prompt_bbox}")

    # Import SAM 2
    import torch
    from sam2.build_sam import build_sam2_video_predictor

    device = torch.device("cpu")
    ckpt = Path("resources/sam2_checkpoints/sam2.1_hiera_tiny.pt")
    cfg = "configs/sam2.1/sam2.1_hiera_t.yaml"

    assert ckpt.exists(), f"SAM 2 checkpoint not found: {ckpt}"
    print(f"  Loading SAM 2 tiny on CPU...")
    t0 = time.time()

    predictor = build_sam2_video_predictor(cfg, str(ckpt), device=device)
    state = predictor.init_state(video_path=str(frames_dir))
    print(f"  SAM 2 loaded ({time.time()-t0:.1f}s)")

    # Add prompt
    if prompt_bbox:
        box = np.array([
            prompt_bbox[0] * W, prompt_bbox[1] * H,
            prompt_bbox[2] * W, prompt_bbox[3] * H,
        ], dtype=np.float32)
        print(f"  Using bbox prompt: {box}")
        predictor.add_new_points_or_box(
            inference_state=state,
            frame_idx=prompt_frame_idx,
            obj_id=1,
            box=box,
        )
    else:
        px = np.array([[prompt_point[0] * W, prompt_point[1] * H]], dtype=np.float32)
        print(f"  Using point prompt: {px}")
        predictor.add_new_points_or_box(
            inference_state=state,
            frame_idx=prompt_frame_idx,
            obj_id=1,
            points=px,
            labels=np.array([1], dtype=np.int32),
        )

    # Propagate masks
    print(f"  Propagating masks through {idx} frames (this takes a while on CPU)...")
    t0 = time.time()
    mask_data = {}
    for frame_idx, obj_ids, mask_logits in predictor.propagate_in_video(state):
        mask = (mask_logits[0] > 0.0).cpu().numpy().squeeze().astype(np.uint8) * 255
        if mask.shape != (H, W):
            mask = cv2.resize(mask, (W, H), interpolation=cv2.INTER_NEAREST)
        mask_data[frame_idx] = mask
        if frame_idx % 20 == 0:
            elapsed = time.time() - t0
            rate = (frame_idx + 1) / elapsed if elapsed > 0 else 0
            print(f"    Frame {frame_idx}/{idx} ({rate:.1f} frames/s)")

    elapsed = time.time() - t0
    print(f"  Masks generated in {elapsed:.0f}s ({idx/elapsed:.1f} frames/s)")

    # Save masks
    areas = []
    centroids = []
    for i in range(idx):
        mask = mask_data.get(i, np.zeros((H, W), dtype=np.uint8))
        cv2.imwrite(str(masks_dir / f"{i:06d}.png"), mask)
        area = int(np.sum(mask > 0))
        areas.append(area)
        if area > 0:
            ys, xs = np.where(mask > 0)
            cx, cy = float(np.mean(xs)) / W, float(np.mean(ys)) / H
        else:
            cx, cy = 0.0, 0.0
        centroids.append({"frame": i, "x": round(cx, 4), "y": round(cy, 4), "area": area})

    # Save preview (bowler on green screen)
    print("  Generating preview...")
    cap = cv2.VideoCapture(str(Path(clip_path).resolve()))
    fourcc = cv2.VideoWriter_fourcc(*"mp4v")
    preview = cv2.VideoWriter(str(stage_dir / "preview.mp4"), fourcc, fps, (W, H))
    for i in range(idx):
        ok, frame = cap.read()
        if not ok:
            break
        mask = mask_data.get(i, np.zeros((H, W), dtype=np.uint8))
        green = np.zeros_like(frame)
        green[:] = (0, 255, 0)  # green screen
        mask_3ch = mask[:, :, None] / 255.0
        composited = (frame * mask_3ch + green * (1 - mask_3ch)).astype(np.uint8)
        preview.write(composited)
    cap.release()
    preview.release()

    # Metrics
    masked_count = sum(1 for a in areas if a > 500)
    empty_count = sum(1 for a in areas if a <= 500)
    max_consec_empty = 0
    consec = 0
    for a in areas:
        if a <= 500:
            consec += 1
            max_consec_empty = max(max_consec_empty, consec)
        else:
            consec = 0

    metrics = {
        "frames_total": idx,
        "frames_masked": masked_count,
        "frames_empty": empty_count,
        "mask_coverage": round(masked_count / idx, 3) if idx > 0 else 0,
        "avg_area_px": round(np.mean([a for a in areas if a > 500]), 0) if masked_count > 0 else 0,
        "min_area_px": min([a for a in areas if a > 500]) if masked_count > 0 else 0,
        "max_area_px": max(areas),
        "max_consecutive_empty": max_consec_empty,
        "sam2_model": "sam2.1_hiera_tiny",
        "device": "cpu",
        "processing_time_s": round(elapsed, 1),
        "prompt": {
            "frame_idx": prompt_frame_idx,
            "time_s": prompt_time,
            "type": "bbox" if prompt_bbox else "point",
        },
    }

    with open(stage_dir / "metrics.json", "w") as f:
        json.dump(metrics, f, indent=2)

    with open(stage_dir / "centroids.json", "w") as f:
        json.dump(centroids, f, indent=2)

    print(f"\nStage 2 {'PASSED' if metrics['mask_coverage'] >= 0.5 else 'DEGRADED'}")
    print(f"  Masked: {masked_count}/{idx} ({metrics['mask_coverage']*100:.0f}%)")
    print(f"  Avg area: {metrics['avg_area_px']} px")
    print(f"  Max consecutive empty: {max_consec_empty}")
    print(f"  Processing time: {elapsed:.0f}s")
    print(f"  Preview: {stage_dir}/preview.mp4")

    return metrics


if __name__ == "__main__":
    clip = sys.argv[1] if len(sys.argv) > 1 else "resources/samples/3_sec_1_delivery_nets.mp4"
    run_root = sys.argv[2] if len(sys.argv) > 2 else "content/pipeline_v1_linux/runs/test_run"
    run(run_root, clip)
