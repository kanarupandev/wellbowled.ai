# Pipeline Dev Spec v1

Single implementation contract for the Mac execution pipeline. This file is normative. Research and concept docs are non-normative.

## 1. Scope

- Goal: produce upload-quality bowling analysis videos from a single source clip.
- Execution host: Mac with Apple Silicon, 24 GB RAM, MPS available.
- Latency target: <= 60 minutes for a 10-second clip.
- Canonical semantic timebase: source video time in seconds.
- Analysis path must never use RIFE-generated frames.
- Stage 1 model is fixed to `gemini-3-pro-preview`.
- Pipeline design must be independently optimizable by stage and jointly optimizable end to end.
- Phase and segment definitions must be pluggable.
- Multi-technique execution is first-class and must be represented explicitly in manifests and artifacts.

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

Where:

- `OutputQuality`: final visual and analytic usefulness of encoded outputs.
- `Robustness`: ability to survive weak clips, tool errors, and degraded paths.
- `ContractCompliance`: consistency of manifests, timebase, coordinates, and branch artifacts.
- `InsightUsefulness`: usefulness of verdicts and coaching copy.
- `BranchCompleteness`: fraction of resolved technique branches successfully delivered.
- `RuntimePenalty`: normalized cost of latency against budget.
- `FailurePenalty`: severe penalty for terminal or silent failures.

### 2.2 Stage-local objectives

Each stage MUST publish metrics that let it be optimized independently without breaking downstream contracts.

- Stage 0: maximize decode reliability and metadata correctness.
- Stage 1: maximize bowler identification accuracy, timestamp plausibility, and recommendation usefulness.
- Stage 1.5: maximize suitability resolution while minimizing unnecessary expensive work.
- Stage 2: maximize subject isolation continuity and identity stability.
- Stage 3: maximize analysis-safe detail recovery with zero semantic time drift.
- Stage 4: maximize stable landmark coverage for the bowler only.
- Stage 5: maximize physical plausibility and repeatability of computed metrics under a pluggable segment model.
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

Each run MUST create a run root:

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

Every stage MUST emit `<stage_dir>/manifest.json`. The following schema is mandatory.

```json
{
  "run_id": "string",
  "stage_name": "string",
  "stage_version": "string",
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
      "path": "string",
      "required": true,
      "branch_id": null
    }
  ],
  "artifact_paths": {
    "primary": {},
    "secondary": {}
  },
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

### 4.2 Artifact path rules

- `artifact_paths.primary` and `artifact_paths.secondary` MUST use explicit keys, not positional arrays.
- Shared-stage artifacts use branch-independent keys.
- Branch outputs MUST be keyed by `branch_id`.

Example:

```json
{
  "artifact_paths": {
    "primary": {
      "scene_report": "stage1/scene_report.json",
      "plan": "stage1_5/plan.json"
    },
    "secondary": {
      "branches": {
        "branch_speed_gradient": {
          "render_report": "stage7/branch_speed_gradient/render_report.json",
          "encoded_video": "stage8/branch_speed_gradient/upload_ready.mp4"
        }
      }
    }
  }
}
```

## 5. Run Manifest

`run_manifest.json` MUST contain:

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

## 6. Pluggable Technique and Segment System

Technique logic MUST be decoupled from shared pipeline stages.

### 6.1 Technique plugin contract

Each technique plugin MUST declare:

```json
{
  "technique_id": "speed_gradient",
  "required_shared_stages": ["stage0", "stage1", "stage1_5", "stage2", "stage4", "stage5", "stage7", "stage8"],
  "optional_stages": ["stage3", "stage6", "stage7_5"],
  "supported_camera_angles": ["side-on", "behind", "elevated", "front-on", "mixed"],
  "min_pose_quality": 0.80,
  "segment_definition_id": "delivery_phases_v1",
  "render_template_id": "speed_gradient_v1"
}
```

### 6.2 Segment definition contract

Phase and segment definitions MUST be pluggable and versioned.

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

### 6.3 Branch plan contract

The router MUST resolve branch-specific execution plans.

```json
{
  "branch_id": "branch_speed_gradient",
  "technique_id": "speed_gradient",
  "segment_definition_id": "delivery_phases_v1",
  "render_template_id": "speed_gradient_v1",
  "suitability": "supported | degraded | unsupported",
  "requires_stage6": true,
  "requires_rife": false,
  "warnings": []
}
```

### 6.4 Plugin constraints

- Shared stages MUST not contain technique-specific constants except via plugin input.
- Stage 5 MUST accept a segment definition object rather than hard-coded segment names.
- Stage 7 MUST accept a render template id rather than hard-coded layout logic.
- Each branch MUST be independently executable after Stage 1.5.

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

### Fallback

- None.
- Failure is terminal.

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
- `stage0/clip_metadata.json`
- technique plugin registry
- segment definition registry

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
  "branch_plans": [
    {
      "branch_id": "branch_speed_gradient",
      "technique_id": "speed_gradient",
      "segment_definition_id": "delivery_phases_v1",
      "render_template_id": "speed_gradient_v1",
      "suitability": "supported",
      "requires_stage6": true,
      "requires_rife": false,
      "warnings": []
    }
  ],
  "warnings": []
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
assert all(b["segment_definition_id"] is not None for b in branch_plans)
assert all(b["render_template_id"] is not None for b in branch_plans)
```

