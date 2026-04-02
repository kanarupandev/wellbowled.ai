# Pipeline Dev Spec v1

Single implementation contract for the Mac execution pipeline. This file is normative. All other pipeline docs are non-normative.

## 1. Scope

- Goal: produce upload-quality bowling analysis videos from a single source clip.
- Execution host: Mac with Apple Silicon, 24 GB RAM, MPS available.
- Latency target: <= 60 minutes for a 10-second clip.
- Canonical semantic timebase: source video time in seconds.
- Analysis path must never use RIFE-generated frames.
- Stage 1 model is fixed to `gemini-3-pro-preview`.
- Pipeline design must be independently optimizable by stage and jointly optimizable end to end.
- Phase and segment definitions must be pluggable.
- Multi-technique execution is first-class and branch-explicit.

## 1.1 Version Policy

- `stage_version` in every manifest MUST use semantic versioning `MAJOR.MINOR.PATCH`.
- Increment `PATCH` for wording-only or non-behavioral spec clarifications.
- Increment `MINOR` for backward-compatible contract additions.
- Increment `MAJOR` for breaking schema, path, validation, or execution-order changes.
- `technique_version`, `segment_definition_version`, and `render_template_version` MUST also use semantic versioning.
- A run is valid only if every referenced version exists in the local registry at execution time.

## 1.2 Implementation Environment

The first-pass implementation MUST pin these versions exactly:

```text
python==3.11.x
numpy==1.26.4
opencv-python==4.10.0.84
pillow==10.4.0
mediapipe==0.10.14
torch==2.5.1
torchvision==0.20.1
ffmpeg==7.x CLI runtime
```

If a dependency is changed, the owning stage version MUST be bumped.

## 2. System Model

The pipeline is an optimization problem over quality, robustness, contract integrity, and runtime.

### 2.1 End-to-end objective

For a run `R`, maximize:

```text
OverallScore(R) =
    wq * OutputQuality
  + wr * Robustness
  + wc * ContractCompliance
  + wi * InsightUsefulness
  + wb * BranchCompleteness
  - wt * RuntimePenalty
  - wf * FailurePenalty
```

### 2.2 Stage-local objectives

- Stage 0: maximize decode reliability and metadata correctness.
- Stage 1: maximize bowler identification accuracy, timestamp plausibility, and recommendation usefulness.
- Stage 1.5: maximize suitability resolution while minimizing unnecessary expensive work.
- Stage 2: maximize subject isolation continuity and identity stability.
- Stage 3: maximize analysis-safe detail recovery with zero semantic drift.
- Stage 4: maximize stable landmark coverage for the bowler only.
- Stage 5: maximize physical plausibility and repeatability under a pluggable segment model.
- Stage 5.5: maximize cross-stage inconsistency detection.
- Stage 6: maximize validation quality and coaching specificity.
- Stage 7: maximize render clarity and branch fidelity.
- Stage 7.5: maximize render smoothness without altering analysis semantics.
- Stage 8: maximize playback compatibility and encoded fidelity.

### 2.3 Hard constraints

```python
assert canonical_timebase == "source_seconds"
assert stage4_and_stage5_inputs_do_not_include_rife_outputs
assert all_stage_manifests_share_same_source_hash
assert every_stage_emits_manifest_json
assert every_stage_either_succeeds_skips_degrades_or_fails_explicitly
assert branch_outputs_are_separated_by_branch_id
assert shared_stages_do_not_embed_branch_specific_constants
```

## 3. Execution Contract

### 3.1 Directory layout

```text
<run_root>/
  run_manifest.json
  source/
    input.mp4
  registry/
    technique_plugins.json
    segment_definitions.json
  stage0/
  stage1/
  stage1_5/
  stage2/
  stage3/
  stage4/
  stage5/
  stage5_5/
  stage6/
  stage7/
  stage7_5/
  stage8/
  logs/
```

### 3.2 Canonical timebase

- `canonical_timebase` MUST equal `source_seconds`.
- `source_seconds` is relative to source frame 0.
- Derived frame index MUST be computed as `floor(time_s * source_fps + 1e-6)`.
- No stage may rewrite semantic timestamps from a previous stage.
- Render-only interpolation MUST store derived render fps and render frame count separately from source analysis fps.

### 3.3 Coordinate systems

- `normalized_xy`: float coordinates in `[0.0, 1.0]`, origin top-left.
- `pixel_xy`: source-frame pixel coordinates.
- `landmark_triplet`: `[x, y, visibility]` in normalized coordinates.
- Stage 2 masks MUST match source width and source height.

## 4. Shared Manifest Schema

