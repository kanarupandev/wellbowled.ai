# Research Index

## Completed Research

### R1: Gemini Video Prompting
**Status**: VERIFIED | **Ref**: `docs/prompting_techniques.md`
- Gemini samples at ~1fps, 258 tokens/frame, ~0.5s native temporal precision
- Count-first-then-locate Scout prompt achieves 5/5 detection, 0 phantoms
- Five prompt types designed: Scout, Expert, Live, Legality, Speed

### R2: Delivery Detection Accuracy (Phase 1)
**Status**: SUPERSEDED by R9 | **Ref**: `experiments/delivery_detection/phase1_summary.md`
- Phase 1 tested on 3-sec smoke test only
- MINIMAL thinking appeared best (0.04s delta) on smoke test
- **Superseded**: Phase 2 showed MINIMAL degrades on longer/diverse videos

### R3: MediaPipe Pose Feasibility
**Status**: VERIFIED | **Ref**: `experiments/delivery_detection/003_findings.md`
- Wrist visibility drops to 0.38 during delivery arc (occlusion problem)
- Peak angular velocity delayed ~0.3s from actual release
- Unreliable alone for precise release timestamps without interpolation
- Useful for: skeleton overlay, biomechanical features, run-up detection

### R4: Gemini API Cost & Optimization
**Status**: VERIFIED | **Ref**: `experiments/delivery_detection/002_architecture_comparison.md`
- Cost is negligible: ~$1/day at 1K calls with default thinking
- Batch API (50% discount) not worth 24hr turnaround for experiments
- File API critical for videos >5MB (accuracy, not just size)

### R5: Hybrid Architecture Design
**Status**: DESIGNED | **Ref**: `experiments/delivery_detection/002_architecture_comparison.md`
- MediaPipe on-device for instant detection, Gemini for semantic confirmation
- For hackathon: Gemini-only. Post-MVP: hybrid.
- Disagreement resolution: MediaPipe primary, Gemini arbiter

### R6: Biomechanical Analysis Prompting
**Status**: TRAINING-DATA | **Ref**: `docs/prompting_techniques.md` §2B
- 6-phase analysis: run-up, loading, release, wrist, head, follow-through
- Visual landmark anchoring reduces hallucination
- Joint angle reference ranges from Worthington et al., Portus et al.

### R7: Speed Estimation
**Status**: TRAINING-DATA | **Ref**: `docs/prompting_techniques.md` §2E
- 3-tier approach: Gemini qualitative → biomechanical regression → ball tracking
- Gemini alone: +/- 15-25 kph (classification only)
- Ball tracking (YOLO/TrackNet): +/- 5-10 kph at 120fps (future work)

### R8: Legality Detection
**Status**: TRAINING-DATA | **Ref**: `docs/prompting_techniques.md` §2D
- 2D video cannot reliably measure 15° elbow extension
- Observation-only language, mandatory disclaimer
- Camera angle critical: side-on assessable, front-on unreliable

### R9: Configuration Optimization (Phase 2)
**Status**: VERIFIED | **Ref**: `experiments/delivery_detection/phase2_configs.md`
- **Winner**: Config E — temp=0.1, default thinking (no thinkingConfig), simple prompt, File API >5MB
- Tested 5 configs (A-E) across 5 videos with frugal smoke-test gating
- **6/7 deliveries PASS** across diverse clips (broadcast + nets + single/multi-delivery)

Key findings:
1. **Low temperature (0.1) essential** — temp 1.0 causes hallucinated phantom deliveries
2. **Default thinking > MINIMAL** for real videos — deeper reasoning improves timestamp accuracy
3. **File API critical** for >5MB — server-side processing gives better temporal precision
4. **Simpler prompts win** — response schema + video metadata confused the model
5. **Don't downscale** — 480p loses release-point detail, model lands on follow-through
6. **Smoke tests can overfit** — Config C won 3-sec test but failed real videos

### R10: Accuracy Trends
**Status**: VERIFIED | **Ref**: `experiments/delivery_detection/phase2_configs.md`
- When wrong, model overshoots (detects follow-through, not release) — bias toward visually dramatic moment
- Thinking depth benefit scales with video duration/complexity
- Camera angle consistency > resolution > video length for accuracy
- Adding constraints (schema, metadata, thinking limits) hurts — model performs best with simple task + free reasoning
- Broadcast montage with rapid scene cuts remains fundamentally hard (3/7 best case)

