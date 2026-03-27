#!/usr/bin/env python3
"""Pipeline v1 — Bowling Analysis Content Pipeline.

Spec: linux_content_pipeline_work/pipeline_v1/dev_spec.md

Usage:
    python pipeline.py <input.mp4> --technique speed_gradient
"""

import argparse
import colorsys
import hashlib
import json
import logging
import os
import shutil
import subprocess
import sys
import time
import uuid
from datetime import datetime, timezone
from math import floor, sqrt
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy.ndimage import median_filter as medfilt

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# CONSTANTS
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

PIPELINE_DIR = Path(__file__).resolve().parent
RESOURCES = PIPELINE_DIR.parent.parent / "resources"
SAM2_CKPT = RESOURCES / "sam2_checkpoints" / "sam2.1_hiera_large.pt"
SAM2_CFG = "configs/sam2.1/sam2.1_hiera_l.yaml"
MP_MODEL = RESOURCES / "pose_landmarker_heavy.task"

GEMINI_MODELS = ["gemini-3-pro-preview", "gemini-2.5-pro", "gemini-2.5-flash"]
RW, RH = 1080, 1920  # render canvas
RFPS = 30
BRAND = (0, 109, 119)       # #006D77
BG = (13, 17, 23)           # #0D1117
WHITE = (255, 255, 255)
GREY = (128, 128, 128)

POSE_CONNS = [
    (11, 12), (11, 13), (13, 15), (12, 14), (14, 16),
    (11, 23), (12, 24), (23, 24),
    (23, 25), (25, 27), (24, 26), (26, 28),
    (15, 17), (15, 19), (16, 18), (16, 20),
    (27, 29), (28, 30),
]

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# UTILITIES
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