Every stage MUST emit `<stage_dir>/manifest.json`.

```json
{
  "run_id": "string",
  "stage_name": "string",
  "stage_version": "semver",
  "status": "success | degraded | failed | skipped",
  "source_path": "string",
  "source_hash": "sha256:string",
  "canonical_timebase": "source_seconds",
  "source_video": {
    "width": 0,
    "height": 0,
    "fps": 0.0,
    "duration_seconds": 0.0,
    "frame_count": 0,
    "codec": "string"
  },
  "coordinate_system": {
    "space": "normalized_xy | pixel_xy | mixed",
    "origin": "top_left",
    "x_direction": "right",
    "y_direction": "down"
  },
  "inputs": [
    {
      "logical_name": "string",
      "artifact_role": "string",
      "schema_id": "string",
      "content_type": "string",
      "path": "string",
      "required": true,
      "branch_id": null,
      "plan_ref": null
    }
  ],
  "shared_artifacts": {},
  "branch_artifacts": {},
  "error_artifacts": {},
  "stage_payload_schema_id": "string",
  "confidence": {
    "overall": 0.0,
    "notes": []
  },
  "metrics": {
    "global": {},
    "branches": {}
  },
  "validation": {
    "checks_run": [],
    "checks_passed": [],
    "checks_failed": []
  },
  "fallback": {
    "was_used": false,
    "mode": "none | retry | degraded | manual",
    "reason": "string"
  },
  "optimization": {
    "stage_objective": "string",
    "stage_score": 0.0,
    "end_to_end_risk": "low | medium | high",
    "tunables": []
  },
  "branches": [
    {
      "branch_id": "string",
      "technique_id": "string",
      "plan_ref": "string",
      "segment_definition_id": "string",
      "segment_definition_version": "semver",
      "render_template_id": "string",
      "render_template_version": "semver",
      "branch_dir": "string",
      "branch_manifest_path": "string",
      "branch_report_path": "string",
      "status": "success | degraded | failed | skipped"
    }
  ],
  "provenance": {
    "tool": "string",
    "tool_version": "string",
    "model": "string",
    "runtime": "macos_apple_silicon_mps",
    "started_at": "ISO-8601",
    "completed_at": "ISO-8601"
  }
}
```

### 4.1 Global invariants

```python
assert manifest["canonical_timebase"] == "source_seconds"
assert manifest["source_hash"] == run_manifest["source_hash"]
assert manifest["source_video"]["fps"] == run_manifest["source_video"]["fps"]
assert manifest["source_video"]["frame_count"] == run_manifest["source_video"]["frame_count"]
assert manifest["source_video"]["width"] == run_manifest["source_video"]["width"]
assert manifest["source_video"]["height"] == run_manifest["source_video"]["height"]
```

### 4.2 Branch invariants

For branch-aware stages `stage5` through `stage8`:

```python
router_branch_ids = [b["branch_id"] for b in stage1_5_plan["branch_plans"]]
stage_branch_ids = [b["branch_id"] for b in manifest["branches"]]
assert stage_branch_ids == router_branch_ids
assert all(b["plan_ref"] == f"stage1_5:branch:{b['branch_id']}" for b in manifest["branches"])
assert all(b["branch_dir"] for b in manifest["branches"])
assert all(b["branch_manifest_path"] for b in manifest["branches"])
```

A branch-aware stage MUST preserve the exact Stage 1.5 branch set even when a branch is `failed`, `skipped`, or `degraded`.

## 5. Run Manifest

```json
{
  "run_id": "uuid-or-stable-hash",
  "source_path": "absolute path",
  "source_hash": "sha256:string",
  "user_request": {
    "technique": "speed_gradient | xfactor | kinogram | arm_arc | goniogram | all",
    "render_speed": 0.25,
    "allow_stage6": true
  },
  "source_video": {
    "width": 0,
    "height": 0,
    "fps": 0.0,
    "duration_seconds": 0.0,
    "frame_count": 0,
    "codec": "string"
  }
}
```

## 5.1 Registry Bootstrap Rules

The registry files are required runtime inputs, not optional examples.

`registry/technique_plugins.json` MUST contain at least one valid technique plugin object and MUST be an array of plugin objects.

`registry/segment_definitions.json` MUST contain at least one valid segment definition object and MUST be an array of segment definition objects.

Registry loader rules:

```python
assert technique_plugins_json_exists
assert segment_definitions_json_exists
assert isinstance(technique_plugins, list) and len(technique_plugins) >= 1
assert isinstance(segment_definitions, list) and len(segment_definitions) >= 1
assert unique((p["technique_id"], p["technique_version"]) for p in technique_plugins)
assert unique((d["segment_definition_id"], d["version"]) for d in segment_definitions)
assert every_plugin_references_existing_segment_definition
```