### R11: Live API Feasibility
**Status**: HYPOTHESIS — AUDIO IS THE PATH (not yet validated end-to-end) | **Ref**: `experiments/live_speed/results.md`
- gemini-3-flash-preview does NOT support Live API
- Native-audio models (`gemini-2.5-flash-native-audio`) respond via audio — ideal UX for bowlers mid-session (hands-free)
- Audio response = feature, not limitation
- **Tested**: Polling with generateContent: 2/4 deliveries detected + 1 phantom
- **Not tested**: End-to-end native-audio Live API streaming video → spoken delivery feedback
- **Next step**: Build and run native-audio experiment to validate the hypothesis

### R12: Speed Estimation
**Status**: VERIFIED | **Ref**: `experiments/live_speed/results.md`
- **Gemini 3 Pro**: 96-99 kph avg, ±3 kph cross-delivery consistency, type classification reliable
- **YOLO (COCO, 30fps)**: Cannot detect cricket ball — needs 240fps + fine-tuning
- **MediaPipe wrist velocity**: Peak 1016-1967 px/s at release, identifies bowling arm, useful proxy
- **Best for hackathon**: Gemini Pro classification on 2.5s clips ("medium pace ~95-100 kph")

### R13: MediaPipe as Delivery Trigger
**Status**: PROMISING | **Ref**: `experiments/live_speed/results.md`
- Wrist velocity spike clearly marks release point in all 4 clips
- Can replace Live API as on-device delivery trigger
- Also identifies bowling arm (right/left) and arm extension angle

### R14: Delivery Type Detection (Line, Length, Type)
**Status**: FEASIBLE (UNTESTED) | **Ref**: `docs/session_onboarding.md`
- **Length** (yorker/full/good/short/bouncer): HIGH feasibility from Gemini visual classification (~75-85%). Ball pitch location relative to batter + batter footwork response are strong visual cues.
- **Line** (off/middle/leg/wide): MEDIUM feasibility (~60-70%). Requires depth perception from 2D; camera angle behind stumps is critical.
- **Type** (seam/spin): HIGH feasibility (~80%+). Bowler's action, arm speed, wrist position are visually distinct.
- **Swing direction**: LOW feasibility (~50-65%). Subtle lateral movement hard to detect without trajectory data.
- **Key insight**: Gemini understands bowling semantically (not geometrically). It can classify "short outside off" from visual context but cannot give precise x,y pitch coordinates.
- **Zone-based pitch maps**: Accumulate categorical classifications across a spell → approximate zone map. Honest, achievable, valuable for coaching.
- **Precise pitch maps**: Need dedicated ball tracking (YOLO/TrackNet + homography calibration from stumps). FullTrack AI does this.

### R15: Competitive Landscape
**Status**: RESEARCHED | **Ref**: `docs/session_onboarding.md`
- **FullTrack AI**: Single iPhone behind stumps. Homography calibration from stump positions (known 20.12m pitch). Ball tracking via proprietary ML. Peer-reviewed: ICC >0.96 for line/length, speed overestimates by ~2.6-2.8 kph for pace. 3M+ users. $10/mo.
- **PitchVision**: 2 cameras + laptop + activation sensor. Professional coaching kit.
- **CricVision**: Cloud-based AI ball tracking, 3D trajectory. Single camera.
- **SPEEDUP Cricket**: CV-based 3D trajectory from single device. Speed + throw angle.
- **Ludimos**: IPL teams use. AI extracts line/length/speed/deviation from training video.
- **NV Play Vision AI**: Auto-coding ball position, pitch map coordinates from stationary cameras.
- **Catapult**: Wearable inertial sensors, 1000+ data points/sec. Auto-detects bowling deliveries.
- **Hawk-Eye**: 6+ cameras at 340fps. 2.6mm accuracy. Broadcast-only.
- **Our angle**: Nobody does live audio feedback. FullTrack gives you data; we give you a mate who talks.

### R16: Ball Tracking State of the Art (Single Mobile Camera)
**Status**: RESEARCHED | **Ref**: `research/cricket_resources.md`
- At 140 kph, ball crosses 20m in ~0.5s. At 30fps = ~15 frames (marginal). 60fps = ~30 frames (adequate). 240fps = ~120 frames (excellent).
- **TrackNet V3/V4**: Best accuracy for small fast objects. 97.5% tracking, IoU 0.91. NOT mobile-friendly.
- **YOLOv8**: 99.18% mAP50 with transfer learning on cricket data. ~85 FPS on iPhone via CoreML. Mobile-viable.
- **YOLO26** (Sept 2025): Purpose-built for edge/low-power. CoreML + TFLite export.
- **3D from single camera**: Homography from stumps (known 20.12m pitch geometry). FullTrack's approach.
- **Practical architecture**: YOLO on-device for real-time detection + Kalman filter for trajectory through occlusions + homography for real-world coordinates.