def sha256_file(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for ch in iter(lambda: f.read(65536), b""):
            h.update(ch)
    return f"sha256:{h.hexdigest()}"


def sfidx(t, fps):
    """Source frame index from time in seconds."""
    return floor(t * fps + 1e-6)


def now_iso():
    return datetime.now(timezone.utc).isoformat()


def dist(a, b):
    return sqrt((a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2)


def midpt(a, b):
    return ((a[0] + b[0]) / 2.0, (a[1] + b[1]) / 2.0)


def torso_len(lm):
    """Torso length from landmarks (normalized coords)."""
    return dist(midpt(lm[11], lm[12]), midpt(lm[23], lm[24]))


def vel_color(v):
    """Velocity 0..1 → RGB: blue(cold) → red(hot)."""
    v = max(0.0, min(1.0, v))
    hue = 240.0 * (1.0 - v) / 360.0
    r, g, b = colorsys.hsv_to_rgb(hue, 1.0, 1.0)
    return (int(r * 255), int(g * 255), int(b * 255))


def save_json(p, d):
    Path(p).parent.mkdir(parents=True, exist_ok=True)
    with open(p, "w") as f:
        json.dump(d, f, indent=2)


def load_json(p):
    with open(p) as f:
        return json.load(f)


def get_font(size):
    for p in [
        "/System/Library/Fonts/Supplemental/Arial.ttf",
        "/System/Library/Fonts/Helvetica.ttc",
        "/Library/Fonts/Arial.ttf",
    ]:
        try:
            return ImageFont.truetype(p, size)
        except (IOError, OSError):
            continue
    return ImageFont.load_default()


def parse_gemini_json(text):
    text = text.strip()
    if text.startswith("```"):
        lines = text.split("\n")
        lines = [l for l in lines if not l.strip().startswith("```")]
        text = "\n".join(lines)
    return json.loads(text)


def make_manifest(run_id, stage, ver, src_path, src_hash, src_vid, **kw):
    return {
        "run_id": run_id,
        "stage_name": stage,
        "stage_version": ver,
        "status": kw.get("status", "success"),
        "source_path": str(src_path),
        "source_hash": src_hash,
        "canonical_timebase": "source_seconds",
        "source_video": src_vid,
        "coordinate_system": {
            "space": "normalized_xy", "origin": "top_left",
            "x_direction": "right", "y_direction": "down",
        },
        "inputs": kw.get("inputs", []),
        "shared_artifacts": kw.get("shared_artifacts", {}),
        "branch_artifacts": kw.get("branch_artifacts", {}),
        "error_artifacts": kw.get("error_artifacts", {}),
        "stage_payload_schema_id": kw.get("schema_id", ""),
        "confidence": kw.get("confidence", {"overall": 1.0, "notes": []}),
        "metrics": kw.get("metrics", {"global": {}, "branches": {}}),
        "validation": kw.get("validation", {
            "checks_run": [], "checks_passed": [], "checks_failed": [],
        }),
        "fallback": kw.get("fallback", {
            "was_used": False, "mode": "none", "reason": "",
        }),
        "optimization": kw.get("optimization", {
            "stage_objective": "", "stage_score": 0.0,
            "end_to_end_risk": "low", "tunables": [],
        }),
        "branches": kw.get("branches", []),
        "provenance": {
            "tool": "pipeline_v1",
            "tool_version": "1.0.0",
            "model": kw.get("model", ""),
            "runtime": "macos_apple_silicon_mps",
            "started_at": kw.get("started_at", now_iso()),
            "completed_at": now_iso(),
        },
    }


LOG_FMT = "%(asctime)s level=%(levelname)s run_id=%(run_id)s stage=%(stage)s branch_id=%(branch_id)s event=%(event)s message=%(message)s"


class StageAdapter(logging.LoggerAdapter):
    def process(self, msg, kwargs):
        extra = {**self.extra, **kwargs.pop("extra", {})}
        kwargs["extra"] = extra
        return msg, kwargs


def get_logger(stage, logs_dir, run_id):
    logger = logging.getLogger(f"pipeline.{stage}")
    logger.setLevel(logging.DEBUG)
    if not logger.handlers:
        fh = logging.FileHandler(logs_dir / f"{stage}.log")
        fh.setFormatter(logging.Formatter(LOG_FMT))
        logger.addHandler(fh)
        # also log to run.log
        rh = logging.FileHandler(logs_dir / "run.log")
        rh.setFormatter(logging.Formatter(LOG_FMT))
        logger.addHandler(rh)
    defaults = {"run_id": run_id, "stage": stage, "branch_id": "none", "event": "info"}
    return StageAdapter(logger, defaults)


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# STAGE 0: INPUT VALIDATION
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

def run_stage0(run_root, source_path, run_id, src_hash, log):
    sd = run_root / "stage0"; sd.mkdir(exist_ok=True)
    t0 = now_iso()
    log.info("Stage 0 start", extra={"event": "start"})

    cap = cv2.VideoCapture(str(source_path))
    w = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    h = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    fps = cap.get(cv2.CAP_PROP_FPS)
    fc = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    dur = round(fc / fps, 3) if fps > 0 else 0
    ci = int(cap.get(cv2.CAP_PROP_FOURCC))
    codec = "".join(chr((ci >> 8 * i) & 0xFF) for i in range(4))

    sv = {"width": w, "height": h, "fps": fps, "duration_seconds": dur,
          "frame_count": fc, "codec": codec}

    # contact sheet — 8 evenly spaced
    n = 8
    times = [round(dur * i / (n - 1), 3) for i in range(n)]
    frames = []
    for t in times:
        cap.set(cv2.CAP_PROP_POS_FRAMES, sfidx(t, fps))
        ok, fr = cap.read()
        if ok:
            frames.append(fr)
    cap.release()

    if frames:
        tw, th = 320, int(320 * h / w) if w else 180
        sheet = np.zeros((2 * th, 4 * tw, 3), np.uint8)
        for i, fr in enumerate(frames[:8]):
            r, c = divmod(i, 4)
            sheet[r * th:(r + 1) * th, c * tw:(c + 1) * tw] = cv2.resize(fr, (tw, th))
        cv2.imwrite(str(sd / "contact_sheet.jpg"), sheet)

    meta = {"source_path": str(source_path), "source_hash": src_hash,
            **sv, "contact_sheet_frame_times_s": times}
    save_json(sd / "clip_metadata.json", meta)

    # validate
    cr, cp, cf = [], [], []
    for name, ok in [
        ("decode_ok", len(frames) > 0),
        ("duration", 3.0 <= dur <= 60.0),
        ("fps", fps >= 15.0),
        ("resolution", min(w, h) >= 240),
        ("frame_count", fc >= 45),
    ]:
        cr.append(name)
        (cp if ok else cf).append(name)

    status = "success" if not cf else "failed"
    save_json(sd / "manifest.json", make_manifest(
        run_id, "stage0", "1.0.0", source_path, src_hash, sv,
        status=status, started_at=t0,
        validation={"checks_run": cr, "checks_passed": cp, "checks_failed": cf},
        shared_artifacts={"clip_metadata": "stage0/clip_metadata.json",
                          "contact_sheet": "stage0/contact_sheet.jpg"}))

    if cf:
        raise RuntimeError(f"Stage 0 failed: {cf}")
    log.info(f"Stage 0 done: {w}x{h} {fps}fps {fc}f {dur}s", extra={"event": "done"})
    return sv


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# STAGE 1: SCENE UNDERSTANDING (Gemini)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

def run_stage1(run_root, sv, run_id, src_hash, source_path, log):
    sd = run_root / "stage1"; sd.mkdir(exist_ok=True)
    t0 = now_iso()
    log.info("Stage 1 start", extra={"event": "start"})

    cs_img = Image.open(run_root / "stage0" / "contact_sheet.jpg")
    meta = load_json(run_root / "stage0" / "clip_metadata.json")
    times = meta["contact_sheet_frame_times_s"]

    prompt = f"""You are analyzing a cricket bowling video clip. This contact sheet shows 8 evenly-spaced frames.

Clip: {sv['duration_seconds']}s at {sv['fps']}fps, {sv['width']}x{sv['height']}.
Frame times (seconds): {times}

Analyze the bowling action and respond with ONLY valid JSON (no markdown, no code fences):

{{
  "bowler_id": "bowler name if recognizable, else unknown",
  "bowling_arm": "right or left",
  "bowler_center_points": [
    {{"frame_time_s": 0.0, "x": 0.5, "y": 0.5}}
  ],
  "bowler_bounding_box": {{
    "frame_time_s": 0.0,
    "x1": 0.0, "y1": 0.0, "x2": 0.0, "y2": 0.0
  }},
  "timestamps_s": {{
    "run_up_start": 0.0,
    "back_foot_contact": 0.0,
    "front_foot_contact": 0.0,
    "release": 0.0,
    "follow_through": 0.0
  }},
  "camera_angle": "behind | side-on | front-on | elevated | mixed",
  "clip_quality": 7,
  "people_count": 1,
  "recommended_techniques": ["speed_gradient"],
  "stage1_confidence": 0.8
}}

Rules:
- bowler_center_points: one entry per contact sheet frame showing bowler torso center in normalized [0,1] coords (origin top-left)
- bowler_bounding_box: tight box around the bowler in the frame where they are LARGEST and most visible. x1,y1=top-left corner, x2,y2=bottom-right corner, all normalized [0,1]. Pick the frame where the bowler is closest to camera / biggest.
- Timestamps in seconds from clip start. Must be ordered: run_up_start < back_foot_contact < front_foot_contact <= release < follow_through <= {sv['duration_seconds']}
- clip_quality: 1=unusable 10=perfect broadcast
- recommended_techniques from: speed_gradient, xfactor, kinogram, arm_arc, goniogram
- Respond with JSON only"""

    from google import genai
    api_key = os.environ.get("GEMINI_API_KEY") or os.environ.get("GOOGLE_API_KEY", "")
    client = genai.Client(api_key=api_key)

    scene = None
    model_used = None
    for mn in GEMINI_MODELS:
        try:
            log.info(f"Trying model {mn}", extra={"event": "gemini_call"})
            resp = client.models.generate_content(model=mn, contents=[prompt, cs_img])
            scene = parse_gemini_json(resp.text)
            model_used = mn
            log.info(f"Model {mn} succeeded", extra={"event": "gemini_ok"})
            break
        except Exception as e:
            log.warning(f"Model {mn} failed: {e}", extra={"event": "gemini_fail"})

    if scene is None:
        raise RuntimeError("All Gemini models failed for Stage 1")

    scene["model_used"] = model_used

    # validate timestamps
    ts = scene["timestamps_s"]
    assert ts["run_up_start"] < ts["back_foot_contact"], "run_up < bfc"
    assert ts["back_foot_contact"] < ts["front_foot_contact"], "bfc < ffc"
    assert ts["front_foot_contact"] <= ts["release"], "ffc <= release"
    assert ts["release"] < ts["follow_through"], "release < follow_through"
    # clamp follow_through
    ts["follow_through"] = min(ts["follow_through"], sv["duration_seconds"])
    assert scene["bowling_arm"] in {"left", "right"}
    assert len(scene["bowler_center_points"]) >= 1
    assert all(0 <= p["x"] <= 1 and 0 <= p["y"] <= 1 for p in scene["bowler_center_points"])
    assert 1 <= scene.get("clip_quality", 5) <= 10
    assert 0 <= scene.get("stage1_confidence", 0.5) <= 1

    save_json(sd / "scene_report.json", scene)
    save_json(sd / "manifest.json", make_manifest(
        run_id, "stage1", "1.0.0", source_path, src_hash, sv,
        started_at=t0, model=model_used,
        shared_artifacts={"scene_report": "stage1/scene_report.json"},
        confidence={"overall": scene.get("stage1_confidence", 0.5), "notes": []}))

    log.info(f"Stage 1 done: {scene['bowler_id']}, arm={scene['bowling_arm']}, "
             f"quality={scene.get('clip_quality')}", extra={"event": "done"})
    return scene


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# STAGE 1.5: ROUTER
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

def run_stage1_5(run_root, sv, scene, run_id, src_hash, source_path, user_tech, log):
    sd = run_root / "stage1_5"; sd.mkdir(exist_ok=True)
    t0 = now_iso()
    log.info("Stage 1.5 start", extra={"event": "start"})

    plugins = load_json(PIPELINE_DIR / "registry" / "technique_plugins.json")
    seg_defs = load_json(PIPELINE_DIR / "registry" / "segment_definitions.json")

    # validate registry
    assert len(plugins) >= 1, "no technique plugins"
    assert len(seg_defs) >= 1, "no segment definitions"

    seg_map = {(d["segment_definition_id"], d["version"]): d for d in seg_defs}
    plugin_map = {p["technique_id"]: p for p in plugins}

    cam = scene.get("camera_angle", "mixed")

    def suitability(p):
        if cam not in p["supported_camera_angles"] and "mixed" not in p["supported_camera_angles"]:
            return "unsupported"
        return "supported"

    branch_plans = []
    if user_tech == "all":
        targets = [p for p in plugins if suitability(p) != "unsupported"]
    else:
        if user_tech not in plugin_map:
            raise RuntimeError(f"Unknown technique: {user_tech}")
        p = plugin_map[user_tech]
        targets = [p] if suitability(p) != "unsupported" else []

    for p in targets:
        bid = f"branch_{p['technique_id']}"
        sd_id, sd_ver = p["segment_definition_id"], p["segment_definition_version"]
        assert (sd_id, sd_ver) in seg_map, f"segment def {sd_id}@{sd_ver} not in registry"
        branch_plans.append({
            "branch_id": bid,
            "technique_id": p["technique_id"],
            "technique_version": p["technique_version"],
            "segment_definition_id": sd_id,
            "segment_definition_version": sd_ver,
            "render_template_id": p["render_template_id"],
            "render_template_version": p["render_template_version"],
            "required_stages": ["stage5", "stage7", "stage8"],
            "optional_stages": ["stage6", "stage7_5"],
            "suitability": suitability(p),
            "degraded": False,
            "terminal_failed": False,
            "branch_output_root": f"branches/{bid}",
            "required_inputs": {
                "analysis": f"stage5/branches/{bid}/analysis.json",
                "render_report": f"stage7/branches/{bid}/render_report.json",
            },
            "expected_outputs": {
                "render_frames": f"stage7/branches/{bid}/rendered_frames",
                "encoded_video": f"stage8/branches/{bid}/upload_ready.mp4",
            },
            "plan_ref": f"stage1_5:branch:{bid}",
            "warnings": [],
        })

    assert len(branch_plans) >= 1, "no viable branches"

    plan = {
        "user_requested": user_tech,
        "gemini_recommended": scene.get("recommended_techniques", []),
        "requires_sam2": True,
        "requires_upscale": False,
        "analysis_fps": sv["fps"],
        "render_speed": 0.25,
        "render_target": {"width": RW, "height": RH, "fps": RFPS},
        "branch_plans": branch_plans,
    }
    save_json(sd / "plan.json", plan)
    save_json(sd / "manifest.json", make_manifest(
        run_id, "stage1_5", "1.0.0", source_path, src_hash, sv,
        started_at=t0,
        shared_artifacts={"plan": "stage1_5/plan.json"}))

    log.info(f"Stage 1.5 done: {len(branch_plans)} branch(es)", extra={"event": "done"})
    return plan


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# STAGE 2: BOWLER ISOLATION (SAM 2)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

def run_stage2(run_root, sv, scene, run_id, src_hash, source_path, log):
    sd = run_root / "stage2"; sd.mkdir(exist_ok=True)
    masks_dir = sd / "masks"; masks_dir.mkdir(exist_ok=True)
    t0 = now_iso()
    log.info("Stage 2 start", extra={"event": "start"})

    W, H, fps, fc = sv["width"], sv["height"], sv["fps"], sv["frame_count"]

    # extract frames to JPEG dir for SAM 2
    frames_dir = sd / "frames"; frames_dir.mkdir(exist_ok=True)
    cap = cv2.VideoCapture(str(source_path))
    idx = 0
    while True:
        ok, fr = cap.read()
        if not ok:
            break
        cv2.imwrite(str(frames_dir / f"{idx:06d}.jpg"), fr)
        idx += 1
    cap.release()
    actual_fc = idx
    log.info(f"Extracted {actual_fc} frames", extra={"event": "frames_extracted"})

    # pick prompt — prefer bounding box, fall back to center point
    bbox = scene.get("bowler_bounding_box")
    pts = scene["bowler_center_points"]

    import torch
    from sam2.build_sam import build_sam2_video_predictor

    device = torch.device("mps")
    predictor = build_sam2_video_predictor(SAM2_CFG, str(SAM2_CKPT), device=device)
    state = predictor.init_state(video_path=str(frames_dir))

    if bbox and bbox.get("x1") is not None:
        # primary prompt: bounding box — much more precise than a single point
        prompt_frame_idx = sfidx(bbox["frame_time_s"], fps)
        prompt_frame_idx = min(prompt_frame_idx, actual_fc - 1)
        box = np.array([
            bbox["x1"] * W, bbox["y1"] * H,
            bbox["x2"] * W, bbox["y2"] * H,
        ], dtype=np.float32)
        log.info(f"Box prompt: frame {prompt_frame_idx}, box [{box[0]:.0f},{box[1]:.0f},{box[2]:.0f},{box[3]:.0f}]",
                 extra={"event": "sam2_prompt"})
        predictor.add_new_points_or_box(
            inference_state=state,
            frame_idx=prompt_frame_idx,
            obj_id=1,
            box=box,
        )
    else:
        # fallback: first center point as point prompt
        prompt_pt = pts[0]
        prompt_frame_idx = sfidx(prompt_pt["frame_time_s"], fps)
        prompt_frame_idx = min(prompt_frame_idx, actual_fc - 1)
        px = prompt_pt["x"] * W
        py = prompt_pt["y"] * H
        log.info(f"Point prompt: frame {prompt_frame_idx}, pixel ({px:.0f}, {py:.0f})",
                 extra={"event": "sam2_prompt"})
        predictor.add_new_points_or_box(
            inference_state=state,
            frame_idx=prompt_frame_idx,
            obj_id=1,
            points=np.array([[px, py]], dtype=np.float32),
            labels=np.array([1], dtype=np.int32),
        )

    # add reinforcement prompts at other center points (handles camera cuts)
    prompted_frames = {prompt_frame_idx}
    for pt in pts:
        fi = sfidx(pt["frame_time_s"], fps)
        fi = min(fi, actual_fc - 1)
        if fi in prompted_frames:
            continue
        px = pt["x"] * W
        py = pt["y"] * H
        if px > 0 and py > 0:
            log.info(f"Reinforcement point: frame {fi}, ({px:.0f}, {py:.0f})",
                     extra={"event": "sam2_reinforce"})
            predictor.add_new_points_or_box(
                inference_state=state,
                frame_idx=fi,
                obj_id=1,
                points=np.array([[px, py]], dtype=np.float32),
                labels=np.array([1], dtype=np.int32),
            )
            prompted_frames.add(fi)

    # propagate
    masks_dict = {}
    for fi, oids, logits in predictor.propagate_in_video(state):
        mask = (logits[0] > 0.0).squeeze().cpu().numpy().astype(np.uint8) * 255
        masks_dict[fi] = mask

    log.info(f"SAM 2 produced masks for {len(masks_dict)} frames", extra={"event": "sam2_done"})

    # save masks + compute metrics
    areas = []
    centroids = []
    empty_count = 0

    for fi in range(actual_fc):
        if fi in masks_dict:
            m = masks_dict[fi]
        else:
            m = np.zeros((H, W), dtype=np.uint8)

        # ensure correct dimensions
        if m.shape != (H, W):
            m = cv2.resize(m, (W, H), interpolation=cv2.INTER_NEAREST)
            m = (m > 127).astype(np.uint8) * 255

        cv2.imwrite(str(masks_dir / f"frame_{fi:06d}.png"), m)

        area = int(np.sum(m > 0))
        areas.append(area)
        if area < 500:
            empty_count += 1
            centroids.append({"frame_index": fi, "x": 0.0, "y": 0.0})
        else:
            ys, xs = np.where(m > 0)
            cx, cy = float(np.mean(xs)) / W, float(np.mean(ys)) / H
            centroids.append({"frame_index": fi, "x": round(cx, 4), "y": round(cy, 4)})

    # cleanup temp frames
    shutil.rmtree(frames_dir, ignore_errors=True)

    # metrics
    masked_count = sum(1 for a in areas if a >= 500)
    areas_np = np.array(areas, dtype=float)
    nonzero = areas_np[areas_np >= 500]

    # centroid drift
    max_drift = 0.0
    for i in range(1, len(centroids)):
        if centroids[i]["x"] > 0 and centroids[i - 1]["x"] > 0:
            d = sqrt((centroids[i]["x"] - centroids[i - 1]["x"]) ** 2 +
                     (centroids[i]["y"] - centroids[i - 1]["y"]) ** 2)
            max_drift = max(max_drift, d)

    # adjacent area change
    max_area_change = 0.0
    for i in range(1, len(areas)):
        if areas[i] > 500 and areas[i - 1] > 500:
            ratio = abs(areas[i] - areas[i - 1]) / max(areas[i], areas[i - 1])
            max_area_change = max(max_area_change, ratio)

    # consecutive empty
    max_empty_run = 0
    cur_run = 0
    for a in areas:
        if a < 500:
            cur_run += 1
            max_empty_run = max(max_empty_run, cur_run)
        else:
            cur_run = 0

    metrics = {
        "frames_masked": masked_count,
        "frames_empty": empty_count,
        "mask_count": actual_fc,
        "mask_width": W,
        "mask_height": H,
        "avg_mask_area_px": float(np.mean(nonzero)) if len(nonzero) else 0,
        "min_mask_area_px": float(np.min(nonzero)) if len(nonzero) else 0,
        "max_mask_area_px": float(np.max(nonzero)) if len(nonzero) else 0,
        "mask_area_stddev_px": float(np.std(nonzero)) if len(nonzero) else 0,
        "max_centroid_drift_ratio": round(max_drift, 4),
        "max_adjacent_mask_area_change_ratio": round(max_area_change, 4),
        "sam2_model": "sam2.1_hiera_large",
        "sam2_prompt": {"frame_time_s": bbox["frame_time_s"] if bbox else pts[0]["frame_time_s"],
                        "type": "box" if bbox else "point",
                        "box": bbox if bbox else None,
                        "point": pts[0] if not bbox else None},
        "isolation_mode": "sam2_masks",
        "synthetic_mask_fill_value": 255,
        "single_person_gate_passed": False,
    }
    save_json(sd / "stage2_metrics.json", metrics)

    centroid_track = {"coordinate_system": "normalized_xy", "frames": centroids}
    save_json(sd / "centroid_track.json", centroid_track)

    # isolation preview
    _make_preview(source_path, masks_dir, sd / "isolation_preview.mp4", sv)

    # validate
    cr = ["mask_count", "coverage", "min_area", "empty_run", "drift", "area_change"]
    cp, cf = [], []
    if actual_fc == fc:
        cp.append("mask_count")
    else:
        cf.append("mask_count")
    if masked_count / max(actual_fc, 1) >= 0.90:
        cp.append("coverage")
    else:
        cf.append("coverage")
    if len(nonzero) and np.min(nonzero) > 500:
        cp.append("min_area")
    else:
        cf.append("min_area")
    if max_empty_run < 3:
        cp.append("empty_run")
    else:
        cf.append("empty_run")
    if max_drift < 0.15:
        cp.append("drift")
    else:
        cf.append("drift")
    if max_area_change < 0.50:
        cp.append("area_change")
    else:
        cf.append("area_change")

    status = "success" if not cf else "degraded"
    save_json(sd / "manifest.json", make_manifest(
        run_id, "stage2", "1.0.0", source_path, src_hash, sv,
        status=status, started_at=t0,
        validation={"checks_run": cr, "checks_passed": cp, "checks_failed": cf},
        shared_artifacts={"masks": "stage2/masks/", "metrics": "stage2/stage2_metrics.json",
                          "centroid_track": "stage2/centroid_track.json",
                          "preview": "stage2/isolation_preview.mp4"}))

    log.info(f"Stage 2 done: {masked_count}/{actual_fc} masked, drift={max_drift:.3f}",
             extra={"event": "done"})
    return metrics


def _make_preview(source_path, masks_dir, out_path, sv):
    """Quick isolation preview video."""
    cap = cv2.VideoCapture(str(source_path))
    W, H = sv["width"], sv["height"]
    fourcc = cv2.VideoWriter_fourcc(*"mp4v")
    writer = cv2.VideoWriter(str(out_path), fourcc, sv["fps"], (W, H))
    fi = 0
    while True:
        ok, fr = cap.read()
        if not ok:
            break
        mp = masks_dir / f"frame_{fi:06d}.png"
        if mp.exists():
            mask = cv2.imread(str(mp), cv2.IMREAD_GRAYSCALE)
            if mask is not None and mask.shape[:2] == (H, W):
                fr = cv2.bitwise_and(fr, fr, mask=mask)
            else:
                fr = np.zeros_like(fr)
        else:
            fr = np.zeros_like(fr)
        writer.write(fr)
        fi += 1
    cap.release()
    writer.release()


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# STAGE 3: ENHANCEMENT (passthrough)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

def run_stage3(run_root, sv, run_id, src_hash, source_path, log):
    sd = run_root / "stage3"; sd.mkdir(exist_ok=True)
    log.info("Stage 3 skipped (passthrough)", extra={"event": "skip"})
    save_json(sd / "manifest.json", make_manifest(
        run_id, "stage3", "1.0.0", source_path, src_hash, sv,
        status="skipped",
        fallback={"was_used": True, "mode": "degraded", "reason": "enhancement not implemented"}))


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# STAGE 4: POSE EXTRACTION (MediaPipe)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

def _run_pose_pass(source_path, masks_dir, sv):
    """Single MediaPipe pass → list of frame dicts."""
    import mediapipe as mp

    opts = mp.tasks.vision.PoseLandmarkerOptions(
        base_options=mp.tasks.BaseOptions(model_asset_path=str(MP_MODEL)),
        running_mode=mp.tasks.vision.RunningMode.IMAGE,
        num_poses=1,
        min_pose_detection_confidence=0.3,
        min_pose_presence_confidence=0.3,
        min_tracking_confidence=0.3,
    )
    detector = mp.tasks.vision.PoseLandmarker.create_from_options(opts)

    cap = cv2.VideoCapture(str(source_path))
    W, H = sv["width"], sv["height"]
    fps = sv["fps"]
    frames_out = []
    fi = 0

    while True:
        ok, fr = cap.read()
        if not ok:
            break

        # apply mask
        mp_path = masks_dir / f"frame_{fi:06d}.png"
        if mp_path.exists():
            mask = cv2.imread(str(mp_path), cv2.IMREAD_GRAYSCALE)
            if mask is not None and mask.shape == (H, W):
                fr = cv2.bitwise_and(fr, fr, mask=mask)
            else:
                fr = np.zeros_like(fr)

        rgb = cv2.cvtColor(fr, cv2.COLOR_BGR2RGB)
        mp_img = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)
        result = detector.detect(mp_img)

        if result.pose_landmarks and len(result.pose_landmarks) > 0:
            lm = result.pose_landmarks[0]
            landmarks = [[round(l.x, 6), round(l.y, 6), round(l.visibility, 4)] for l in lm]
            tl = torso_len([(l[0], l[1]) for l in landmarks])
            frames_out.append({
                "index": fi, "time_s": round(fi / fps, 4),
                "detected": True, "landmarks": landmarks,
                "torso_length": round(tl, 6),
            })
        else:
            frames_out.append({
                "index": fi, "time_s": round(fi / fps, 4),
                "detected": False, "landmarks": [[0, 0, 0]] * 33,
                "torso_length": 0.0,
            })
        fi += 1

    cap.release()
    detector.close()
    return frames_out


def run_stage4(run_root, sv, scene, run_id, src_hash, source_path, log):
    sd = run_root / "stage4"; sd.mkdir(exist_ok=True)
    t0 = now_iso()
    log.info("Stage 4 start", extra={"event": "start"})

    masks_dir = run_root / "stage2" / "masks"

    # first pass
    frames1 = _run_pose_pass(source_path, masks_dir, sv)
    # second pass for determinism
    frames2 = _run_pose_pass(source_path, masks_dir, sv)

    # check determinism
    determinism = True
    for f1, f2 in zip(frames1, frames2):
        if f1["detected"] != f2["detected"]:
            determinism = False
            break
        if f1["detected"] and f2["detected"]:
            for l1, l2 in zip(f1["landmarks"], f2["landmarks"]):
                if abs(l1[0] - l2[0]) > 1e-4 or abs(l1[1] - l2[1]) > 1e-4:
                    determinism = False
                    break

    # quality metrics
    detected = [f for f in frames1 if f["detected"]]
    det_rate = len(detected) / max(len(frames1), 1)

    # shoulder-hip visibility
    sh_vis = 0
    for f in detected:
        lm = f["landmarks"]
        if all(lm[i][2] > 0.3 for i in [11, 12, 23, 24]):
            sh_vis += 1
    sh_rate = sh_vis / max(len(detected), 1)

    # bowling arm wrist visibility in delivery window
    ts = scene["timestamps_s"]
    bfc_idx = sfidx(ts["back_foot_contact"], sv["fps"])
    ft_idx = sfidx(ts["follow_through"], sv["fps"])
    wrist_idx = 16 if scene["bowling_arm"] == "right" else 15
    dw_frames = [f for f in frames1 if bfc_idx <= f["index"] <= ft_idx]
    wrist_vis = sum(1 for f in dw_frames if f["detected"] and f["landmarks"][wrist_idx][2] > 0.3)
    wrist_rate = wrist_vis / max(len(dw_frames), 1)

    # torso stability
    torso_vals = [f["torso_length"] for f in detected if f["torso_length"] > 0]
    tl_mean = float(np.mean(torso_vals)) if torso_vals else 0
    tl_std = float(np.std(torso_vals)) if torso_vals else 0

    # max landmark jump
    max_jump = 0.0
    for i in range(1, len(frames1)):
        if frames1[i]["detected"] and frames1[i - 1]["detected"]:
            tl = frames1[i]["torso_length"]
            if tl > 0:
                for j in range(33):
                    d = dist(frames1[i]["landmarks"][j][:2],
                             frames1[i - 1]["landmarks"][j][:2])
                    max_jump = max(max_jump, d / tl)

    pq = {
        "detection_rate": round(det_rate, 3),
        "shoulder_hip_visibility_rate": round(sh_rate, 3),
        "bowling_arm_wrist_visibility_delivery_window": round(wrist_rate, 3),
        "torso_length_mean": round(tl_mean, 6),
        "torso_length_stddev": round(tl_std, 6),
        "max_landmark_jump_ratio": round(max_jump, 4),
        "determinism_verified": determinism,
    }

    poses = {"canonical_fps": sv["fps"], "frames": frames1, "pose_quality": pq}
    save_json(sd / "poses.json", poses)

    # validate
    cr = ["detection_rate", "sh_visibility", "wrist_visibility", "torso_stability",
          "jump_ratio", "determinism"]
    cp, cf = [], []
    (cp if det_rate >= 0.80 else cf).append("detection_rate")
    (cp if sh_rate >= 0.85 else cf).append("sh_visibility")
    (cp if wrist_rate >= 0.80 else cf).append("wrist_visibility")
    (cp if tl_mean == 0 or tl_std / tl_mean < 0.20 else cf).append("torso_stability")
    (cp if max_jump < 0.15 else cf).append("jump_ratio")
    (cp if determinism else cf).append("determinism")

    status = "success" if not cf else "degraded"
    save_json(sd / "manifest.json", make_manifest(
        run_id, "stage4", "1.0.0", source_path, src_hash, sv,
        status=status, started_at=t0,
        validation={"checks_run": cr, "checks_passed": cp, "checks_failed": cf},
        shared_artifacts={"poses": "stage4/poses.json"}))

    log.info(f"Stage 4 done: det={det_rate:.0%} sh={sh_rate:.0%} wrist={wrist_rate:.0%} "
             f"det_check={'OK' if determinism else 'FAIL'}",
             extra={"event": "done"})
    return poses


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# STAGE 5: ANALYSIS (per branch)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

def _resolve_joints(seg, arm):
    if seg["joint_source"] == "fixed":
        return seg["joint_indices"]
    return seg["joint_indices_by_arm"][arm]


def run_stage5(run_root, sv, scene, plan, poses, run_id, src_hash, source_path, log):
    sd = run_root / "stage5"; sd.mkdir(exist_ok=True)
    t0 = now_iso()
    log.info("Stage 5 start", extra={"event": "start"})

    seg_defs = load_json(PIPELINE_DIR / "registry" / "segment_definitions.json")
    seg_map = {(d["segment_definition_id"], d["version"]): d for d in seg_defs}
    fps = sv["fps"]
    arm = scene["bowling_arm"]
    frames = poses["frames"]

    branch_entries = []
    for bp in plan["branch_plans"]:
        bid = bp["branch_id"]
        bdir = sd / "branches" / bid; bdir.mkdir(parents=True, exist_ok=True)
        log.info(f"Analyzing branch {bid}", extra={"event": "branch_start", "branch_id": bid})

        sd_key = (bp["segment_definition_id"], bp["segment_definition_version"])
        seg_def = seg_map[sd_key]

        # delivery window
        ts = scene["timestamps_s"]
        start_s = ts[seg_def["window"]["start_key"]]
        end_s = ts[seg_def["window"]["end_key"]]
        start_idx = sfidx(start_s, fps)
        end_idx = sfidx(end_s, fps)
        dw_indices = list(range(start_idx + 1, end_idx + 1))

        # resolve segments
        resolved = []
        for seg in seg_def["segments"]:
            ji = _resolve_joints(seg, arm)
            resolved.append({"segment_id": seg["segment_id"],
                             "joint_indices": ji, "aggregation": seg["aggregation"]})

        # per-joint velocity (consecutive frames, torso-normalized)
        n_frames = len(frames)
        joint_vel = {j: np.zeros(n_frames) for seg in resolved for j in seg["joint_indices"]}

        for i in range(1, n_frames):
            f_cur, f_prev = frames[i], frames[i - 1]
            if not f_cur["detected"] or not f_prev["detected"]:
                continue
            tl = f_cur["torso_length"]
            if tl <= 0:
                continue
            for j in joint_vel:
                d = dist(f_cur["landmarks"][j][:2], f_prev["landmarks"][j][:2])
                joint_vel[j][i] = d * fps / tl

        # 3-frame median filter
        for j in joint_vel:
            joint_vel[j] = medfilt(joint_vel[j], size=3)

        # per-segment aggregated velocity
        seg_series = {}
        for seg in resolved:
            sid = seg["segment_id"]
            jis = seg["joint_indices"]
            series = np.zeros(n_frames)
            for t in range(n_frames):
                vals = [joint_vel[j][t] for j in jis]
                series[t] = max(vals) if vals else 0
            seg_series[sid] = series

        # peaks in delivery window
        seg_peaks = {}
        for sid, series in seg_series.items():
            best_val, best_idx = -1, -1
            for t in dw_indices:
                if 0 <= t < n_frames and series[t] > best_val:
                    best_val = series[t]
                    best_idx = t
            if best_idx >= 0:
                seg_peaks[sid] = {
                    "peak_frame": best_idx,
                    "peak_time_s": round(best_idx / fps, 4),
                    "velocity_tl_s": round(best_val, 4),
                }

        # transition ratios
        trans_ratios = {}
        for a, b in seg_def["transitions"]:
            key = f"{a}->{b}"
            if a in seg_peaks and b in seg_peaks:
                va = seg_peaks[a]["velocity_tl_s"]
                vb = seg_peaks[b]["velocity_tl_s"]
                trans_ratios[key] = round(vb / va, 3) if va > 0 else 0
            else:
                trans_ratios[key] = 0

        # peak order
        expected = seg_def["expected_peak_order"]
        observed = sorted(
            [(sid, seg_peaks[sid]["peak_time_s"], expected.index(sid))
             for sid in expected if sid in seg_peaks],
            key=lambda x: (x[1], x[2])
        )
        peak_order_correct = [x[0] for x in observed] == expected

        # wrist joint peaks
        supporting = {}
        for j_idx in [15, 16]:
            if j_idx in joint_vel:
                vals = joint_vel[j_idx]
                best = max(vals[t] for t in dw_indices if 0 <= t < n_frames) if dw_indices else 0
                supporting[str(j_idx)] = round(float(best), 4)
            else:
                supporting[str(j_idx)] = 0.0

        # chain amplification
        peak_vels = [seg_peaks[sid]["velocity_tl_s"] for sid in expected if sid in seg_peaks]
        amp = peak_vels[-1] / peak_vels[0] if len(peak_vels) >= 2 and peak_vels[0] > 0 else 1.0

        # weakest link
        weakest = min(trans_ratios, key=lambda k: trans_ratios[k]) if trans_ratios else ""

        # confidence
        notes = []
        if not peak_order_correct:
            notes.append("peak order incorrect — possible energy leak")
        cam = scene.get("camera_angle", "mixed")
        if cam in ("front-on", "behind"):
            notes.append(f"camera angle '{cam}' may reduce lateral velocity accuracy")
        if not notes:
            notes.append("analysis within expected bounds")

        analysis = {
            "canonical_timebase": "source_seconds",
            "branch_id": bid,
            "plan_ref": bp["plan_ref"],
            "segment_definition_id": bp["segment_definition_id"],
            "segment_definition_version": bp["segment_definition_version"],
            "delivery_window": {"start_s": start_s, "end_s": end_s,
                                "start_idx": start_idx, "end_idx": end_idx},
            "resolved_segments": resolved,
            "segment_peaks": seg_peaks,
            "transition_ratios": trans_ratios,
            "supporting_joint_peaks": supporting,
            "peak_order_correct": peak_order_correct,
            "peak_order_rule": "stable_sort_by_peak_time_then_expected_order_index",
            "total_chain_amplification": round(amp, 3),
            "weakest_link": weakest,
            "camera_angle": cam,
            "confidence_notes": notes,
            "flags": [] if peak_order_correct else ["peak_order_violated"],
        }
        save_json(bdir / "analysis.json", analysis)

        branch_entries.append({
            "branch_id": bid, "technique_id": bp["technique_id"],
            "plan_ref": bp["plan_ref"],
            "segment_definition_id": bp["segment_definition_id"],
            "segment_definition_version": bp["segment_definition_version"],
            "render_template_id": bp["render_template_id"],
            "render_template_version": bp["render_template_version"],
            "branch_dir": str(bdir.relative_to(run_root)),
            "branch_manifest_path": str((bdir / "analysis.json").relative_to(run_root)),
            "branch_report_path": str((bdir / "analysis.json").relative_to(run_root)),
            "status": "success",
        })

        log.info(f"Branch {bid}: peaks={list(seg_peaks.keys())} order={'OK' if peak_order_correct else 'FAIL'} amp={amp:.2f}",
                 extra={"event": "branch_done", "branch_id": bid})

    save_json(sd / "manifest.json", make_manifest(
        run_id, "stage5", "1.0.0", source_path, src_hash, sv,
        started_at=t0, branches=branch_entries))

    log.info("Stage 5 done", extra={"event": "done"})


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# STAGE 5.5: CROSS-STAGE SANITY CHECKS
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

def run_stage5_5(run_root, sv, scene, plan, poses, run_id, src_hash, source_path, log):
    sd = run_root / "stage5_5"; sd.mkdir(exist_ok=True)
    t0 = now_iso()
    log.info("Stage 5.5 start", extra={"event": "start"})

    fps = sv["fps"]
    arm = scene["bowling_arm"]
    centroid_track = load_json(run_root / "stage2" / "centroid_track.json")

    branch_entries = []
    for bp in plan["branch_plans"]:
        bid = bp["branch_id"]
        bdir = sd / "branches" / bid; bdir.mkdir(parents=True, exist_ok=True)
        analysis = load_json(run_root / "stage5" / "branches" / bid / "analysis.json")

        checks = []

        def check(cid, name, passed, val, thresh, comp, detail=""):
            checks.append({
                "check_id": cid, "name": name,
                "result": "pass" if passed else "warn",
                "measured_value": round(val, 4) if isinstance(val, float) else val,
                "threshold": thresh, "comparison": comp,
                "detail": detail, "rerun_required": False,
            })

        # 1. dominant wrist check
        lp = analysis["supporting_joint_peaks"].get("15", 0)
        rp = analysis["supporting_joint_peaks"].get("16", 0)
        if arm == "right":
            check("wrist_dom", "bowling arm wrist dominance", rp >= lp, rp,
                  lp, ">=", f"R={rp} L={lp}")
        else:
            check("wrist_dom", "bowling arm wrist dominance", lp >= rp, lp,
                  rp, ">=", f"L={lp} R={rp}")

        # 2. centroid alignment (stage1 vs stage2)
        s1_pts = scene["bowler_center_points"]
        s2_frames = centroid_track["frames"]
        max_cd = 0.0
        for pt in s1_pts:
            fi = sfidx(pt["frame_time_s"], fps)
            if fi < len(s2_frames) and s2_frames[fi]["x"] > 0:
                d = sqrt((pt["x"] - s2_frames[fi]["x"]) ** 2 +
                         (pt["y"] - s2_frames[fi]["y"]) ** 2)
                max_cd = max(max_cd, d)
        check("centroid_align", "stage1-stage2 centroid alignment",
              max_cd < 0.30, max_cd, 0.30, "<")

        # 3. release posture
        rel_idx = sfidx(scene["timestamps_s"]["release"], fps)
        pf = poses["frames"]
        if rel_idx < len(pf) and pf[rel_idx]["detected"]:
            lm = pf[rel_idx]["landmarks"]
            w_idx = 16 if arm == "right" else 15
            h_idx = 24 if arm == "right" else 23
            wy = lm[w_idx][1]
            hy = lm[h_idx][1]
            check("release_posture", "wrist above hip at release",
                  wy <= hy + 0.10, wy, hy + 0.10, "<=",
                  f"wrist_y={wy:.3f} hip_y={hy:.3f}")
        else:
            check("release_posture", "wrist above hip at release",
                  False, 0, 0, "<=", "release frame not detected")

        # 4. torso stability
        pq = poses["pose_quality"]
        tl_m = pq["torso_length_mean"]
        tl_s = pq["torso_length_stddev"]
        cv_val = tl_s / tl_m if tl_m > 0 else 1.0
        check("torso_cv", "torso length stability",
              cv_val < 0.20, cv_val, 0.20, "<")

        # 5. wrist peak near release
        wrist_peak_s = analysis["segment_peaks"].get("wrist", {}).get("peak_time_s", 0)
        release_s = scene["timestamps_s"]["release"]
        diff = abs(wrist_peak_s - release_s)
        check("wrist_release", "wrist peak near release",
              diff <= 0.20, diff, 0.20, "<=",
              f"wrist_peak={wrist_peak_s}s release={release_s}s")

        all_pass = all(c["result"] == "pass" for c in checks)
        report = {"passed": all_pass, "checks": checks}
        save_json(bdir / "sanity_report.json", report)

        branch_entries.append({
            "branch_id": bid, "technique_id": bp["technique_id"],
            "plan_ref": bp["plan_ref"],
            "segment_definition_id": bp["segment_definition_id"],
            "segment_definition_version": bp["segment_definition_version"],
            "render_template_id": bp["render_template_id"],
            "render_template_version": bp["render_template_version"],
            "branch_dir": str(bdir.relative_to(run_root)),
            "branch_manifest_path": str((bdir / "sanity_report.json").relative_to(run_root)),
            "branch_report_path": str((bdir / "sanity_report.json").relative_to(run_root)),
            "status": "success" if all_pass else "degraded",
        })
        log.info(f"Branch {bid} sanity: {'PASS' if all_pass else 'WARN'} "
                 f"({sum(1 for c in checks if c['result']=='pass')}/{len(checks)})",
                 extra={"event": "branch_done", "branch_id": bid})

    save_json(sd / "manifest.json", make_manifest(
        run_id, "stage5_5", "1.0.0", source_path, src_hash, sv,
        started_at=t0, branches=branch_entries))
    log.info("Stage 5.5 done", extra={"event": "done"})


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# STAGE 6: INSIGHT (skip)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

def run_stage6(run_root, sv, plan, run_id, src_hash, source_path, log):
    sd = run_root / "stage6"; sd.mkdir(exist_ok=True)
    log.info("Stage 6 skipped", extra={"event": "skip"})
    branches = [{
        "branch_id": bp["branch_id"], "technique_id": bp["technique_id"],
        "plan_ref": bp["plan_ref"],
        "segment_definition_id": bp["segment_definition_id"],
        "segment_definition_version": bp["segment_definition_version"],
        "render_template_id": bp["render_template_id"],
        "render_template_version": bp["render_template_version"],
        "branch_dir": f"stage6/branches/{bp['branch_id']}",
        "branch_manifest_path": "", "branch_report_path": "",
        "status": "skipped",
    } for bp in plan["branch_plans"]]
    save_json(sd / "manifest.json", make_manifest(
        run_id, "stage6", "1.0.0", source_path, src_hash, sv,
        status="skipped", branches=branches))


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# STAGE 7: RENDER
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

def _draw_skeleton(draw, lm, vel_map, ox, oy, scale, alpha_frame=None):
    """Draw skeleton on Pillow draw context. vel_map: joint_idx → 0..1 velocity."""
    pts = {}
    for i in range(33):
        if lm[i][2] < 0.2:
            continue
        x = ox + lm[i][0] * scale[0]
        y = oy + lm[i][1] * scale[1]
        pts[i] = (x, y)

    # connections
    for a, b in POSE_CONNS:
        if a in pts and b in pts:
            va = vel_map.get(a, 0)
            vb = vel_map.get(b, 0)
            c = vel_color((va + vb) / 2)
            draw.line([pts[a], pts[b]], fill=c, width=4)

    # joints
    for i, (x, y) in pts.items():
        c = vel_color(vel_map.get(i, 0))
        r = 5
        draw.ellipse([x - r, y - r, x + r, y + r], fill=c)


def run_stage7(run_root, sv, scene, plan, poses, run_id, src_hash, source_path, log):
    sd = run_root / "stage7"; sd.mkdir(exist_ok=True)
    t0 = now_iso()
    log.info("Stage 7 start", extra={"event": "start"})

    fps = sv["fps"]
    W, H = sv["width"], sv["height"]
    arm = scene["bowling_arm"]
    masks_dir = run_root / "stage2" / "masks"
    frames_data = poses["frames"]

    # fonts
    font_big = get_font(64)
    font_med = get_font(40)
    font_sm = get_font(28)

    # preload source frames
    cap = cv2.VideoCapture(str(source_path))
    src_frames = []
    while True:
        ok, fr = cap.read()
        if not ok:
            break
        src_frames.append(fr)
    cap.release()

    # precompute per-joint velocities for all frames (for rendering)
    n_frames = len(frames_data)
    all_joints = set()
    for c in POSE_CONNS:
        all_joints.update(c)
    joint_vel = {j: np.zeros(n_frames) for j in all_joints}

    for i in range(1, n_frames):
        fc, fp = frames_data[i], frames_data[i - 1]
        if not fc["detected"] or not fp["detected"]:
            continue
        tl = fc["torso_length"]
        if tl <= 0:
            continue
        for j in joint_vel:
            if j < 33:
                d = dist(fc["landmarks"][j][:2], fp["landmarks"][j][:2])
                joint_vel[j][i] = d * fps / tl

    for j in joint_vel:
        joint_vel[j] = medfilt(joint_vel[j], size=3)

    # normalize to max wrist velocity
    wrist_j = 16 if arm == "right" else 15
    max_wrist = float(np.max(joint_vel.get(wrist_j, [1])))
    if max_wrist <= 0:
        max_wrist = 1.0

    branch_entries = []
    for bp in plan["branch_plans"]:
        bid = bp["branch_id"]
        bdir = sd / "branches" / bid
        rf_dir = bdir / "rendered_frames"; rf_dir.mkdir(parents=True, exist_ok=True)

        analysis = load_json(run_root / "stage5" / "branches" / bid / "analysis.json")
        dw = analysis["delivery_window"]

        # timing
        ts = scene["timestamps_s"]
        bfc_idx = dw["start_idx"]
        ft_idx = dw["end_idx"]
        rel_idx = sfidx(ts["release"], fps)

        # run-up: last 1.5s before BFC
        runup_start = max(0, bfc_idx - int(1.5 * fps))
        runup_indices = list(range(runup_start, bfc_idx))

        # delivery: BFC to follow_through, each frame repeated
        delivery_indices = list(range(bfc_idx, min(ft_idx + 1, n_frames)))
        hold = max(6, int(RFPS / (fps * plan.get("render_speed", 0.25))))

        # render frame counter
        render_idx = 0

        def save_frame(img):
            nonlocal render_idx
            img.save(str(rf_dir / f"frame_{render_idx:06d}.png"))
            render_idx += 1

        def make_canvas():
            return Image.new("RGB", (RW, RH), BG)

        def paste_video(canvas, src_fi, draw, apply_mask=True):
            """Paste source frame (masked) onto canvas, return (ox, oy, sw, sh)."""
            if src_fi >= len(src_frames):
                return 0, 0, 0, 0
            fr = src_frames[src_fi].copy()
            if apply_mask:
                mp = masks_dir / f"frame_{src_fi:06d}.png"
                if mp.exists():
                    mask = cv2.imread(str(mp), cv2.IMREAD_GRAYSCALE)
                    if mask is not None and mask.shape == (H, W):
                        fr = cv2.bitwise_and(fr, fr, mask=mask)
            rgb = cv2.cvtColor(fr, cv2.COLOR_BGR2RGB)
            pil_fr = Image.fromarray(rgb)

            # fit into 1080 x 1100 area (y=100 to y=1200)
            avail_w, avail_h = RW, 1100
            scale = min(avail_w / W, avail_h / H)
            sw, sh = int(W * scale), int(H * scale)
            pil_fr = pil_fr.resize((sw, sh), Image.LANCZOS)
            ox = (RW - sw) // 2
            oy = 100 + (avail_h - sh) // 2
            canvas.paste(pil_fr, (ox, oy))
            return ox, oy, sw, sh

        # ── TITLE CARD (1.5s) ────────────────────────────────
        for _ in range(int(1.5 * RFPS)):
            c = make_canvas()
            d = ImageDraw.Draw(c)
            d.text((RW // 2, 600), "SPEED GRADIENT", fill=WHITE, font=font_big, anchor="mm")
            name = scene.get("bowler_id", "unknown")
            if name and name != "unknown":
                d.text((RW // 2, 700), name.upper(), fill=GREY, font=font_med, anchor="mm")
            d.text((RW // 2, RH - 60), "wellBowled.ai", fill=BRAND, font=font_sm, anchor="mm")
            save_frame(c)

        # ── RUN-UP (1x) ──────────────────────────────────────
        for si in runup_indices:
            c = make_canvas()
            d = ImageDraw.Draw(c)
            d.text((RW // 2, 50), "LOAD", fill=GREY, font=font_med, anchor="mm")
            ox, oy, sw, sh = paste_video(c, si, d)
            if sw > 0 and si < len(frames_data) and frames_data[si]["detected"]:
                lm = frames_data[si]["landmarks"]
                # uniform blue during run-up
                vm = {j: 0.0 for j in all_joints}
                _draw_skeleton(d, lm, vm, ox, oy, (sw, sh))
            d.text((RW // 2, RH - 60), "wellBowled.ai", fill=BRAND, font=font_sm, anchor="mm")
            save_frame(c)

        # ── DELIVERY (slo-mo) ─────────────────────────────────
        phase_names = {
            "plant": (bfc_idx, sfidx(ts["front_foot_contact"], fps)),
            "brace": (sfidx(ts["front_foot_contact"], fps), sfidx(ts.get("release", ts["front_foot_contact"]), fps)),
            "whip": (sfidx(ts["release"], fps), ft_idx),
        }

        for si in delivery_indices:
            # determine phase name
            phase = "DELIVERY"
            for pn, (ps, pe) in phase_names.items():
                if ps <= si <= pe:
                    phase = pn.upper()
                    break

            # per-joint velocity map normalized to max_wrist
            vm = {}
            for j in all_joints:
                v = joint_vel.get(j, np.zeros(1))
                val = v[si] / max_wrist if si < len(v) else 0
                vm[j] = min(1.0, max(0.0, val))

            for rep in range(hold):
                c = make_canvas()
                d = ImageDraw.Draw(c)
                d.text((RW // 2, 50), phase, fill=WHITE, font=font_med, anchor="mm")
                ox, oy, sw, sh = paste_video(c, si, d)

                if sw > 0 and si < len(frames_data) and frames_data[si]["detected"]:
                    lm = frames_data[si]["landmarks"]
                    _draw_skeleton(d, lm, vm, ox, oy, (sw, sh))

                # bottom panel: segment velocity bars
                bar_y = 1300
                bar_h = 30
                seg_peaks = analysis["segment_peaks"]
                for k, seg_id in enumerate(["hips", "trunk", "arm", "wrist"]):
                    if seg_id not in seg_peaks:
                        continue
                    peak_vel = seg_peaks[seg_id]["velocity_tl_s"]
                    # current velocity for this segment's joints
                    seg_def_entry = None
                    for rs in analysis["resolved_segments"]:
                        if rs["segment_id"] == seg_id:
                            seg_def_entry = rs
                            break
                    cur_vel = 0
                    if seg_def_entry:
                        jis = seg_def_entry["joint_indices"]
                        vals = [joint_vel.get(j, np.zeros(1))[si] if si < len(joint_vel.get(j, [])) else 0 for j in jis]
                        cur_vel = max(vals) if vals else 0

                    norm_v = cur_vel / max_wrist if max_wrist > 0 else 0
                    bar_w = int(min(1.0, norm_v) * 700)
                    color = vel_color(min(1.0, norm_v))
                    by = bar_y + k * (bar_h + 20)
                    d.text((60, by + bar_h // 2), seg_id.upper(), fill=GREY, font=font_sm, anchor="lm")
                    d.rectangle([200, by, 200 + bar_w, by + bar_h], fill=color)

                d.text((RW // 2, RH - 60), "wellBowled.ai", fill=BRAND, font=font_sm, anchor="mm")
                save_frame(c)

        # ── VERDICT (2.5s) ────────────────────────────────────
        for _ in range(int(2.5 * RFPS)):
            c = make_canvas()
            d = ImageDraw.Draw(c)

            # freeze on release frame
            ox, oy, sw, sh = paste_video(c, min(rel_idx, len(src_frames) - 1), d)
            if rel_idx < len(frames_data) and frames_data[rel_idx]["detected"]:
                vm = {}
                for j in all_joints:
                    v = joint_vel.get(j, np.zeros(1))
                    val = v[rel_idx] / max_wrist if rel_idx < len(v) else 0
                    vm[j] = min(1.0, max(0.0, val))
                _draw_skeleton(d, frames_data[rel_idx]["landmarks"], vm, ox, oy, (sw, sh))

            d.text((RW // 2, 50), "VERDICT", fill=WHITE, font=font_med, anchor="mm")

            # peak order
            vy = 1260
            peaks = analysis["segment_peaks"]
            order = analysis.get("peak_order_correct", False)
            verdict_text = "ELITE SEQUENCING" if order else "ENERGY LEAK DETECTED"
            verdict_color = (0, 200, 80) if order else (255, 80, 40)
            d.text((RW // 2, vy), verdict_text, fill=verdict_color, font=font_big, anchor="mm")
            vy += 80

            # segment peaks
            for sid in ["hips", "trunk", "arm", "wrist"]:
                if sid in peaks:
                    pk = peaks[sid]
                    color = vel_color(pk["velocity_tl_s"] / max_wrist if max_wrist > 0 else 0)
                    d.text((100, vy), f"{sid.upper()}", fill=color, font=font_sm, anchor="lm")
                    d.text((400, vy), f"peak @ {pk['peak_time_s']:.2f}s", fill=GREY, font=font_sm, anchor="lm")
                    d.text((750, vy), f"vel={pk['velocity_tl_s']:.1f} tl/s",
                           fill=GREY, font=font_sm, anchor="lm")
                    vy += 45

            # transition ratios
            vy += 20
            for key, ratio in analysis["transition_ratios"].items():
                label = "LEAK" if ratio < 1.0 else "GAIN"
                c_r = (255, 80, 40) if ratio < 0.8 else (0, 200, 80) if ratio > 1.2 else GREY
                d.text((100, vy), key, fill=GREY, font=font_sm, anchor="lm")
                d.text((500, vy), f"×{ratio:.2f} ({label})", fill=c_r, font=font_sm, anchor="lm")
                vy += 40

            d.text((RW // 2, RH - 60), "wellBowled.ai", fill=BRAND, font=font_sm, anchor="mm")
            save_frame(c)

        # ── END CARD (1.5s) ───────────────────────────────────
        for _ in range(int(1.5 * RFPS)):
            c = make_canvas()
            d = ImageDraw.Draw(c)
            d.text((RW // 2, RH // 2 - 40), "wellBowled.ai", fill=BRAND, font=font_big, anchor="mm")
            d.text((RW // 2, RH // 2 + 40), "BOWLING BIOMECHANICS", fill=GREY, font=font_sm, anchor="mm")
            save_frame(c)

        # render report
        total = render_idx
        dur_s = round(total / RFPS, 2)
        title_f = int(1.5 * RFPS)
        runup_f = len(runup_indices)
        delivery_f = len(delivery_indices) * hold
        verdict_f = int(2.5 * RFPS)
        end_f = int(1.5 * RFPS)

        report = {
            "branch_id": bid,
            "plan_ref": bp["plan_ref"],
            "technique": bp["technique_id"],
            "render_template_id": bp["render_template_id"],
            "render_template_version": bp["render_template_version"],
            "analysis_ref": f"stage5/branches/{bid}/analysis.json",
            "insight_ref": None,
            "total_frames": total,
            "duration_s": dur_s,
            "output_fps": RFPS,
            "rife_requested": False,
            "sections": {
                "title": round(title_f / RFPS, 2),
                "analysis": round((runup_f + delivery_f) / RFPS, 2),
                "verdict": round(verdict_f / RFPS, 2),
                "end": round(end_f / RFPS, 2),
            },
        }
        save_json(bdir / "render_report.json", report)

        branch_entries.append({
            "branch_id": bid, "technique_id": bp["technique_id"],
            "plan_ref": bp["plan_ref"],
            "segment_definition_id": bp["segment_definition_id"],
            "segment_definition_version": bp["segment_definition_version"],
            "render_template_id": bp["render_template_id"],
            "render_template_version": bp["render_template_version"],
            "branch_dir": str(bdir.relative_to(run_root)),
            "branch_manifest_path": str((bdir / "render_report.json").relative_to(run_root)),
            "branch_report_path": str((bdir / "render_report.json").relative_to(run_root)),
            "status": "success",
        })
        log.info(f"Branch {bid} rendered: {total} frames, {dur_s}s",
                 extra={"event": "branch_done", "branch_id": bid})

    save_json(sd / "manifest.json", make_manifest(
        run_id, "stage7", "1.0.0", source_path, src_hash, sv,
        started_at=t0, branches=branch_entries))
    log.info("Stage 7 done", extra={"event": "done"})


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# STAGE 7.5: INTERPOLATION (skip)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

def run_stage7_5(run_root, sv, plan, run_id, src_hash, source_path, log):
    sd = run_root / "stage7_5"; sd.mkdir(exist_ok=True)
    log.info("Stage 7.5 skipped", extra={"event": "skip"})

    branch_entries = []
    for bp in plan["branch_plans"]:
        bid = bp["branch_id"]
        bdir = sd / "branches" / bid; bdir.mkdir(parents=True, exist_ok=True)
        # passthrough ref to stage 7 frames
        ref = run_root / "stage7" / "branches" / bid / "rendered_frames"
        (bdir / "passthrough_ref.txt").write_text(str(ref))
        branch_entries.append({
            "branch_id": bid, "technique_id": bp["technique_id"],
            "plan_ref": bp["plan_ref"],
            "segment_definition_id": bp["segment_definition_id"],
            "segment_definition_version": bp["segment_definition_version"],
            "render_template_id": bp["render_template_id"],
            "render_template_version": bp["render_template_version"],
            "branch_dir": str(bdir.relative_to(run_root)),
            "branch_manifest_path": "",
            "branch_report_path": "",
            "status": "skipped",
        })

    save_json(sd / "manifest.json", make_manifest(
        run_id, "stage7_5", "1.0.0", source_path, src_hash, sv,
        status="skipped", branches=branch_entries))


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# STAGE 8: ENCODE
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

def run_stage8(run_root, sv, plan, run_id, src_hash, source_path, log):
    sd = run_root / "stage8"; sd.mkdir(exist_ok=True)
    t0 = now_iso()
    log.info("Stage 8 start", extra={"event": "start"})

    branch_entries = []
    for bp in plan["branch_plans"]:
        bid = bp["branch_id"]
        bdir = sd / "branches" / bid; bdir.mkdir(parents=True, exist_ok=True)

        # determine source frames
        s75_ref = run_root / "stage7_5" / "branches" / bid / "passthrough_ref.txt"
        if s75_ref.exists():
            frames_dir = Path(s75_ref.read_text().strip())
        else:
            frames_dir = run_root / "stage7" / "branches" / bid / "rendered_frames"

        render_report = load_json(run_root / "stage7" / "branches" / bid / "render_report.json")
        out_mp4 = bdir / "upload_ready.mp4"

        # ffmpeg encode
        cmd = [
            "ffmpeg", "-y",
            "-framerate", str(RFPS),
            "-i", str(frames_dir / "frame_%06d.png"),
            "-c:v", "libx264",
            "-preset", "slow",
            "-crf", "17",
            "-pix_fmt", "yuv420p",
            "-vf", f"scale={RW}:{RH}",
            str(out_mp4),
        ]
        log.info(f"Encoding {bid}", extra={"event": "ffmpeg_start", "branch_id": bid})
        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode != 0:
            err = {"error": result.stderr[-500:] if result.stderr else "unknown"}
            save_json(bdir / "error_report.json", err)
            log.error(f"FFmpeg failed for {bid}: {result.stderr[:200]}",
                      extra={"event": "ffmpeg_fail", "branch_id": bid})
            branch_entries.append({
                "branch_id": bid, "technique_id": bp["technique_id"],
                "plan_ref": bp["plan_ref"],
                "segment_definition_id": bp["segment_definition_id"],
                "segment_definition_version": bp["segment_definition_version"],
                "render_template_id": bp["render_template_id"],
                "render_template_version": bp["render_template_version"],
                "branch_dir": str(bdir.relative_to(run_root)),
                "branch_manifest_path": "", "branch_report_path": "",
                "status": "failed",
            })
            continue

        # validate with ffprobe
        probe_cmd = [
            "ffprobe", "-v", "quiet", "-print_format", "json",
            "-show_format", "-show_streams", str(out_mp4),
        ]
        probe = subprocess.run(probe_cmd, capture_output=True, text=True)
        info = json.loads(probe.stdout) if probe.returncode == 0 else {}
        stream = info.get("streams", [{}])[0] if info.get("streams") else {}
        fmt = info.get("format", {})

        enc_report = {
            "codec": stream.get("codec_name", ""),
            "pixel_format": stream.get("pix_fmt", ""),
            "width": int(stream.get("width", 0)),
            "height": int(stream.get("height", 0)),
            "fps": eval(stream.get("r_frame_rate", "0/1")) if "/" in stream.get("r_frame_rate", "") else float(stream.get("r_frame_rate", 0)),
            "duration_s": float(fmt.get("duration", 0)),
            "bitrate_bps": int(fmt.get("bit_rate", 0)),
            "file_size_bytes": int(fmt.get("size", 0)),
        }
        save_json(bdir / "encode_report.json", enc_report)

        # validation checks
        cr = ["codec", "pix_fmt", "resolution", "fps", "bitrate", "duration", "size"]
        cp, cf = [], []
        (cp if enc_report["codec"] == "h264" else cf).append("codec")
        (cp if enc_report["pixel_format"] == "yuv420p" else cf).append("pix_fmt")
        (cp if enc_report["width"] == RW and enc_report["height"] == RH else cf).append("resolution")
        (cp if abs(enc_report["fps"] - RFPS) < 1 else cf).append("fps")
        (cp if enc_report["bitrate_bps"] >= 4_000_000 else cf).append("bitrate")
        (cp if abs(enc_report["duration_s"] - render_report["duration_s"]) <= 0.5 else cf).append("duration")
        (cp if enc_report["file_size_bytes"] < 100 * 1024 * 1024 else cf).append("size")

        status = "success" if not cf else "degraded"
        branch_entries.append({
            "branch_id": bid, "technique_id": bp["technique_id"],
            "plan_ref": bp["plan_ref"],
            "segment_definition_id": bp["segment_definition_id"],
            "segment_definition_version": bp["segment_definition_version"],
            "render_template_id": bp["render_template_id"],
            "render_template_version": bp["render_template_version"],
            "branch_dir": str(bdir.relative_to(run_root)),
            "branch_manifest_path": str((bdir / "encode_report.json").relative_to(run_root)),
            "branch_report_path": str((bdir / "encode_report.json").relative_to(run_root)),
            "status": status,
        })
        log.info(f"Branch {bid} encoded: {enc_report['duration_s']:.1f}s "
                 f"{enc_report['file_size_bytes'] / 1024 / 1024:.1f}MB",
                 extra={"event": "branch_done", "branch_id": bid})

    save_json(sd / "manifest.json", make_manifest(
        run_id, "stage8", "1.0.0", source_path, src_hash, sv,
        started_at=t0, branches=branch_entries))
    log.info("Stage 8 done", extra={"event": "done"})


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# ORCHESTRATOR
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

def run_pipeline(input_path, technique="speed_gradient", output_dir=None):
    source = Path(input_path).resolve()
    if not source.exists():
        print(f"ERROR: {source} not found")
        sys.exit(1)

    run_id = str(uuid.uuid4())[:8]
    if output_dir:
        run_root = Path(output_dir)
    else:
        run_root = PIPELINE_DIR / "output" / run_id
    run_root.mkdir(parents=True, exist_ok=True)

    # copy source
    src_dir = run_root / "source"; src_dir.mkdir(exist_ok=True)
    dst = src_dir / "input.mp4"
    shutil.copy2(source, dst)
    source_path = dst

    src_hash = sha256_file(source_path)

    # copy registry
    reg_dst = run_root / "registry"; reg_dst.mkdir(exist_ok=True)
    for f in (PIPELINE_DIR / "registry").iterdir():
        shutil.copy2(f, reg_dst / f.name)

    # logs
    logs_dir = run_root / "logs"; logs_dir.mkdir(exist_ok=True)

    log = get_logger("run", logs_dir, run_id)
    log.info(f"Pipeline start: {source} technique={technique}", extra={"event": "pipeline_start"})

    print(f"▸ Run ID: {run_id}")
    print(f"▸ Output: {run_root}")
    print(f"▸ Source: {source}")

    try:
        # Stage 0
        print("▸ Stage 0: Input validation...")
        slog = get_logger("stage0", logs_dir, run_id)
        sv = run_stage0(run_root, source_path, run_id, src_hash, slog)

        # run manifest
        save_json(run_root / "run_manifest.json", {
            "run_id": run_id,
            "source_path": str(source_path),
            "source_hash": src_hash,
            "user_request": {
                "technique": technique,
                "render_speed": 0.25,
                "allow_stage6": False,
            },
            "source_video": sv,
        })

        # Stage 1
        print("▸ Stage 1: Scene understanding (Gemini)...")
        slog = get_logger("stage1", logs_dir, run_id)
        scene = run_stage1(run_root, sv, run_id, src_hash, source_path, slog)
        print(f"  → {scene['bowler_id']}, {scene['bowling_arm']} arm, "
              f"quality={scene.get('clip_quality')}")

        # Stage 1.5
        print("▸ Stage 1.5: Router...")
        slog = get_logger("stage1_5", logs_dir, run_id)
        plan = run_stage1_5(run_root, sv, scene, run_id, src_hash, source_path, technique, slog)
        print(f"  → {len(plan['branch_plans'])} branch(es)")

        # Stage 2
        print("▸ Stage 2: Bowler isolation (SAM 2)...")
        slog = get_logger("stage2", logs_dir, run_id)
        s2_metrics = run_stage2(run_root, sv, scene, run_id, src_hash, source_path, slog)
        print(f"  → {s2_metrics['frames_masked']}/{s2_metrics['mask_count']} frames masked")

        # Stage 3 (skip)
        print("▸ Stage 3: Enhancement (skipped)...")
        slog = get_logger("stage3", logs_dir, run_id)
        run_stage3(run_root, sv, run_id, src_hash, source_path, slog)

        # Stage 4
        print("▸ Stage 4: Pose extraction (MediaPipe)...")
        slog = get_logger("stage4", logs_dir, run_id)
        poses = run_stage4(run_root, sv, scene, run_id, src_hash, source_path, slog)
        pq = poses["pose_quality"]
        print(f"  → detection={pq['detection_rate']:.0%} determinism={'OK' if pq['determinism_verified'] else 'FAIL'}")

        # Stage 5
        print("▸ Stage 5: Analysis...")
        slog = get_logger("stage5", logs_dir, run_id)
        run_stage5(run_root, sv, scene, plan, poses, run_id, src_hash, source_path, slog)

        # Stage 5.5
        print("▸ Stage 5.5: Sanity checks...")
        slog = get_logger("stage5_5", logs_dir, run_id)
        run_stage5_5(run_root, sv, scene, plan, poses, run_id, src_hash, source_path, slog)

        # Stage 6 (skip)
        print("▸ Stage 6: Insight (skipped)...")
        slog = get_logger("stage6", logs_dir, run_id)
        run_stage6(run_root, sv, plan, run_id, src_hash, source_path, slog)

        # Stage 7
        print("▸ Stage 7: Render...")
        slog = get_logger("stage7", logs_dir, run_id)
        run_stage7(run_root, sv, scene, plan, poses, run_id, src_hash, source_path, slog)

        # Stage 7.5 (skip)
        print("▸ Stage 7.5: Interpolation (skipped)...")
        slog = get_logger("stage7_5", logs_dir, run_id)
        run_stage7_5(run_root, sv, plan, run_id, src_hash, source_path, slog)

        # Stage 8
        print("▸ Stage 8: Encode...")
        slog = get_logger("stage8", logs_dir, run_id)
        run_stage8(run_root, sv, plan, run_id, src_hash, source_path, slog)

        # final output
        for bp in plan["branch_plans"]:
            bid = bp["branch_id"]
            out = run_root / "stage8" / "branches" / bid / "upload_ready.mp4"
            if out.exists():
                size_mb = out.stat().st_size / 1024 / 1024
                print(f"\n✓ Output: {out}")
                print(f"  Size: {size_mb:.1f} MB")

        log.info("Pipeline complete", extra={"event": "pipeline_done"})
        print("\n✓ Pipeline complete")

    except Exception as e:
        log.error(f"Pipeline failed: {e}", extra={"event": "pipeline_fail"})
        print(f"\n✗ Pipeline failed: {e}")
        raise


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# CLI
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Pipeline v1 — Bowling Analysis")
    parser.add_argument("input", help="Path to input video (MP4)")
    parser.add_argument("--technique", default="speed_gradient",
                        help="Technique to run (default: speed_gradient)")
    parser.add_argument("--output-dir", default=None,
                        help="Override output directory")
    args = parser.parse_args()

    # load .env if present
    env_path = PIPELINE_DIR.parent.parent / ".env"
    if env_path.exists():
        for line in env_path.read_text().splitlines():
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                os.environ.setdefault(k.strip(), v.strip())

    run_pipeline(args.input, technique=args.technique, output_dir=args.output_dir)