Missing registry files, malformed registry JSON, duplicate ids+versions, or unresolved references MUST fail the run at Stage 1.5.

Minimum bootstrap content:

- `technique_plugins.json` MUST include at least `speed_gradient`.
- `segment_definitions.json` MUST include at least `delivery_phases_v1@1.0.0`.

## 6. Pluggable Technique and Segment System

### 6.1 Technique plugin contract

```json
{
  "technique_id": "speed_gradient",
  "technique_version": "1.0.0",
  "required_shared_stages": ["stage0", "stage1", "stage1_5", "stage2", "stage4", "stage5", "stage7", "stage8"],
  "optional_stages": ["stage3", "stage6", "stage7_5"],
  "supported_camera_angles": ["side-on", "behind", "elevated", "front-on", "mixed"],
  "min_pose_quality": 0.80,
  "segment_definition_id": "delivery_phases_v1",
  "segment_definition_version": "1.0.0",
  "render_template_id": "speed_gradient_v1",
  "render_template_version": "1.0.0"
}
```

### 6.2 Segment definition contract

```json
{
  "segment_definition_id": "delivery_phases_v1",
  "version": "1.0.0",
  "window": {
    "start_key": "back_foot_contact",
    "end_key": "follow_through"
  },
  "segments": [
    {
      "segment_id": "hips",
      "joint_source": "fixed",
      "joint_indices": [23, 24],
      "aggregation": "max"
    },
    {
      "segment_id": "trunk",
      "joint_source": "fixed",
      "joint_indices": [11, 12],
      "aggregation": "max"
    },
    {
      "segment_id": "arm",
      "joint_source": "bowling_arm",
      "joint_indices_by_arm": {
        "right": [14, 16],
        "left": [13, 15]
      },
      "aggregation": "max"
    },
    {
      "segment_id": "wrist",
      "joint_source": "bowling_arm",
      "joint_indices_by_arm": {
        "right": [16],
        "left": [15]
      },
      "aggregation": "max"
    }
  ],
  "transitions": [
    ["hips", "trunk"],
    ["trunk", "arm"],
    ["arm", "wrist"]
  ],
  "expected_peak_order": ["hips", "trunk", "arm", "wrist"]
}
```

### 6.3 Canonical branch plan contract

Stage 1.5 is the single source of truth for branch resolution.

```json
{
  "branch_id": "branch_speed_gradient",
  "technique_id": "speed_gradient",
  "technique_version": "1.0.0",
  "segment_definition_id": "delivery_phases_v1",
  "segment_definition_version": "1.0.0",
  "render_template_id": "speed_gradient_v1",
  "render_template_version": "1.0.0",
  "required_stages": ["stage5", "stage7", "stage8"],
  "optional_stages": ["stage6", "stage7_5"],
  "suitability": "supported | degraded | unsupported",
  "degraded": false,
  "terminal_failed": false,
  "branch_output_root": "branches/branch_speed_gradient",
  "required_inputs": {
    "analysis": "stage5/branches/branch_speed_gradient/analysis.json",
    "render_report": "stage7/branches/branch_speed_gradient/render_report.json"
  },
  "expected_outputs": {
    "render_frames": "stage7/branches/branch_speed_gradient/rendered_frames",
    "encoded_video": "stage8/branches/branch_speed_gradient/upload_ready.mp4"
  },
  "plan_ref": "stage1_5:branch:branch_speed_gradient",
  "warnings": []
}
```

## 7. Stage Definitions

## Stage 0: Input Validation

### Tool

- Python 3.11
- OpenCV
- ffprobe optional

### Inputs

- `source/input.mp4`

### Outputs

- `stage0/manifest.json`
- `stage0/clip_metadata.json`
- `stage0/contact_sheet.jpg`

### `clip_metadata.json`

```json
{
  "source_path": "string",
  "source_hash": "sha256:string",
  "width": 0,
  "height": 0,
  "fps": 0.0,
  "duration_seconds": 0.0,
  "frame_count": 0,
  "codec": "string",
  "contact_sheet_frame_times_s": [0.0]
}
```

### Validation

```python
assert decode_ok
assert 3.0 <= duration_seconds <= 60.0
assert fps >= 15.0
assert min(width, height) >= 240
assert frame_count >= 45
```

## Stage 1: Scene Understanding

### Tool

- `gemini-3-pro-preview`

### Inputs

- `stage0/contact_sheet.jpg`
- `stage0/clip_metadata.json`

### Outputs

