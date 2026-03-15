# Live Delivery Deep Analysis Requirements + Feasibility Plan

**Date**: 2026-03-03  
**Repo**: `/Users/kanarupan/workspace/wellbowled.ai`  
**Status**: Source-of-truth for this feature slice (document-first, before implementation)

---

## 1. Canonical Requirements (User-Specified)

This section records the exact required behavior for implementation.

1. End session flow must be:
`end session -> deliveries page`.
2. Deliveries page must be horizontal swipe (one page per delivery).
3. Each delivery card must show a 5-second clip and a release-point thumbnail.
4. Deep analysis must be **on-demand** per delivery (not auto-run for all deliveries).
5. While deep analysis runs:
- show spinner
- show cool "news-bullet" style progress updates
- around 15-20 unique updates
- each update max 2 seconds
- once list is exhausted and analysis still running, hold on `"Analyzing..."` until completion.
6. After deep analysis completes, UI must clearly indicate downward swipe availability.
7. First downward section: well-structured phase-wise textual analysis (`good / bad / ugly` style including injury risk).
8. In parallel with detailed analysis completion, run:
- DNA matching vector profile
- MediaPipe pose extraction/annotation pipeline.
9. DNA output:
- top 1-3 international bowler matches (current DB of 103 bowlers)
- compelling presentation of action signature / mixture.
10. Next downward section: MediaPipe pose annotated, color-coded overlay video.
11. Below overlay section: chat entry area with suggestion chips.
12. Chat input is non-typing for now; chip selection drives requests.
13. Chip selection must send:
- selected chip
- detailed analysis response
- system prompt instructions
to Gemini fast model and return response that controls video focus for relevant phase.
14. Must optimize for low latency, strong UX, and safe async behavior (no race-condition regressions).

---

## 2. Feasibility Check

## 2.1 Overall

**Feasible** within this codebase with incremental refactor.

Key reason: current project already has foundations for each required layer:
1. clip extraction + delivery sequencing
2. Gemini calls for delivery analysis and DNA extraction
3. MediaPipe-based pose primitives and overlay renderer
4. phase chip playback controls in results UI.

## 2.2 Feasible Immediately

1. End -> deliveries page immediate navigation.
2. Horizontal delivery carousel with dots.
3. Release thumbnail extraction from clips.
4. On-demand deep analysis button + async spinner/telemetry.
5. 20-step telemetry loop with 2s cadence then sticky `"Analyzing..."`.
6. Downward sectioning and swipe affordance indicator.
7. Async parallel execution using task groups for:
- deep analysis
- DNA extraction/match
- pose extraction.

## 2.3 Feasible with Medium Complexity

1. Reliable per-delivery on-device pose extraction from recorded clip using MediaPipe video mode.
2. Chip-driven Gemini response that returns deterministic playback directives (`focus window`, `pause`, `slow-mo`).

## 2.4 Critical Challenge (Intentional Pushback)

Absolute deterministic pose behavior across devices is not fully realistic for ML+camera+decode pipelines.

What is realistic and enforceable:
1. **Operational determinism**: fixed model asset, fixed frame sampling, fixed thresholds, fixed ordering, fixed rounding, fixed tie-breaks.
2. **UI determinism**: identical state transitions and fallback behavior for same pipeline outcomes.

This is the right bar to target for hackathon-grade reliability.

---

## 3. Current Code Static Analysis (Gaps vs Requirements)

## 3.1 Flow + Navigation

1. Live view auto-start already exists.
2. Results navigation is currently coupled to `isAnalyzing == false`, which delays entering results when post-session analysis is long.
3. Current post-session path performs broad analysis eagerly rather than delivery-on-demand deep analysis.

Impact:
1. higher perceived latency
2. violates requested `end -> deliveries page` immediacy.

## 3.2 Deep Analysis Trigger Model

1. Current UI shows pending deep-analysis text when phases are absent.
2. There is no explicit per-delivery "Run Deep Analysis" trigger in this live results path.