---

## Open Research Questions

### Q1: Multi-delivery detection in broadcast montage
Bumrah montage (7 deliveries, rapid cuts): best result 3/7 at 0.2s threshold. Count inconsistent (5-8 detected). Scene segmentation could help but untested.

### Q2: Gemini 3 Pro vs Flash for Expert analysis
Is Pro meaningfully better than Flash for biomechanical phase analysis? Cost difference is ~4x. Needs experiment.

### Q3: Bowling type classification accuracy
~~Can Gemini reliably distinguish fast/medium/spin from video alone?~~ **ANSWERED by R12**: Yes, type classification (fast/medium/spin) is reliable. Absolute speed ±10 kph.

### Q4: Multi-pass detection
Coarse pass to find delivery windows, fine pass (zoomed to 1-sec window) for precise timestamp. Follows from R10 trend that focused analysis improves precision.

### Q5: Multimodal Live API for real-time detection
~~What are the actual capabilities and limitations?~~ **REFRAMED by R11**: Audio response IS the right UX. Native-audio models are the path forward for live coaching feedback. Bowler can't look at phone — spoken feedback is ideal.

### Q6: Available cricket/bowling datasets, models, and tools
What existing resources can we leverage? → See `research/cricket_resources.md`

### Q7: YOLO fine-tuned on cricket ball + 240fps
Can iPhone 240fps + cricket-specific YOLO give ±5-10 kph accuracy? Dataset available (1068 images, Kaggle).

### Q8: MediaPipe wrist velocity → speed regression
Can we build a regression model mapping wrist pixel velocity to ball speed using Gemini estimates as labels?

### Q9: Gemini delivery type classification accuracy
Can Gemini reliably classify length (yorker/full/good/short) and line (off/middle/leg) from behind-stumps 2.5s clips? Estimated 75-85% for length, 60-70% for line. Needs experiment with labeled test clips.

### Q10: Challenge mode — spoken target + verification loop
Can the Live API audio model speak a target ("bowl a yorker on off stump"), then evaluate the next delivery against that target from the video? This is the core engagement loop. Needs end-to-end Live API experiment.

### Q11: Zone-based pitch map from accumulated Gemini classifications
Can we build a useful pitch map by accumulating Gemini's categorical line/length classifications per delivery? No pixel tracking needed — just zone buckets. Needs UI experiment.

### Q12: FullTrack-style ball tracking layer
Should we add a dedicated YOLO ball tracking layer (fine-tuned on cricket ball dataset, 1068 images) for precise pitch maps? Or is Gemini zone-based classification sufficient for our "expert mate" positioning? This is a build-vs-differentiate decision.

---

## Test Videos

| Video | Duration | FPS | Deliveries | Type |
|-------|----------|-----|------------|------|
| 3_sec_1_delivery_nets.mp4 | 3.7s | 30 | 1 (frame 30) | Smoke test, nets |
| umran_malik_150kph.mp4 | 8.7s | 60 | 1 (frame 281) | Broadcast, single |
| kapil_jones_swing.mp4 | 20.6s | 25 | 2 (frames 80, 364) + slo-mo | Broadcast + replay |
| whatsapp_nets_session.mp4 | 68.6s | 30 | 4 (frames 203, 565, 1127, 1770) | Nets session |
| bumrah_bairstow_swing.mp4 | 20.1s | 30 | 7 (frames 145-516) | Broadcast montage |

---

## Directory Cross-References

```
wellbowled.ai/
├── docs/
│   ├── prompting_techniques.md   ← R1, R6, R7, R8
│   ├── dev_process.md            ← methodology
│   └── session_onboarding.md     ← project overview
├── experiments/
│   └── delivery_detection/
│       ├── phase1_summary.md     ← R2 (Phase 1, superseded)
│       ├── phase2_configs.md     ← R9, R10 (Phase 2, current)
│       ├── configs.py            ← config definitions (A-E)
│       ├── detect.py             ← experiment runner
│       ├── 003_findings.md       ← R3 ground truth comparison
│       ├── 002_architecture_comparison.md ← R4, R5
│       └── result_*.json         ← raw experiment results
└── research/
    ├── README.md                 ← this file
    └── cricket_resources.md      ← Q6 (available tools/data)
```