- `stage1/manifest.json`
- `stage1/scene_report.json`

### `scene_report.json`

```json
{
  "bowler_id": "string",
  "bowling_arm": "right | left",
  "bowler_center_points": [
    {
      "frame_time_s": 0.0,
      "x": 0.0,
      "y": 0.0
    }
  ],
  "timestamps_s": {
    "run_up_start": 0.0,
    "back_foot_contact": 0.0,
    "front_foot_contact": 0.0,
    "release": 0.0,
    "follow_through": 0.0
  },
  "camera_angle": "behind | side-on | front-on | elevated | mixed",
  "clip_quality": 0,
  "people_count": 0,
  "recommended_techniques": [],
  "model_used": "gemini-3-pro-preview",
  "stage1_confidence": 0.0
}
```

### Validation

```python
assert len(bowler_center_points) >= 1
assert bowling_arm in {"left", "right"}
assert 1 <= clip_quality <= 10
assert 0.0 <= stage1_confidence <= 1.0
assert timestamps.run_up_start < timestamps.back_foot_contact
assert timestamps.back_foot_contact < timestamps.front_foot_contact
assert timestamps.front_foot_contact <= timestamps.release
assert timestamps.release < timestamps.follow_through
assert timestamps.follow_through <= duration_seconds
assert all(0.0 <= p["x"] <= 1.0 and 0.0 <= p["y"] <= 1.0 for p in bowler_center_points)
assert clip_quality >= 5
```

### Fallback

- Retry once with regenerated contact sheet frames.
- If API error persists, require `stage1/manual_input.json` and mark `status=degraded`.

## Stage 1.5: Router

### Tool

- Python logic only

### Inputs

- `run_manifest.json`
- `stage1/scene_report.json`
- `registry/technique_plugins.json`
- `registry/segment_definitions.json`

### Outputs

- `stage1_5/manifest.json`
- `stage1_5/plan.json`

### `plan.json`

```json
{
  "user_requested": "string",
  "gemini_recommended": [],
  "requires_sam2": true,
  "requires_upscale": false,
  "analysis_fps": 0.0,
  "render_speed": 0.25,
  "render_target": {
    "width": 1080,
    "height": 1920,
    "fps": 30
  },
  "branch_plans": []
}
```

### Router rules

```python
if user_requested == "all":
    branch_plans = [make_branch_plan(plugin) for plugin in plugins if suitability(plugin) in {"supported", "degraded"}]
else:
    branch_plans = [make_branch_plan(plugin_by_id[user_requested])] if suitability(plugin_by_id[user_requested]) != "unsupported" else []

assert len(branch_plans) >= 1
assert analysis_fps == source_fps
assert render_target["fps"] == 30
assert len({b["branch_id"] for b in branch_plans}) == len(branch_plans)
assert all(b["plan_ref"] == f"stage1_5:branch:{b['branch_id']}" for b in branch_plans)
```

## Stage 2: Bowler Isolation

### Tool

- SAM 2 Large on Mac MPS

### Inputs

- `source/input.mp4`
- `stage1/scene_report.json`
- `stage1_5/plan.json`

### Outputs

- `stage2/manifest.json`
- `stage2/stage2_metrics.json`
- `stage2/centroid_track.json`
- `stage2/masks/frame_000000.png ...`
- `stage2/isolation_preview.mp4`

### `stage2_metrics.json`

```json
{
  "frames_masked": 0,
  "frames_empty": 0,
  "mask_count": 0,
  "mask_width": 0,
  "mask_height": 0,
  "avg_mask_area_px": 0.0,
  "min_mask_area_px": 0.0,
  "max_mask_area_px": 0.0,
  "mask_area_stddev_px": 0.0,
  "max_centroid_drift_ratio": 0.0,
  "max_adjacent_mask_area_change_ratio": 0.0,
  "sam2_model": "sam2.1_hiera_large",
  "sam2_prompt": {
    "frame_time_s": 0.0,
    "x": 0.0,
    "y": 0.0
  },
  "isolation_mode": "sam2_masks | passthrough_full_frame",
  "synthetic_mask_fill_value": 255,
  "single_person_gate_passed": false
}
```

### Mask contract

- One PNG mask per source frame.
- Same width and height as source.
- Pixel values MUST be only `0` or `255`.
- Downstream stages MUST treat all Stage 2 masks identically.
- No alternate no-mask mode exists downstream.
- If `isolation_mode == passthrough_full_frame`, every pixel in every mask MUST be `255`.

### `centroid_track.json`

```json
{
  "coordinate_system": "normalized_xy",
  "frames": [
    {
      "frame_index": 0,
      "x": 0.0,
      "y": 0.0
    }
  ]
}
```