Impact:
1. user has unclear control
2. on-demand contract not met.

## 3.3 DNA Presentation

1. DNA extraction/matching already implemented.
2. Current results page shows only a lightweight session-level summary card.
3. No dedicated per-delivery compelling DNA section in downward flow.

## 3.4 Pose Overlay Availability

1. Overlay renderer exists.
2. Current live results path depends on `landmarksURL`; this is often absent.
3. No guaranteed local per-delivery pose extraction fallback in this flow.

Impact:
1. overlay section can remain unavailable.

## 3.5 Async/Race Risk Points

1. Shared mutable state transitions spread across view state + view model state.
2. Potential stale gating by global `isAnalyzing` rather than per-delivery analysis states.
3. Parallel task cancellation and result write-back order must be explicit.
4. Background callback mutation to shared session fields needs strict actor/main-thread discipline.

---

## 4. Latency + UX Strategy

## 4.1 User-Perceived Latency Targets

1. `End session -> deliveries page visible`: `< 1.5s` target.
2. Thumbnail availability per delivery: `< 500ms` after clip ready (best effort).
3. On-demand deep analysis start feedback: `< 100ms` after button tap (spinner + first bulletin).
4. Control chip interaction response target: `< 1.5s` median on good network.

## 4.2 Pipeline Split (Low-Latency First)

On session end:
1. run local clip extraction + thumbnail generation only
2. navigate immediately to deliveries carousel.

On deep-analysis tap for one delivery:
1. start deep-analysis task group
2. run parallel:
- Gemini detailed analysis
- DNA extraction + matching
- MediaPipe pose extraction
3. stream telemetry bullets every 2s
4. transition to downward-ready state once minimum deep textual result is available
5. continue filling auxiliary sections as they complete.

---

## 5. Model + Prompt Feasibility (Web-Backed)

## 5.1 Model Selection Strategy

Inference from docs:
1. keep Live voice on Live-native audio model for session conversation.
2. use a stable multimodal Flash family model for per-delivery deep analysis / chip control where low latency matters.
3. avoid over-reliance on preview-only model names for critical demo paths unless explicitly validated each day.

Rationale:
1. official model docs position Flash variants for low-latency/high-volume usage.
2. structured outputs are available and reduce parser failures.

## 5.2 Prompting Strategy

1. Use strict JSON schema responses (`response_mime_type: application/json`, schema enforced).
2. Keep system prompts short, explicit, and constraint-first.
3. Use component prompts:
- deep analysis prompt
- DNA extraction prompt
- chip control prompt.
4. Include deterministic output contract:
- fixed enums
- fixed numeric ranges
- explicit fallback fields.

## 5.3 Video Input Strategy

1. Specify explicit frame sampling (`videoMetadata.fps`) for motion-critical analysis.
2. Tune `media_resolution` for latency-quality tradeoff.
3. For general motion understanding, start low/medium and elevate only where detail loss is measured.

---

## 6. MediaPipe Determinism Plan

1. Single model asset version pinned in app bundle.
2. Fixed running mode + fixed timestamp progression.
3. Fixed frame sampling rate for offline clip processing.
4. Stable sort and consistent phase boundary derivation.
5. Phase/joint labels normalized (`lowercase`, canonical aliases).
6. Deterministic color mapping:
- red = injury risk
- yellow = attention
- green = good.

---

## 7. Async Design (No-Race Implementation Intent)

## 7.1 Per-Delivery State Machine

For each delivery:
1. `idle`
2. `analyzing` (on-demand)
3. `text_ready`
4. `pose_ready`
5. `dna_ready`
6. `complete`
7. `failed` (with recoverable retry).

## 7.2 Structured Concurrency Rules

1. Use `withThrowingTaskGroup`/`withTaskGroup` for child tasks.
2. Use cooperative cancellation (`cancelAll`) when user leaves delivery or restarts analysis.
3. All UI mutations on main actor only.
4. Task results write through a single reducer function keyed by delivery ID.

