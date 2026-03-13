# Live Results Flow Spec + TDD Plan (Gemini Live Demo)

**Date**: 2026-03-02  
**Repo**: `/Users/kanarupan/workspace/wellbowled.ai`  
**Reference source (read-only only)**: `/Users/kanarupan/workspace/obsolete-wellbowled-alpha`

> Update note (2026-03-03): For the current on-demand deep-analysis architecture and latency-first async plan, use
> `/Users/kanarupan/workspace/wellbowled.ai/docs/live_delivery_deep_analysis_requirements.md`
> as canonical source-of-truth. This document remains historical context for the earlier results-flow slice.
>
> Update note (2026-03-05): Post-session entry behavior now uses a replay-first gate:
> 1) auto-open full session replay,
> 2) hold replay for `WBConfig.sessionResultsReplayHoldSeconds` (default 1s),
> 3) show clip-prep spinner only if prep is still running,
> 4) auto-transition to delivery carousel only when prep is complete and at least one delivery exists,
> 5) if zero deliveries, stay on replay with `No deliveries found` overlay.

## 1. Requirement Summary (Confirmed)

When a live session ends by any of these paths:
1. Timeout
2. User taps End button
3. User voice command (`"end the session"` and variants)

Then app must auto-navigate to session results and present:
1. Horizontal side carousel, one card/page per detected delivery (Instagram-like dots)
2. Each delivery page shows:
   - 5s clip (3s run-up + release + 2s follow-through)
   - high-level note(s)
   - Pace Score + Rough Speed Bucket (Estimated Speed only when calibrated + confidence shown)
3. User can swipe downward inside each delivery page to get deep analysis
4. Deep analysis section includes phase-wise:
   - pros
   - cons
   - injury risk comments
5. Deeper section includes MediaPipe node+stick overlay on bowler
6. Overlay legend must be fine print:
   - red = injury risk
   - green = good
   - yellow = attention
7. Color coding must be driven by Gemini feedback labels (not hardcoded phase defaults)
8. Annotated pose video must support chip controls:
   - show top 3 high-impact phase chips (ex: Run-up, Release, Follow-through)
   - tap chip to focus that phase segment in video
   - provide chips for Pause and Slow-mo
   - slow-mo can target selected phase
9. Chips must feel suggestion-driven:
   - default chip set appears automatically when deep analysis is ready
   - ranking for top 3 chips uses phase severity/importance from Gemini feedback

## 2. Engagement Requirement While Deep Analysis Is Running

Deep analysis may take ~20s to 60s. UX must keep user engaged:
1. Show spinner/progress state while deep analysis is not ready
2. Show rotating telemetry/news-bullet style status lines
3. Use ~10-20 distinct lines
4. Advance line every ~2 seconds
5. Coverage target: up to ~40 seconds of rotating updates
6. If still not ready after 40s, continue with generic analyzing status

Example telemetry lines (working set, update-safe):
1. Evaluating kinetic chain energy transfer
2. Measuring run-up rhythm consistency
3. Tracking front-foot plant stability
4. Checking hip-shoulder separation timing
5. Scanning bowling arm path smoothness
6. Estimating release window precision
7. Validating wrist snap and seam alignment
8. Measuring follow-through deceleration control
9. Mapping load distribution across joints
10. Cross-checking phase transitions
11. Comparing delivery pattern against previous ball
12. Scoring balance through release
13. Reviewing trunk rotation sequence
14. Verifying landing mechanics
15. Detecting high-stress joint moments
16. Building phase-level coaching summary
17. Synthesizing injury-risk indicators
18. Finalizing action recommendations

## 3. UI/Navigation Intent (Borrowed Pattern, Not Theme)

From obsolete reference, preserve only structure:
1. Horizontal `TabView` carousel for delivery-level navigation
2. Vertical scroll/paging inside a selected delivery for deeper detail
3. Immediate high-level view first, deep details below
4. Strong in-card status messaging when overlay/deep analysis is pending

Color theme and styling from obsolete repo are explicitly ignored.

## 4. Coding Intent (Current Repo)