### Validation

```python
assert mask_count == source_frame_count
assert mask_width == source_width
assert mask_height == source_height
assert isolation_mode in {"sam2_masks", "passthrough_full_frame"}
assert valid_mask_values_only in {0, 255}
if isolation_mode == "sam2_masks":
    assert frames_masked / source_frame_count >= 0.90
    assert min_mask_area_px > 500
    assert no_consecutive_empty_run_length < 3
    assert max_centroid_drift_ratio < 0.15
    assert max_adjacent_mask_area_change_ratio < 0.50
else:
    assert single_person_gate_passed is True
    assert synthetic_mask_fill_value == 255
    assert all_masks_are_full_frame_white is True
```

### Fallback

- Retry with next Stage 1 center point.
- Retry with manual point if available.
- If SAM 2 unavailable and `people_count == 1`, set `isolation_mode = passthrough_full_frame` and continue degraded.
- Otherwise fail.

## Stage 3: Analysis-Safe Enhancement

### Tool

- Real-ESRGAN 2x only

### Inputs

- `source/input.mp4`
- `stage2/masks/`
- `stage1_5/plan.json`

### Outputs

- `stage3/manifest.json`
- `stage3/stage3_metrics.json`
- `stage3/enhanced_frames/` or passthrough reference

### Validation

```python
if upscaled:
    assert output_width == source_width * upscale_factor
    assert output_height == source_height * upscale_factor
assert analysis_source in {"source_masked_frames", "enhanced_frames"}
```

### Fallback

- If enhancement introduces artifacts or fails, set `upscaled=false` and pass through source masked frames.

## Stage 4: Pose Extraction

### Tool

- MediaPipe Pose Landmarker Heavy

### Inputs

- `source/input.mp4`
- `stage2/masks/`
- optional `stage3/enhanced_frames/`
- `stage1/scene_report.json`

### Mask application rule

For each source frame and corresponding Stage 2 mask:

```python
assert mask_pixel in {0, 255}
masked_rgb = source_rgb if mask_pixel == 255 else (0, 0, 0)
```

No alpha compositing, threshold estimation, or alternate blend mode is allowed.

### Outputs

- `stage4/manifest.json`
- `stage4/poses.json`

### `poses.json`

```json
{
  "canonical_fps": 0.0,
  "frames": [
    {
      "index": 0,
      "time_s": 0.0,
      "detected": true,
      "landmarks": [[0.0, 0.0, 0.0]],
      "torso_length": 0.0
    }
  ],
  "pose_quality": {
    "detection_rate": 0.0,
    "shoulder_hip_visibility_rate": 0.0,
    "bowling_arm_wrist_visibility_delivery_window": 0.0,
    "torso_length_mean": 0.0,
    "torso_length_stddev": 0.0,
    "max_landmark_jump_ratio": 0.0,
    "determinism_verified": true
  }
}
```

### Validation

```python
assert len(frames) == source_frame_count
assert pose_quality["detection_rate"] >= 0.80
assert pose_quality["shoulder_hip_visibility_rate"] >= 0.85
assert pose_quality["bowling_arm_wrist_visibility_delivery_window"] >= 0.80
assert pose_quality["torso_length_stddev"] / pose_quality["torso_length_mean"] < 0.20
assert pose_quality["max_landmark_jump_ratio"] < 0.15
assert pose_quality["determinism_verified"] is True
```

### Fallback

- Retry once using source masked frames if enhanced frames were used.
- If detection remains < 0.80, fail for measurement techniques.
- Non-measurement techniques may continue only if router marked them degraded.

## Stage 5: Analysis

### Tool

- Python with NumPy

### Inputs

- `stage4/poses.json`
- `stage1/scene_report.json`
- `stage1_5/plan.json`
- chosen segment definition per branch

### Outputs

- `stage5/manifest.json`
- `stage5/branches/<branch_id>/analysis.json`

### `analysis.json`

```json
{
  "canonical_timebase": "source_seconds",
  "branch_id": "string",
  "plan_ref": "string",
  "segment_definition_id": "string",
  "segment_definition_version": "semver",
  "delivery_window": {
    "start_s": 0.0,
    "end_s": 0.0,
    "start_idx": 0,
    "end_idx": 0
  },
  "resolved_segments": [
    {
      "segment_id": "string",
      "joint_indices": [0],
      "aggregation": "max"
    }
  ],
  "segment_peaks": {},
  "transition_ratios": {},
  "supporting_joint_peaks": {
    "15": 0.0,
    "16": 0.0
  },
  "peak_order_correct": true,
  "peak_order_rule": "stable_sort_by_peak_time_then_expected_order_index",
  "total_chain_amplification": 0.0,
  "weakest_link": "string",
  "camera_angle": "string",
  "confidence_notes": [],
  "flags": []
}
```