## 7.3 Telemetry Loop Rules

1. 2-second cadence.
2. 20 unique updates max.
3. after 40 seconds (20 x 2s), show sticky `"Analyzing..."`.
4. stop loop immediately on completion/failure/cancel.

---

## 8. UX Spec (Planned Page Sequence)

1. **Page A (horizontal)**: delivery clip + release thumbnail + summary badges.
2. **Action**: `Deep Analysis` button.
3. **Loading phase**: spinner + telemetry bullets.
4. **When text ready**: show explicit swipe affordance (`Swipe down for phase insights` + chevron animation).
5. **Downward section 1**: phase-wise `good / bad / ugly` blocks.
6. **Downward section 2**: DNA action-signature card stack (top 1-3 matches).
7. **Downward section 3**: pose-annotated video + legend.
8. **Downward section 4**: chat chips panel; chip tap triggers Gemini fast control response and playback focus.

---

## 9. Dedicated 20-Step Telemetry Bulletin Set

Display one message every 2 seconds while deep analysis is running.

1. Detecting run-up phase boundaries
2. Measuring approach rhythm consistency
3. Validating gather alignment
4. Tracking back-foot contact stability
5. Estimating trunk load transfer
6. Segmenting delivery stride window
7. Measuring front-arm pull timing
8. Checking head stability through release
9. Calculating release kinematics
10. Reviewing wrist alignment at release
11. Estimating seam-axis consistency
12. Scanning follow-through deceleration
13. Computing kinetic chain efficiency
14. Tagging high-stress joint events
15. Building phase-wise strengths
16. Building phase-wise risk flags
17. Generating corrective cues
18. Compiling action signature vector
19. Matching international bowler profiles
20. Finalizing annotated coaching report

After item 20:
`Analyzing...` (persistent until completion).

---

## 10. Validation and Test Plan (Implementation Gate)

1. Unit tests for telemetry progression/fallback timing.
2. Unit tests for per-delivery state-machine transitions.
3. Unit tests for structured JSON parsing and fallback defaults.
4. Unit tests for deterministic chip response application (`focus window`, `slow-mo`, `pause`).
5. Integration test for on-demand deep analysis invoking parallel tasks.
6. Manual device test:
- end -> deliveries immediate
- on-demand deep analysis
- downward sections + DNA + pose + chip control.

---

## 11. Implementation Feedback Record (2026-03-03)

### Iteration A
1. Change:
- Added on-demand deep-analysis pipeline (`DeepAnalysisModels`, thumbnail generation, clip pose extraction, per-delivery deep-analysis state, results-page UI wiring).
2. Check:
- `xcodebuild -workspace wellBowled.xcworkspace -scheme wellBowled -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:wellBowledTests/WBConfigTests -only-testing:wellBowledTests/SessionResultsPlannerTests test`
3. Result:
- Failed compile: `DeliveryDeepAnalysisResult` incorrectly required `Equatable` while containing non-Equatable `ExpertAnalysis`.
4. Next action:
- Remove `Equatable` conformance from `DeliveryDeepAnalysisResult`.

### Iteration B
1. Change:
- Fixed `DeliveryDeepAnalysisResult` conformance.
2. Check:
- Same targeted test command as Iteration A.
3. Result:
- Failed compile: `SessionViewModel.runDeepAnalysisIfNeeded` inferred `Task<()?, Never>` from weak-self optional chain.
4. Next action:
- Force `Task<Void, Never>` with explicit `guard let self`.

### Iteration C
1. Change:
- Fixed task type in `SessionViewModel.runDeepAnalysisIfNeeded`.
2. Check:
- `xcodebuild ... -only-testing:wellBowledTests/WBConfigTests -only-testing:wellBowledTests/SessionResultsPlannerTests test`
- `xcodebuild ... -only-testing:wellBowledTests/SessionViewModelPromptTests -only-testing:wellBowledTests/GeminiFeedbackMappingTests test`
3. Result:
- Both targeted test runs succeeded.
4. Next action:
- Build and deploy to physical device.

