# Pipeline Contract v1 — CANONICAL (supersedes all other docs)

All other pipeline docs (pipeline_optimized.md, pipeline_tools_research.md, etc.) are research/history. THIS is the single source of truth.

## Performance Target
1 hour accepted latency for a 10-second clip. Quality over speed.

## Execution Environment
**All stages run on Mac (24GB RAM, Apple Silicon MPS).**
Linux is for research/design only. Mac is the execution machine.
SAM 2 benefits from MPS acceleration. All other tools (MediaPipe, OpenCV, FFmpeg, Pillow) run natively on Mac.

## Canonical Timebase
**All timestamps are in source-seconds (float).** Derived frame indices are computed from `frame_idx = int(time_seconds × source_fps)`. No stage changes this. RIFE interpolation is render-only, never analysis input.

---

## STAGE 0: INPUT VALIDATION

**Tool:** Python (cv2)
**Input:** Raw MP4 file path
**Process:** Verify file, extract metadata, generate contact sheet
**Output:**
```
stage0/
├── clip_metadata.json
│   {
│     source_path: "/path/to/clip.mp4",
│     source_hash: "sha256:abc123...",
│     width: 640,
│     height: 360,
│     fps: 30.0,
│     duration_seconds: 10.0,
│     frame_count: 300,
│     codec: "h264"
│   }
└── contact_sheet.jpg  (6 frames, labeled with timestamps)
```
**Validation:**
- [ ] File decodes without error
- [ ] Duration 3-60 seconds
- [ ] FPS ≥ 15
- [ ] Resolution ≥ 240p
- [ ] FAIL → stop with error message

---

## STAGE 1: SCENE UNDERSTANDING

**Tool:** Gemini 3 Preview Pro (1 API call)
**Input:** contact_sheet.jpg + clip_metadata.json
**Process:** Analyze contact sheet, identify bowler, estimate phases
**Output:**
```
stage1/
└── scene_report.json
    {
      bowler_id: "Dale Steyn" | "unknown_right_arm_medium_fast",
      bowling_arm: "right" | "left",
      bowler_center_points: [
        {frame_time_s: 0.5, x: 0.45, y: 0.6},
        {frame_time_s: 1.0, x: 0.40, y: 0.55},
        ...
      ],
      timestamps_s: {
        run_up_start: 0.5,
        back_foot_contact: 1.1,
        front_foot_contact: 1.3,
        release: 1.5,
        follow_through: 1.8
      },
      camera_angle: "behind" | "side-on" | "front-on" | "elevated",
      clip_quality: 7,           // 1-10
      people_count: 5,
      recommended_techniques: ["speed_gradient", "arm_arc"],
      model_used: "gemini-3-pro-preview"
    }
```
**Validation:**
- [ ] bowler_center_points has ≥ 1 entry
- [ ] All timestamps_s in chronological order
- [ ] clip_quality ≥ 5
- [ ] BFC < release < follow_through
- [ ] FAIL quality < 5 → stop "Clip quality too low for analysis"
- [ ] FAIL no bowler → stop "No bowler detected"

**Note on model choice:** Using Pro (not Flash) because this stage feeds ALL downstream stages. Wrong timestamps corrupt everything. Cost difference is negligible (~$0.009) at 1-10 clips/day. If testing shows Flash is equally accurate, downgrade later.

---

## STAGE 1.5: TECHNIQUE ROUTER

**Tool:** Python (logic only, no ML)
**Input:** scene_report.json + user --technique flag
**Process:** Resolve what to run
**Output:**
```
stage1_5/
└── plan.json
    {
      user_requested: "speed_gradient" | "xfactor" | "all",
      gemini_recommended: ["speed_gradient", "arm_arc"],
      resolved_techniques: ["speed_gradient"],
      requires_sam2: true,
      requires_upscale: false,    // source >= 480p
      requires_rife: false,       // render-only if needed
      analysis_fps: 30.0,         // always source fps
      render_speed: 0.25          // slo-mo factor for rendering
    }
```
**Validation:**
- [ ] resolved_techniques is non-empty
- [ ] If user_requested technique not in gemini_recommended, warn but proceed

---

## STAGE 2: BOWLER ISOLATION