### Exact formulas

```python
def midpoint(a, b):
    return ((a[0] + b[0]) / 2.0, (a[1] + b[1]) / 2.0)

def distance(a, b):
    dx = a[0] - b[0]
    dy = a[1] - b[1]
    return (dx * dx + dy * dy) ** 0.5

def torso_length(landmarks):
    return distance(midpoint(landmarks[11], landmarks[12]), midpoint(landmarks[23], landmarks[24]))

def joint_velocity(prev_landmarks, curr_landmarks, joint_idx, fps, torso_len):
    return distance(prev_landmarks[joint_idx], curr_landmarks[joint_idx]) * fps / torso_len

def resolve_segment_joint_indices(segment_def, bowling_arm):
    if segment_def["joint_source"] == "fixed":
        return segment_def["joint_indices"]
    return segment_def["joint_indices_by_arm"][bowling_arm]

def aggregate_segment_velocity(joint_indices, per_joint_velocity_by_frame, frame_indices, aggregation):
    if aggregation == "max":
        return [max(per_joint_velocity_by_frame[j][t] for j in joint_indices) for t in frame_indices]
    raise ValueError("unsupported aggregation")

def source_frame_index(time_s, fps):
    return floor(time_s * fps + 1e-6)
```

### Processing rules

For each branch independently:

1. Load branch plan from `stage1_5/plan.json` by `branch_id`.
2. Load the exact segment definition by id and version.
3. Resolve `delivery_window.start_s = scene_report.timestamps_s[start_key]`.
4. Resolve `delivery_window.end_s = scene_report.timestamps_s[end_key]`.
5. Compute `delivery_window.start_idx = source_frame_index(start_s, source_fps)`.
6. Compute `delivery_window.end_idx = source_frame_index(end_s, source_fps)`.
7. Define `delivery_window_indices = range(start_idx + 1, end_idx + 1)`.
8. Resolve each segment's joint list using `joint_source` and `bowling_arm`.
9. Compute per-joint velocities on consecutive source frames only.
10. Apply a 3-frame median filter to each per-joint velocity series.
11. Compute per-segment time series using `aggregate_segment_velocity`.
12. Compute each segment peak as the maximum value in the delivery window.
13. If multiple frames share the same max value, choose the earliest frame.
14. If any expected segment has no valid series, mark branch `failed`.
15. Compute each transition ratio from the ordered transition list.
16. Compute `peak_order_correct` by stable-sorting observed segment peaks by `(peak_time_s, expected_order_index)` and comparing to `expected_peak_order`.
17. Persist supporting wrist peaks for joints `15` and `16`.

### Validation

```python
expected_segments = [s["segment_id"] for s in segment_definition["segments"]]
expected_transitions = [f"{a}->{b}" for a, b in segment_definition["transitions"]]
assert delivery_window["start_s"] < delivery_window["end_s"]
assert [s["segment_id"] for s in resolved_segments] == expected_segments
assert all(seg["joint_indices"] for seg in resolved_segments)
assert set(segment_peaks.keys()) == set(expected_segments)
assert set(transition_ratios.keys()) == set(expected_transitions)
assert all(v["velocity_tl_s"] > 0 for v in segment_peaks.values())
assert all(delivery_window["start_s"] <= v["peak_time_s"] <= delivery_window["end_s"] for v in segment_peaks.values())
assert all(0.5 <= r <= 5.0 for r in transition_ratios.values())
assert len(confidence_notes) >= 1
assert segment_definition_id == branch_plan["segment_definition_id"]
assert segment_definition_version == branch_plan["segment_definition_version"]
```

### Fallback

- If ratios are implausible, mark branch degraded, append flags, and continue.
- If all segment velocities are near zero, fail the branch.

## Stage 5.5: Cross-Stage Sanity Checks

### Tool

- Python assertions

### Inputs

- `stage1/scene_report.json`
- `stage2/stage2_metrics.json`
- `stage2/centroid_track.json`
- `stage4/poses.json`
- `stage5/branches/<branch_id>/analysis.json`

### Outputs

- `stage5_5/manifest.json`
- `stage5_5/branches/<branch_id>/sanity_report.json`

### `sanity_report.json`

```json
{
  "passed": true,
  "checks": [
    {
      "check_id": "string",
      "name": "string",
      "result": "pass | warn | fail",
      "measured_value": 0.0,
      "threshold": 0.0,
      "comparison": "<= | >= | ==",
      "detail": "string",
      "rerun_required": false
    }
  ]
}
```

