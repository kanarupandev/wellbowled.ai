# Content Pipeline — Automated Analysis Video Production

## Vision

Produce 2 Instagram-ready analysis-rich video clips within 2 hours, with no more than 10 minutes of direct manual supervision.

## Pipeline Philosophy

1. Classical CV + MediaPipe + cricket domain knowledge does the heavy lifting
2. Gemini vision model calls replace manual interventions — reliably
3. Human stays in the loop for final approval only
4. Every manual step is a candidate for automation in the next iteration

## Pipeline Stages

```
Raw footage (net session recording)
    │
    ▼
┌─────────────────────────────────┐
│ 1. AUTO-DETECT DELIVERIES       │  MediaPipe wrist velocity spikes
│    Classical CV, no AI needed   │  + batch segment scanning
└─────────────┬───────────────────┘
              │ N delivery timestamps
              ▼
┌─────────────────────────────────┐
│ 2. EXTRACT CLIPS                │  5s windows (3s pre-roll + 2s post)
│    AVAssetExportSession         │  per delivery
└─────────────┬───────────────────┘
              │ N × 5s MP4 clips
              ▼
┌─────────────────────────────────┐
│ 3. RUN FULL ANALYSIS            │  Per clip, in parallel:
│    a. MediaPipe pose extraction │  → skeleton frames
│    b. Gemini deep analysis      │  → 5 phases, DNA, drills
│    c. Speed estimation          │  → kph (if calibrated)
│    d. DNA matching              │  → famous bowler match
└─────────────┬───────────────────┘
              │ N × analysis bundles
              ▼
┌─────────────────────────────────┐
│ 4. RANK & SELECT (Gemini)       │  Score each delivery:
│    - injury risk count          │  - phase contrast (good vs bad)
│    - DNA match % strength       │  - speed impressiveness
│    - visual drama               │  - skeleton overlay quality
│    Pick top 2                   │
└─────────────┬───────────────────┘
              │ 2 best deliveries
              ▼
┌─────────────────────────────────┐
│ 5. COMPOSITE VIDEO              │  Burn into MP4:
│    - Skeleton overlay (colored) │  - Phase labels + status
│    - Speed badge                │  - DNA match card
│    - Legend (injury/good/attn)  │  - Brand watermark
│    Output: 9:16 social-ready    │
└─────────────┬───────────────────┘
              │ 2 × draft MP4s
              ▼
┌─────────────────────────────────┐
│ 6. HUMAN APPROVAL (≤10 min)     │  Review 2 clips:
│    - Approve / reject / re-run  │  - Optional: trim, reorder
│    - Add caption (or auto-gen)  │  - Publish
└─────────────────────────────────┘
```

## What Exists Today (on-device, iOS)

| Component | Status | File |
|-----------|--------|------|
| Delivery detection (wrist velocity) | Working | DeliveryDetector.swift |
| Clip extraction (5s windows) | Working | ClipExtractor.swift |
| MediaPipe pose extraction | Working | ClipPoseExtractor.swift |
| Skeleton overlay rendering | Working | SkeletonSyncController.swift |
| Gemini deep analysis (5 phases) | Working | GeminiAnalysisService.swift |
| DNA matching (20-dim vector) | Working | BowlingDNAMatcher.swift |
| Speed estimation (frame diff) | Working | SpeedEstimationService.swift |
| Batch segment planning | Working | DeliveryBatchPlanner.swift |
| Expert analysis → color map | Working | ExpertAnalysisBuilder.swift |

## Server-Side Pipelines (Built)

Three standalone Python pipelines now exist in `content/`:

| Pipeline | What It Does | Key Tech | Status |
|----------|-------------|----------|--------|
| **X-Factor** (`xfactor_pipeline/`) | Hip-shoulder separation angle overlay + peak freeze + verdict card | MediaPipe pose → angle math → OpenCV overlay → FFmpeg encode | v0.0.1 — needs background person exclusion, overlay polish, checklist pass |
| **Kinogram** (`kinogram_pipeline/`) | 7-phase stroboscopic composite with color-coded skeletons | MediaPipe pose+segmentation → multi-figure composite → animated reveal | v0.0.1 POC — 7 mandatory fixes in `IMPROVEMENTS.md` |
| **Goniogram** (`goniogram_pipeline/`) | Elbow extension + front knee brace arcs with color-coded verdicts | MediaPipe pose → joint angle math → arc overlay → centroid tracking | v0.0.1 — needs testing, checklist pass |
| **Velocity Waterfall** (`waterfall_pipeline/`) | Stacked segment speed curves animated with slo-mo (kinetic chain whip) | MediaPipe pose → velocity compute → graph render → FFmpeg | v0.0.1 — code complete, untested |
| **Phase Portrait** (`portrait_pipeline/`) | Angle-vs-angle signature loop — elite=tight, amateur=chaos | MediaPipe pose → angle compute → parametric plot → FFmpeg | v0.0.1 — code complete, untested |
| **Spine Stress Gauge** (`spine_gauge_pipeline/`) | Lumbar flexion+rotation risk arc — pulsing red in danger zone | MediaPipe pose → stress compute → gauge render → FFmpeg | v0.0.1 — code complete, unverified |

Each pipeline: input clip → 9:16 reel (1080×1920, H.264, 30fps) with FFmpeg-based QA review.

## What Still Needs Building

| Component | Approach | Effort |
|-----------|----------|--------|
| **Kinogram 7 fixes** | Bystander removal, horizontal separation, tint reduction, background brightness, phase accuracy, Playwright QA, animation pacing | Medium |
| **Content ranker** | Score deliveries by analysis richness, pick top 2. Start with heuristic, graduate to Gemini ranking prompt | Small |
| **Approval UI** | Minimal screen: 2 video previews, approve/reject buttons, optional caption field | Small |
| **Caption generator** | Gemini prompt: given analysis JSON, write a 1-2 line Instagram caption | Small |
| **All 6 pipelines → v1.0.0** | Every pipeline needs: background person exclusion, delivery-window overlay gating, 75-point checklist pass, Gemini Flash bowler ROI, visual polish | Medium–Large |
| **Additional video types** | Wrist trail/gradient, release point mapping, stride length, arm speed curve — see competitive gap analysis | Medium–Large |

## Automation Progression

### Phase 1 — Today (manual assist)
- Record session on device
- App detects deliveries, runs analysis, shows results
- Manually screen-record the skeleton overlay playback
- Manually add text in a video editor
- **~45 min manual work per clip**

### Phase 2 — Compositor MVP
- App exports analysis-overlaid MP4 directly
- Human selects which 2 to publish
- **~15 min manual work per clip**

### Phase 3 — Full Auto Pipeline
- Batch process entire session recording
- Auto-rank, auto-composite, auto-caption
- Human reviews 2 candidates, taps approve
- **≤10 min total manual time for 2 clips**

### Phase 4 — Zero-Touch (stretch)
- Scheduled publishing (approve now, post at peak time)
- A/B test hooks/captions via Gemini
- Auto-adapt style based on engagement metrics
- **~2 min manual time (just approval tap)**

## Content Style

Per Codex research findings:
- Lead with bowling insight, not app demo
- Proof-heavy: skeleton overlay IS the proof
- Hook in first 1-2 seconds (speed badge or dramatic phase)
- 9:16 portrait, 30-60 seconds
- Instagram Reels primary, YouTube Shorts secondary
- Multilingual captions (English + Tamil/Hindi) for reach

## Guiding Principles

1. **Classical first, AI second** — MediaPipe and frame differencing are deterministic and fast. Use Gemini only where judgment is needed.
2. **Every manual step is tech debt** — if a human does it twice, automate it.
3. **Ship ugly, iterate fast** — Phase 1 can be screen recordings with manual text. That's fine. The pipeline improves with each video published.
4. **10-minute rule** — if total human time exceeds 10 minutes for 2 clips, something is wrong. Fix the pipeline, not the workflow.
