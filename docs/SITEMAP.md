# Project Site Map

## Active Source Of Truth

All active development is in:
`/Users/kanarupan/workspace/wellbowled.ai`

## iOS App Source

Path:
`/Users/kanarupan/workspace/wellbowled.ai/ios/wellBowled/`

Core files:
- `SessionViewModel.swift` — live session pipeline orchestration
- `GeminiLiveService.swift` — Gemini Live WebSocket transport
- `GeminiAnalysisService.swift` — post-session Gemini analysis
- `HomeView.swift` — session entry + settings
- `LiveSessionView.swift` — live camera/session UI + results
- `Session.swift` / `Enums.swift` / `Delivery.swift` / `Models.swift` — domain model
- `WBConfig.swift` — runtime config + feature flags + challenge targets
- `ChallengeEngine.swift` — challenge target rotation + result formatting
- `DeliveryDetector.swift` / `WristVelocityTracker.swift` — on-device delivery detection
- `DeliveryPoseSelector.swift` — stable multi-pose bowler selection + lock scoring

## iOS Tests Source

Path:
`/Users/kanarupan/workspace/wellbowled.ai/ios/wellBowled/Tests/`

Current test coverage:
- session lifecycle and scoring (`SessionTests.swift`, `SessionLifecycleIntegrationTests.swift`)
- config/personas (`WBConfigTests.swift`)
- wrist spike detection (`WristVelocityTrackerTests.swift`)
- pose selector lock/fallback determinism (`DeliveryPoseSelectorTests.swift`)
- enums/codable behavior (`EnumsTests.swift`)
- BowlingDNA encoding/matching (`BowlingDNATests.swift`)

## Build Copy (Disposable)

Path:
`/Users/kanarupan/workspace/xcodeProj/wellBowled/`

Rule:
- use for build/test/install only
- do not treat as source of truth
- always sync from `wellbowled.ai/ios/wellBowled/`

## Obsolete Repo

Path:
`/Users/kanarupan/workspace/dont_use_obsolete_wellBowled/`

Rule:
- do not develop here

## Canonical Docs

Path:
`/Users/kanarupan/workspace/wellbowled.ai/docs/`

Primary documents:
- `dev_process.md` — mandatory engineering loop
- `project_dev_deploy_guide.md` — project-specific dev/deploy flow
- `codex_guide.md` — handover + execution runbook
- `architecture_decision.md` — architecture decisions and status
- `session_onboarding.md` — product framing
- `live_results_flow_tdd_plan.md` — live results carousel + deep-analysis UX spec and TDD plan
- `live_delivery_deep_analysis_requirements.md` — dedicated source-of-truth for per-delivery deep analysis flow, async parallelism, latency targets, race-risk checks, and UI behavior
- `live_session_and_deep_analysis_diagrams.md` — Mermaid diagrams for live demo flow, async deep-analysis pipeline, state machine, and navigation model
- `delivery_detection_feedback_log.md` — iteration log with change/check/result evidence for delivery detector reliability updates
- `delivery_detection_hybrid_strategy.md` — canonical hybrid detection policy (MediaPipe live + Gemini Flash batch + timestamp merge rules)
- `pace_score_metric_model.md` — canonical pace metric model (Pace Score, rough speed bucket, calibrated estimated speed, trend, copy guardrails)
- `live_buddy_value_contract.md` — canonical value contract for live conversational buddy (event-grounded coaching guardrails and success metrics)

Read-only UX reference (flow only, no theme copy):
- `/Users/kanarupan/workspace/obsolete-wellbowled-alpha/`

## Content Pipelines (Video Analysis)

Path:
`/Users/kanarupan/workspace/wellbowled.ai/content/`

Each pipeline takes a 3-10s bowling clip → upload-ready 9:16 Instagram Reel (1080×1920, H.264, 30fps).

| # | Pipeline | Path | Status | Output |
|---|----------|------|--------|--------|
| 1 | **X-Factor** | `content/xfactor_pipeline/` | v0.0.1 Done | Hip-shoulder separation overlay, peak freeze, verdict card |
| 2 | **Kinogram** | `content/kinogram_pipeline/` | v0.0.1 POC — 7 fixes pending | 7-phase stroboscopic composite with color-coded skeletons |
| 3 | **Goniogram** | `content/goniogram_pipeline/` | v0.0.1 Done | Elbow extension + knee brace arcs, centroid-tracked bowler |
| 4 | **Velocity Waterfall** | `content/waterfall_pipeline/` | Planned | Stacked segment speed curves animated with slo-mo (kinetic chain whip) |
| 5 | **Phase Portrait** | `content/portrait_pipeline/` | Planned | Angle-vs-angle signature loop — elite=tight, amateur=chaos |
| 6 | **Spine Stress Gauge** | `content/spine_gauge_pipeline/` | Planned | Lumbar flexion+rotation risk arc — pulsing red in danger zone |

Shared dependencies: MediaPipe PoseLandmarker (heavy model), OpenCV, Pillow, FFmpeg, google-generativeai.
Shared venv: symlinked from `xfactor_pipeline/.venv`.
Input sample: `resources/samples/3_sec_1_delivery_nets.mp4`.

## Archived Areas

Paths:
- `/Users/kanarupan/workspace/wellbowled.ai/experiments/`
- `/Users/kanarupan/workspace/wellbowled.ai/research/`
- `/Users/kanarupan/workspace/wellbowled.ai/codex/`

Rule:
- historical context only
- do not use as active source of truth unless explicitly reactivated