Target files in source-of-truth:
1. `/Users/kanarupan/workspace/wellbowled.ai/ios/wellBowled/LiveSessionView.swift`
2. `/Users/kanarupan/workspace/wellbowled.ai/ios/wellBowled/SessionViewModel.swift`
3. `/Users/kanarupan/workspace/wellbowled.ai/ios/wellBowled/Models.swift`
4. `/Users/kanarupan/workspace/wellbowled.ai/ios/wellBowled/Tests/SessionViewModelPromptTests.swift`
5. `/Users/kanarupan/workspace/wellbowled.ai/ios/wellBowled/Tests/...` (new targeted tests)

Implementation intent:
1. Ensure all end paths reliably surface results view without extra taps
2. Move results to horizontal delivery carousel with page indicators
3. Add per-delivery vertical deep analysis section
4. Load Gemini-labeled landmarks, derive phase feedback and color map
5. Display fine-print legend and deep-analysis readiness status
6. Add rotating telemetry ticker during deep analysis pending state
7. Add phase control chips over annotated view:
   - top 3 focus chips (phase-driven)
   - Pause chip
   - Slow-mo chip
8. Wire chip actions to playback controller:
   - focus -> seek to phase timestamp and hold loop window
   - pause -> stop playback at current frame
   - slow-mo -> set reduced playback rate for selected phase
9. Reuse existing control patterns already present in chat/video path where possible (`QuickChip`, `VideoAction`)

## 5. TDD Plan (Strict)

### Red phase tests first
1. `SessionViewModel` end-command parser:
   - accepts `"end session"`, `"end the session"`, `"stop session"`, `"finish session"`
   - rejects unrelated phrases
2. Result auto-navigation logic:
   - opens results after timeout/end when deliveries exist
   - opens after async analysis transitions `isAnalyzing: true -> false`
3. Gemini feedback mapping:
   - `LandmarksData` feedback labels map to `good/slow/injury_risk`
   - phase windows (start/end) are constructed deterministically
4. Telemetry ticker:
   - advances every 2s
   - rotates through configured lines
   - after 40s transitions to generic fallback status
5. Chip recommendation logic:
   - returns exactly 3 phase chips when >=3 phases exist
   - prioritizes phases with higher risk/attention signals
   - falls back safely when phases are sparse
6. Chip action execution:
   - Focus chip seeks to expected timestamp range
   - Pause chip sets playback state to paused
   - Slow-mo chip applies target reduced rate (and restores when cleared)

### Green phase
1. Implement minimal code to pass each failing test
2. Keep behavior deterministic; isolate timer logic behind small testable unit
3. Keep overlay color mapping single-source from Gemini feedback labels

### Refactor phase
1. Remove duplication in phase card rendering
2. Consolidate status strings in one config/static list
3. Keep all flows working across free mode and challenge mode

## 6. Verification Plan

Unit verification:
1. Run targeted unit tests for parser, mapping, ticker
2. Run existing session/config tests to catch regressions

Manual verification on device:
1. End by button -> auto results
2. End by timeout -> auto results
3. End by voice `"end the session"` -> auto results
4. Swipe sideways across deliveries with bottom dots
5. Swipe down on any delivery for phase-wise pro/con/risk
6. Confirm overlay legend fine print
7. Confirm overlay colors change from Gemini labels
8. Confirm telemetry ticker cadence and fallback after 40s
9. Confirm top-3 phase chips appear when deep analysis is ready
10. Tap focus chip -> playback seeks/loops on selected phase
11. Tap pause chip -> playback halts immediately
12. Tap slow-mo chip -> selected phase plays in slow motion

## 7. Out of Scope for This Slice

1. Color/theme redesign
2. Non-live upload pipeline changes
3. Reworking BowlingDNA feature set
4. Backend protocol changes

## 8. Read-Only Reference Files Consulted

1. `/Users/kanarupan/workspace/obsolete-wellbowled-alpha/ios/wellBowled/UploadAnalysisHub.swift`
2. `/Users/kanarupan/workspace/obsolete-wellbowled-alpha/ios/wellBowled/UIComponents.swift`
3. `/Users/kanarupan/workspace/obsolete-wellbowled-alpha/ios/wellBowled/AnalysisResultView.swift`
4. `/Users/kanarupan/workspace/obsolete-wellbowled-alpha/ios/wellBowled/CoachChatPage+Video.swift`
5. `/Users/kanarupan/workspace/obsolete-wellbowled-alpha/ios/wellBowled/AnalysisComponents.swift`