### Required checks

```python
release_frame = floor(scene_report.timestamps_s["release"] * source_fps + 1e-6)
release_posture_tolerance = 0.10
left_wrist_peak = analysis.supporting_joint_peaks["15"]
right_wrist_peak = analysis.supporting_joint_peaks["16"]
if scene_report.bowling_arm == "right":
    assert right_wrist_peak >= left_wrist_peak
else:
    assert left_wrist_peak >= right_wrist_peak
assert max_distance_between(stage2_centroid_track, linearly_interpolated_stage1_track) < 0.30
bowling_wrist_idx = 16 if scene_report.bowling_arm == "right" else 15
bowling_hip_idx = 24 if scene_report.bowling_arm == "right" else 23
bowling_wrist_y_at_release = poses.frames[release_frame].landmarks[bowling_wrist_idx][1]
bowling_hip_y_at_release = poses.frames[release_frame].landmarks[bowling_hip_idx][1]
assert bowling_wrist_y_at_release <= bowling_hip_y_at_release + release_posture_tolerance
torso_length_mean = poses.pose_quality["torso_length_mean"]
torso_length_stddev = poses.pose_quality["torso_length_stddev"]
assert torso_length_stddev / torso_length_mean < 0.20
analysis_wrist_peak_time_s = analysis.segment_peaks["wrist"]["peak_time_s"]
assert abs(analysis_wrist_peak_time_s - scene_report.timestamps_s["release"]) <= 0.20
```

### Failure policy

- Any failed check marks the branch degraded.
- Failed centroid continuity or failed release posture MUST trigger rerun from Stage 2.
- Other failed checks continue degraded with `rerun_required=false`.

## Stage 6: Insight and Validation

### Tool

- `gemini-3-pro-preview`

### Inputs

Per branch:

- `stage5/branches/<branch_id>/analysis.json`
- peak frame image with mask applied
- `stage1/scene_report.json`

### Outputs

- `stage6/manifest.json`
- `stage6/branches/<branch_id>/insight.json`

### Failure policy

- Optional stage per branch.
- If disabled by branch plan, mark branch skipped.
- If analysis is rejected or wrong person is detected, mark branch failed.
- Stage 6 MUST NOT request rerun of shared Stage 2 artifacts. Shared artifact reruns are only triggered by Stage 5.5.

## Stage 7: Render

### Tool

- Python
- Pillow
- OpenCV

### Inputs

Shared:

- `source/input.mp4`
- `stage2/masks/`
- `stage4/poses.json`
- `stage1_5/plan.json`

Per branch:

- `stage5/branches/<branch_id>/analysis.json`
- optional `stage6/branches/<branch_id>/insight.json`
- exact render template payload resolved by id and version

### Outputs

- `stage7/manifest.json`
- `stage7/branches/<branch_id>/rendered_frames/`
- `stage7/branches/<branch_id>/render_report.json`

### `render_report.json`

```json
{
  "branch_id": "string",
  "plan_ref": "string",
  "technique": "string",
  "render_template_id": "string",
  "render_template_version": "semver",
  "analysis_ref": "string",
  "insight_ref": "string | null",
  "total_frames": 0,
  "duration_s": 0.0,
  "output_fps": 30,
  "rife_requested": false,
  "sections": {
    "title": 0.0,
    "analysis": 0.0,
    "verdict": 0.0,
    "end": 0.0
  }
}
```

### Validation

```python
assert total_frames > 0
assert output_fps == 30
assert 10.0 <= duration_s <= 60.0
# analysis_section_contains_non_black_frames
assert any(sum(pixel) > 0 for frame in sample_analysis_frames for pixel in frame)
# verdict_card_matches_analysis_json
assert rendered_verdict_numeric_values == analysis_json_numeric_values
```

### Fallback

- If Stage 6 is skipped or fails, use deterministic template copy and continue.

## Stage 7.5: Render-Time Interpolation

### Tool

- RIFE

### Inputs

Per branch:

- `stage7/branches/<branch_id>/rendered_frames/`
- `stage7/branches/<branch_id>/render_report.json`
- branch plan

### Outputs

- `stage7_5/manifest.json`
- `stage7_5/branches/<branch_id>/interpolated_frames/`
- `stage7_5/branches/<branch_id>/passthrough_ref.txt`

### Selection contract

- Branch directory MUST always exist.
- If RIFE succeeds, `interpolated_frames/` is authoritative.
- If RIFE is skipped, degraded, or failed, `passthrough_ref.txt` MUST point to the authoritative Stage 7 frame directory.