**Tool:** SAM 2 Large (Mac MPS or Linux CPU)
**Input:** Raw clip + scene_report.json (bowler_center_points[0])
**Process:** Segment and track bowler through all frames
**Output:**
```
stage2/
├── stage2_manifest.json
│   {
│     source_hash: "sha256:abc123...",  // must match stage0
│     source_fps: 30.0,
│     source_width: 640,
│     source_height: 360,
│     frame_count: 300,
│     frames_masked: 285,
│     frames_empty: 15,
│     avg_mask_area_px: 12500,
│     min_mask_area_px: 8200,
│     max_mask_area_px: 18000,
│     mask_area_stddev: 2100,
│     sam2_model: "sam2.1_hiera_large",
│     sam2_prompt: {x: 0.45, y: 0.6, frame_time_s: 0.5}
│   }
├── masks/
│   ├── frame_000000.png   // binary mask, same resolution as source
│   ├── frame_000001.png
│   └── ...
└── isolation_preview.mp4  // optional: bowler on green screen for visual check
```
**Validation:**
- [ ] source_hash matches stage0 clip_metadata.json
- [ ] frames_masked / frame_count ≥ 0.90
- [ ] min_mask_area_px > 500
- [ ] No consecutive 3+ empty frames (bowler shouldn't vanish for 100ms+)
- [ ] Mask centroid drift between consecutive frames < 15% of frame width
- [ ] Mask area change between consecutive frames < 50%
- [ ] FAIL < 90% coverage → "SAM 2 lost the bowler"
- [ ] FAIL centroid drift → "SAM 2 jumped to wrong person"

**Fallback:** If validation fails, re-prompt SAM 2 with a different bowler_center_point from scene_report (try next frame's point).

---

## STAGE 3: ENHANCEMENT (conditional)

**Tool:** Real-ESRGAN (upscale only, if needed)
**Input:** stage2/masks/ + original clip + plan.json
**Process:**
- IF plan.requires_upscale → Real-ESRGAN 2x on masked bowler region
- ELSE → passthrough (symlink to stage2)
**Output:**
```
stage3/
├── stage3_manifest.json
│   {
│     upscaled: true | false,
│     upscale_factor: 2,
│     output_width: 1280,
│     output_height: 720
│   }
└── (enhanced masks or symlink to stage2/masks/)
```

**RIFE is NOT used here.** Interpolation is render-only (Stage 7). Analysis always runs on source-fps frames to measure real motion, not model-generated motion.

**Validation:**
- [ ] If upscaled: output resolution = input × upscale_factor
- [ ] No visual artifacts on spot-check frames

---

## STAGE 4: POSE EXTRACTION

**Tool:** MediaPipe PoseLandmarker (heavy model)
**Input:** Original clip + stage2/masks/ (apply mask before detection)
**Process:** For each frame, apply mask (black out non-bowler), run MediaPipe
**Output:**
```
stage4/
├── stage4_manifest.json
│   {
│     source_hash: "sha256:abc123...",
│     source_fps: 30.0,
│     frames_total: 300,
│     frames_detected: 270,
│     detection_rate: 0.90,
│     determinism_verified: true,
│     mediapipe_model: "pose_landmarker_heavy"
│   }
└── poses.json
    {
      canonical_fps: 30.0,
      frames: [
        {
          index: 0,
          time_s: 0.000,
          detected: true,
          landmarks: [[x, y, visibility], ...],  // 33 points, normalized 0-1
          torso_length: 0.18     // mid_shoulder to mid_hip distance (normalized)
        },
        ...
      ]
    }
```
**Validation:**
- [ ] detection_rate ≥ 0.80
- [ ] No landmark jump > 15% of frame between consecutive detected frames
- [ ] Key joints (11,12,23,24 — shoulders/hips) visible in ≥ 85% of detected frames
- [ ] Bowling arm (from scene_report) wrist joint visible in ≥ 80% of delivery window
- [ ] Torso length consistent (stddev < 20% of mean) — catches person-switching
- [ ] Determinism: run twice, results identical
- [ ] FAIL detection < 80% → "Pose detection unreliable on this clip"
- [ ] FAIL torso inconsistent → "Tracking jumped between people"

---

## STAGE 5: ANALYSIS

**Tool:** Python (numpy, no ML)
**Input:** poses.json + scene_report.json
**Process:**
- Per-joint velocity = distance(landmarks[t], landmarks[t-1]) × canonical_fps / torso_length
- 3-frame median smoothing
- Window to delivery stride: timestamps_s.back_foot_contact → timestamps_s.follow_through
- Peak velocity per segment:
  - Hips: joints [23, 24]
  - Trunk: joints [11, 12]
  - Bowling arm: joints [13→15] or [14→16] based on bowling_arm
  - Wrist: joint [15] or [16] based on bowling_arm
- Transfer ratios: peak(next_segment) / peak(current_segment)
- Peak timing sequence
**Output:**
```
stage5/
└── analysis.json
    {
      canonical_timebase: "source_seconds",
      delivery_window: {start_s: 1.1, end_s: 1.8},
      bowling_arm_joints: {shoulder: 12, elbow: 14, wrist: 16},
      segment_peaks: {
        Hips:  {velocity_tl_s: 3.2, peak_time_s: 1.10, peak_frame: 33},
        Trunk: {velocity_tl_s: 4.8, peak_time_s: 1.30, peak_frame: 39},
        Arm:   {velocity_tl_s: 7.1, peak_time_s: 1.43, peak_frame: 43},
        Wrist: {velocity_tl_s: 9.5, peak_time_s: 1.50, peak_frame: 45}
      },
      transfer_ratios: {
        "Hips → Trunk": 1.50,
        "Trunk → Arm": 1.48,
        "Arm → Wrist": 1.34
      },
      peak_order_correct: true,
      total_chain_amplification: 2.97,
      weakest_link: "Arm → Wrist",
      camera_angle: "side-on",
      confidence_notes: [
        "Side-on angle: velocity measurement reliable for lateral motion",
        "Depth-direction motion underestimated from this angle"
      ]
    }
```
**Validation:**
- [ ] All velocities > 0 within delivery window
- [ ] All transfer ratios between 0.5 and 5.0
- [ ] Peak times within delivery window
- [ ] Segment peaks are in plausible order for the camera angle
- [ ] confidence_notes populated based on camera_angle from scene_report
- [ ] FAIL ratio > 5.0 → "Implausible measurement, check pose quality"
- [ ] FAIL all velocities near 0 → "No motion detected in delivery window"

**NOTE:** "Wrist must be fastest" removed as hard gate. Camera angle may cause exceptions. Replaced with angle-aware plausibility check.

---

## STAGE 6: INSIGHT + VALIDATION (optional)

**Tool:** Gemini 3 Preview Pro (1 API call)
**Input:** analysis.json + peak frame image (with mask applied) + scene_report.json
**Process:** Validate analysis, generate coaching text
**Output:**
```
stage6/
└── insight.json
    {
      analysis_validation: "confirmed" | "suspicious" | "rejected",
      isolation_validation: "bowler_correct" | "wrong_person" | "unclear",
      validation_notes: ["Peak timing looks correct for side-on angle"],
      coaching_lines: [
        "Your hip-to-trunk transfer (1.5x) is close to elite.",
        "The arm-to-wrist link is your weakest — delay the wrist snap.",
        "Overall chain: 2.97x amplification. Good foundation."
      ],
      social_caption: "Where does pace come from? Watch the energy flow 🔥",
      confidence: 0.85
    }
```
**Validation:**
- [ ] analysis_validation != "rejected"
- [ ] isolation_validation != "wrong_person"
- [ ] coaching_lines has 3 entries
- [ ] FAIL rejected → re-examine Stage 2 and Stage 4, possibly re-run
- [ ] FAIL wrong_person → re-run Stage 2 with different prompt point

---

## STAGE 7: RENDER (technique-specific)

**Tool:** Python (Pillow + OpenCV)
**Input:** Original clip + masks/ + poses.json + analysis.json + insight.json + plan.json
**Process:**
- Apply masks to original frames (background → technique-specific: black, dark, blurred)
- RIFE interpolation applied HERE if ultra-slo-mo needed (render-only, not analysis)
- Title card → slo-mo with overlay → pauses at transitions → verdict → end card
- Technique-specific rendering (speed_gradient, xfactor, kinogram, etc.)
**Output:**
```
stage7/
├── rendered_frames/
│   ├── frame_000000.png
│   └── ...
└── render_report.json
    {
      technique: "speed_gradient",
      total_frames: 450,
      duration_s: 15.0,
      output_fps: 30,
      rife_interpolated: false,
      sections: {title: 2.0, analysis: 6.5, verdict: 5.0, end: 1.5}
    }
```
**Validation:**
- [ ] Visual spot check: frames at 0%, 25%, 50%, 75%, 95%
- [ ] Frame at 25% — overlay on bowler only, not background
- [ ] Frame at 75% — verdict card data matches analysis.json
- [ ] No pure-black frames in analysis section
- [ ] Total duration 10-60 seconds

---

## STAGE 8: ENCODE

**Tool:** FFmpeg
**Input:** rendered_frames/
**Process:** H.264 encode, add silent audio
**Output:**
```
stage8/
└── upload_ready.mp4
```
**Validation:**
- [ ] ffprobe: codec=h264, 1080×1920, 30fps, yuv420p
- [ ] Bitrate ≥ 4 Mbps
- [ ] Duration matches render_report.json
- [ ] File size < 100 MB
- [ ] Plays in video player without errors