### Iteration D
1. Change:
- Synced source-of-truth to Xcode copy and built device debug binary.
2. Check:
- `xcodebuild -workspace wellBowled.xcworkspace -scheme wellBowled -destination 'generic/platform=iOS' -configuration Debug clean build`
- `xcrun devicectl device install app --device E40F593B-ABB6-514A-873F-48CD7C4F98F3 <APP_PATH>`
- `xcrun devicectl device process launch --device E40F593B-ABB6-514A-873F-48CD7C4F98F3 kanarupan.wellBowled`
3. Result:
- Build succeeded.
- Install succeeded.
- Launch failed due locked-device state (`Unable to launch ... device was not, or could not be, unlocked`).
4. Next action:
- Unlock iPhone and relaunch command (no rebuild required).

### Iteration E (2026-03-04)
1. Change:
- Tuned camera capture for native iPhone capability selection (`target 60fps`, `max 60fps`, preferred `1280x720+`, fallback `30fps`) and added capture config constants in `WBConfig`.
- Added `WBConfig` unit assertions for camera config sanity.
2. Check:
- `xcodebuild -workspace wellBowled.xcworkspace -scheme wellBowled -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:wellBowledTests/WBConfigTests test`
- `xcodebuild -workspace wellBowled.xcworkspace -scheme wellBowled -configuration Debug -destination 'generic/platform=iOS' build`
- `xcrun devicectl device install app --device 00008120-001230560204A01E <APP_PATH>`
- `xcrun devicectl device process launch --device 00008120-001230560204A01E kanarupan.wellBowled`
3. Result:
- Targeted tests passed.
- Device build succeeded.
- Install succeeded (`databaseSequenceNumber: 4164`).
- Launch command failed only when phone was locked (`FBSOpenApplicationErrorDomain error 7, Locked`).
4. Next action:
- Re-run launch while the device screen remains unlocked and verify on-device camera FPS behavior in live session.

## 12. References (Primary Sources)

1. Gemini models doc: [https://ai.google.dev/gemini-api/docs/models/gemini-v2](https://ai.google.dev/gemini-api/docs/models/gemini-v2)
2. Gemini model overview: [https://ai.google.dev/models/gemini](https://ai.google.dev/models/gemini)
3. Gemini structured outputs: [https://ai.google.dev/gemini-api/docs/structured-output](https://ai.google.dev/gemini-api/docs/structured-output)
4. Gemini prompt/system instruction guidance: [https://ai.google.dev/gemini-api/docs/system-instructions](https://ai.google.dev/gemini-api/docs/system-instructions)
5. Gemini prompt best practices: [https://ai.google.dev/guide/prompt_best_practices](https://ai.google.dev/guide/prompt_best_practices)
6. Gemini video understanding (fps sampling): [https://ai.google.dev/gemini-api/docs/video-understanding](https://ai.google.dev/gemini-api/docs/video-understanding)
7. Gemini media resolution: [https://ai.google.dev/gemini-api/docs/media-resolution](https://ai.google.dev/gemini-api/docs/media-resolution)
8. Gemini Live tools/function-calling: [https://ai.google.dev/gemini-api/docs/live-tools](https://ai.google.dev/gemini-api/docs/live-tools)
9. Gemini Live session management/resumption: [https://ai.google.dev/gemini-api/docs/live-session](https://ai.google.dev/gemini-api/docs/live-session)
10. Gemini Live API reference: [https://ai.google.dev/api/live](https://ai.google.dev/api/live)
11. MediaPipe Pose Landmarker iOS: [https://ai.google.dev/edge/mediapipe/solutions/vision/pose_landmarker/ios](https://ai.google.dev/edge/mediapipe/solutions/vision/pose_landmarker/ios)
12. Swift TaskGroup docs (structured concurrency): [https://developer.apple.com/documentation/swift/taskgroup](https://developer.apple.com/documentation/swift/taskgroup)