### Fallback

- If user request conflicts with Gemini recommendation, proceed with warning.
- If all techniques are unsupported, fail terminally with explicit reason.

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
- `stage2/masks/frame_000000.png ...`
- `stage2/isolation_preview.mp4`

### `stage2_metrics.json`

```json
{
  "frames_masked": 0,
  "frames_empty": 0,
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
  "isolation_mode": "sam2_masks | passthrough_full_frame"
}
```

### Processing rules

- Use the first valid Stage 1 center point as primary prompt.
- Generate exactly one binary mask PNG per source frame.
- If `isolation_mode == passthrough_full_frame`, generate synthetic all-white masks with the same dimensions as the source frames. This preserves downstream contracts.
- Mask file names MUST map 1:1 to source frame indices.
- `isolation_preview.mp4` is required.

### Validation

```python
assert mask_file_count == source_frame_count
assert isolation_mode in {"sam2_masks", "passthrough_full_frame"}
if isolation_mode == "sam2_masks":
    assert frames_masked / source_frame_count >= 0.90
    assert min_mask_area_px > 500
    assert no_consecutive_empty_run_length < 3
    assert max_centroid_drift_ratio < 0.15
    assert max_adjacent_mask_area_change_ratio < 0.50
else:
    assert people_count == 1
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

### `stage3_metrics.json`

```json
{
  "upscaled": false,
  "upscale_factor": 1,
  "output_width": 0,
  "output_height": 0,
  "analysis_source": "source_masked_frames | enhanced_frames"
}
```

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

### Processing rules

- Apply Stage 2 mask before pose extraction.
- If Stage 3 is active, it may be used only if frame count remains identical and source-time mapping is unchanged.
- Emit one frame entry per source frame.

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
  "segment_definition_id": "string",
  "delivery_window": {
    "start_s": 0.0,
    "end_s": 0.0
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

1. Load the branch's `segment_definition_id` from `plan.json`.
2. Resolve `delivery_window.start_s = scene_report.timestamps_s[start_key]`.
3. Resolve `delivery_window.end_s = scene_report.timestamps_s[end_key]`.
4. Compute `delivery_window_start_idx = source_frame_index(delivery_window.start_s, source_fps)`.
5. Compute `delivery_window_end_idx = source_frame_index(delivery_window.end_s, source_fps)`.
6. Define `delivery_window_indices = range(delivery_window_start_idx + 1, delivery_window_end_idx + 1)` because velocity uses frame `t-1 -> t`.
7. Resolve each segment's joint list using `joint_source` and `bowling_arm`.
8. Compute per-joint velocities on consecutive source frames only.
9. Apply a 3-frame median filter to each per-joint velocity series.
10. Compute per-segment time series using `aggregate_segment_velocity(..., delivery_window_indices, ...)`.
11. Compute each segment peak as the maximum value in its segment time series inside the delivery window.
12. Compute each transition ratio from the ordered transition list in the segment definition.
13. Compute `peak_order_correct` by comparing the chronological order of observed segment peak times with `expected_peak_order`.
14. Persist the filtered per-joint wrist velocity peaks for joints 15 and 16 in the branch analysis payload so Stage 5.5 can consume them without recomputing hidden state.

### Validation

```python
assert delivery_window["start_s"] < delivery_window["end_s"]
assert all(seg["joint_indices"] for seg in resolved_segments)
assert all(v["velocity_tl_s"] > 0 for v in segment_peaks.values())
assert all(delivery_window["start_s"] <= v["peak_time_s"] <= delivery_window["end_s"] for v in segment_peaks.values())
assert all(0.5 <= r <= 5.0 for r in transition_ratios.values())
assert len(confidence_notes) >= 1
assert segment_definition_id == branch_plan["segment_definition_id"]
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
      "name": "string",
      "result": "pass | warn | fail",
      "detail": "string"
    }
  ]
}
```

### Required checks

Exact definitions:

```python
# Helper definitions
release_frame = floor(scene_report.timestamps_s["release"] * source_fps + 1e-6)
release_posture_tolerance = 0.10  # normalized frame height

# 1. Bowling arm consistency
left_wrist_peak = analysis.supporting_joint_peaks["15"]
right_wrist_peak = analysis.supporting_joint_peaks["16"]
if scene_report.bowling_arm == "right":
    assert right_wrist_peak >= left_wrist_peak
else:
    assert left_wrist_peak >= right_wrist_peak

