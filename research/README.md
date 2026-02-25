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

---

## Open Research Questions

### Q1: Multi-delivery detection in broadcast montage
Bumrah montage (7 deliveries, rapid cuts): best result 3/7 at 0.2s threshold. Count inconsistent (5-8 detected). Scene segmentation could help but untested.

### Q2: Gemini 3 Pro vs Flash for Expert analysis
Is Pro meaningfully better than Flash for biomechanical phase analysis? Cost difference is ~4x. Needs experiment.

### Q3: Bowling type classification accuracy
Can Gemini reliably distinguish fast/medium/spin from video alone? Needed for speed estimation tier 1.

### Q4: Multi-pass detection
Coarse pass to find delivery windows, fine pass (zoomed to 1-sec window) for precise timestamp. Follows from R10 trend that focused analysis improves precision.

### Q5: Multimodal Live API for real-time detection
What are the actual capabilities and limitations of Gemini's streaming API for live bowling detection?

### Q6: Available cricket/bowling datasets, models, and tools
What existing resources can we leverage? → See `research/cricket_resources.md`

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