### Validation

```python
if rife_used:
    assert output_frame_count >= input_frame_count * 4
else:
    assert branch_status in {"skipped", "success", "degraded", "failed"}
    assert passthrough_ref_exists is True
```

## Stage 8: Encode

### Tool

- FFmpeg

### Inputs

Per branch:

- `stage7_5` authoritative frames if `stage7_5` status is `success`
- otherwise Stage 7 rendered frames
- `stage7/branches/<branch_id>/render_report.json`

### Selection rule

```python
if stage7_5_branch_status == "success":
    encode_input = stage7_5_interpolated_frames
else:
    encode_input = stage7_rendered_frames
```

### Outputs

- `stage8/manifest.json`
- `stage8/branches/<branch_id>/upload_ready.mp4`
- `stage8/branches/<branch_id>/encode_report.json`
- `stage8/branches/<branch_id>/error_report.json` on failure

### Validation

```python
assert codec == "h264"
assert pixel_format == "yuv420p"
assert width == 1080 and height == 1920
assert fps == 30.0
assert bitrate_bps >= 4_000_000
assert abs(duration_s - render_report.duration_s) <= 0.1
assert file_size_bytes < 100 * 1024 * 1024
assert playable is True
```

## 8. Failure Policy

- `failed`: stage or branch cannot continue.
- `degraded`: stage or branch may continue with explicit warnings.
- `skipped`: optional stage not executed.
- Shared-stage failure fails the whole run.
- Branch-stage failure fails only that branch.
- Every failed branch MUST still emit:
  - branch directory
  - branch manifest entry
  - `error_report.json`
  - final branch status in the parent stage manifest

## 9. Degraded Modes

| Stage | Trigger | Result status | Required fields | Downstream interpretation |
|---|---|---|---|---|
| Stage 1 | API unavailable | `degraded` | manual input ref | continue |
| Stage 2 | SAM 2 unavailable and one visible person only | `degraded` | `isolation_mode=passthrough_full_frame`, synthetic mask fields | continue |
| Stage 3 | enhancement artifacts or failure | `degraded` | `upscaled=false` | continue |
| Stage 5 | implausible but non-zero ratios | `degraded` | flags, confidence notes | continue |
| Stage 6 | optional disabled or request failed | `skipped` or `degraded` | branch status | continue |
| Stage 7.5 | RIFE failed | `degraded` | passthrough ref | continue |

## 10. Non-Negotiable Assertions

```python
assert stage1_scene_report.model_used == "gemini-3-pro-preview"
assert all_stage_manifests_share_same_source_hash
assert no_stage_changes_canonical_timebase
assert stage4_and_stage5_never_use_rife_outputs
assert stage7_verdict_values_equal_stage5_analysis_values
assert plugins_are_selected_by_router_not_by_shared_stages
assert segment_definitions_are_loaded_from_registry_not_hard_coded_in_stage5
assert branch_plans_are_explicit_and_one_to_one_with_branch_outputs
assert degraded_no_isolation_mode_still_emits_masks
assert branch_ids_are_stable_across_all_branch_aware_stages
assert branch_aware_stage_manifests_reference_router_plan_refs
```

## 10.1 Logging Contract

The `logs/` directory is mandatory.

Required files:

```text
logs/run.log
logs/stage0.log
logs/stage1.log
logs/stage1_5.log
logs/stage2.log
logs/stage3.log
logs/stage4.log
logs/stage5.log
logs/stage5_5.log
logs/stage6.log
logs/stage7.log
logs/stage7_5.log
logs/stage8.log
```

Log format MUST be line-delimited text with this structure:

```text
<ISO-8601> level=<DEBUG|INFO|WARNING|ERROR> run_id=<id> stage=<stage> branch_id=<id|none> event=<token> message=<free text>
```

Required logging rules:

- Shared stages use `branch_id=none`.
- Branch-aware stages MUST log once per branch transition into `success`, `degraded`, `failed`, or `skipped`.
- Every retry, fallback activation, and rerun trigger MUST emit a `WARNING` or `ERROR` line.
- Every terminal failure MUST emit an `ERROR` line containing the path to `error_report.json`.
- Python implementation MAY use the standard `logging` module, but emitted lines MUST conform to the required format.

## 11. Implementation Order

1. Stage 0
2. Stage 1
3. Stage 1.5
4. Stage 2
5. Stage 4
6. Stage 5
7. Stage 5.5
8. Stage 7
9. Stage 8
10. Stage 3
11. Stage 6
12. Stage 7.5

Rationale: build the shared measurement backbone first, then add optional optimization stages and branch polish.