# 2. Centroid continuity against Stage 1 track
# Stage 2 must persist centroid track in normalized coordinates for each source frame index.
# Interpolate Stage 1 bowler points linearly over source frame indices.
assert max_distance_between(stage2_centroid_track, linearly_interpolated_stage1_track) < 0.30

# 3. Release posture plausibility
# Bowling wrist should not be meaningfully below the bowling-side hip at release.
# right arm => wrist 16, hip 24; left arm => wrist 15, hip 23.
bowling_wrist_idx = 16 if scene_report.bowling_arm == "right" else 15
bowling_hip_idx = 24 if scene_report.bowling_arm == "right" else 23
bowling_wrist_y_at_release = poses.frames[release_frame].landmarks[bowling_wrist_idx][1]
bowling_hip_y_at_release = poses.frames[release_frame].landmarks[bowling_hip_idx][1]
assert bowling_wrist_y_at_release <= bowling_hip_y_at_release + release_posture_tolerance

# 4. Body size continuity
torso_length_mean = poses.pose_quality["torso_length_mean"]
torso_length_stddev = poses.pose_quality["torso_length_stddev"]
assert torso_length_stddev / torso_length_mean < 0.20

# 5. Delivery window sanity
analysis_wrist_peak_time_s = analysis.segment_peaks["wrist"]["peak_time_s"]
assert abs(analysis_wrist_peak_time_s - scene_report.timestamps_s["release"]) <= 0.20
```

### Fallback

- Any failed check marks the branch degraded.
- Failed centroid continuity or release posture SHOULD trigger rerun from Stage 2.

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

### `insight.json`

```json
{
  "branch_id": "string",
  "analysis_validation": "confirmed | suspicious | rejected",
  "isolation_validation": "bowler_correct | wrong_person | unclear",
  "validation_notes": [],
  "coaching_lines": [],
  "social_caption": "string",
  "confidence": 0.0
}
```

### Validation

```python
assert analysis_validation in {"confirmed", "suspicious", "rejected"}
assert isolation_validation in {"bowler_correct", "wrong_person", "unclear"}
assert 0.0 <= confidence <= 1.0
if manifest["status"] != "skipped":
    assert len(coaching_lines) == 3
```

### Fallback

- Optional stage per branch.
- If disabled by branch plan, mark branch skipped.
- If analysis is rejected or wrong person is detected, rerun from Stage 2 for that branch only if shared artifacts are invalidated; otherwise fail the branch.

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
- render plugin from branch plan

### Outputs

- `stage7/manifest.json`
- `stage7/branches/<branch_id>/rendered_frames/`
- `stage7/branches/<branch_id>/render_report.json`

### `render_report.json`

```json
{
  "branch_id": "string",
  "technique": "string",
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
assert analysis_section_contains_non_black_frames
assert verdict_card_matches_analysis_json
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
- `stage7_5/branches/<branch_id>/interpolated_frames/` or passthrough reference

### Validation

```python
if rife_used:
    assert output_frame_count >= input_frame_count * 4
else:
    assert branch_status in {"skipped", "success"}
```

### Fallback

- If RIFE fails, use Stage 7 output directly.

## Stage 8: Encode

### Tool

- FFmpeg

### Inputs

Per branch:

- `stage7/branches/<branch_id>/rendered_frames/` or `stage7_5/branches/<branch_id>/interpolated_frames/`
- `stage7/branches/<branch_id>/render_report.json`

### Outputs

- `stage8/manifest.json`
- `stage8/branches/<branch_id>/upload_ready.mp4`
- `stage8/branches/<branch_id>/encode_report.json`

### `encode_report.json`

```json
{
  "branch_id": "string",
  "codec": "h264",
  "pixel_format": "yuv420p",
  "width": 1080,
  "height": 1920,
  "fps": 30.0,
  "bitrate_bps": 0,
  "duration_s": 0.0,
  "file_size_bytes": 0
}
```

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

### Fallback

- Retry once with safer FFmpeg settings.
- If still unplayable, fail the branch.

## 8. Failure Policy

- `failed`: branch or shared stage cannot continue.
- `degraded`: branch or shared stage may continue with explicit warnings.
- `skipped`: optional stage not executed.
- A terminal failure MUST produce `error_report.json` in the failing stage directory or branch directory.
- Shared-stage failure fails the whole run.
- Branch-stage failure fails only the affected branch unless the invalid artifact is shared.

## 9. Degraded Modes

| Stage | Trigger | Degraded behavior |
|---|---|---|
| Stage 1 | API unavailable | manual scene input |
| Stage 2 | SAM 2 unavailable and one visible person only | synthetic full-frame masks |
| Stage 3 | enhancement artifacts or failure | pass through source masked frames |
| Stage 5 | implausible but non-zero ratios | flag and continue |
| Stage 6 | optional disabled or request failed | render without coaching text |
| Stage 7.5 | RIFE failed | use Stage 7 frames |

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
```

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
