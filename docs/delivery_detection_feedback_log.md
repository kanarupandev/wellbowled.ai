# Delivery Detection Feedback Log

Date: 2026-03-05
Scope: Live delivery detection reliability hardening (multi-person + lock stability)

## Iteration 1
- Change:
  - Added `DeliveryPoseSelector` (pure selection logic for multi-pose candidate filtering and subject lock scoring).
  - Updated `DeliveryDetector` to:
    - request up to `WBConfig.deliveryPoseMaxPoses` from MediaPipe
    - select a stable candidate using lock center and drift penalties
    - reset lock after consecutive misses
    - apply overarm release posture gate before emitting delivery event
    - emit debug logs for candidate/lock and confirmed delivery events
  - Added detection configuration knobs in `WBConfig`:
    - `deliveryPoseMaxPoses`
    - `deliveryPoseMinShoulderSpan`
    - `deliveryPoseLockMaxCenterDrift`
    - `deliveryPoseLockSmoothing`
    - `deliveryPoseLockResetMissFrames`
    - `deliveryPoseLockDriftPenalty`
    - `deliveryOverarmWristAboveShoulderMargin`
- Check:
  - `xcodebuild ... -only-testing:wellBowledTests/DeliveryPoseSelectorTests -only-testing:wellBowledTests/WristVelocityTrackerTests`
- Result:
  - Initial compile failed (`switch` non-exhaustive for `BowlingArm.unknown`), fixed in `DeliveryDetector`.
  - Initial test build failed due optional `CGFloat` assertions in new test file, fixed by explicit unwraps.
  - Final focused run succeeded (`** TEST SUCCEEDED **`).
- Next action:
  - Run additional determinism regression subset.

## Iteration 2
- Change:
  - No production code change. Regression verification pass.
- Check:
  - `xcodebuild ... -only-testing:wellBowledTests/CoreDeterminismTests`
- Result:
  - Passed (`** TEST SUCCEEDED **`).
- Next action:
  - Keep current thresholds as baseline and validate on real multi-person net sessions for false positives/false negatives tuning.

## Iteration 3
- Change:
  - Updated post-session UX/state flow:
    - Results now open on full-session replay first (always if recording exists).
    - Replay is held for a configurable minimum (`WBConfig.sessionResultsReplayHoldSeconds`, default `1.0s`).
    - Spinner is shown only after the hold period and only while clip prep is still running.
    - Auto-transition to horizontal delivery carousel happens only when:
      - hold period is complete
      - clip prep is complete
      - at least one delivery exists
    - If no deliveries exist after prep, replay stays visible with a clear `No deliveries found` overlay (no extra navigation).
  - Added real clip-preparation telemetry state in `SessionViewModel`:
    - `clipPreparationStatusMessage`
    - progress/status strings are tied to actual pipeline states (`finalizing`, `clipping N of total`, `ready`, `no deliveries`).
  - Ensured post-session clip prep runs whenever recording exists; no-delivery sessions now produce explicit replay status instead of dead-end empty state.
- Check:
  - `xcodebuild -workspace wellBowled.xcworkspace -scheme wellBowled -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:wellBowledTests/SessionResultsPlannerTests test`
- Result:
  - Passed (`** TEST SUCCEEDED **`), including new tests for:
    - replay-hold + carousel auto-navigation gating
    - spinner visibility rules
    - no-delivery overlay rules
- Next action:
  - Validate on-device net sessions and tune detector thresholds separately to improve true positive rate.

## Iteration 4
- Change:
  - Added failing tests first for rolling segment scheduling and timestamp merge behavior:
    - `DeliveryBatchPlannerTests`
    - Additional `WBConfig` assertions for segment/overlap/stride + merge window.
- Check:
  - `xcodebuild -workspace wellBowled.xcworkspace -scheme wellBowled -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:wellBowledTests/DeliveryBatchPlannerTests test`
- Result:
  - Expected RED state:
    - compile failed with missing symbols (`DeliveryBatchPlanner`, `DeliveryTimestampCandidate`).
  - Confirms tests are asserting behavior not yet implemented.
- Next action:
  - Implement planner + merge primitives and wire hybrid detection flow.

## Iteration 5
- Change:
  - Implemented hybrid post-session detection pipeline:
    - Added `DeliveryBatchPlanner.swift`:
      - rolling segment scheduler (`duration`, `overlap`, derived stride)
      - timestamp merge/dedupe (`mergeWindow`, confidence/source policy)
    - Extended `WBConfig.swift` with configurable detection knobs:
      - `deliveryDetectionSegmentDurationSeconds`
      - `deliveryDetectionSegmentOverlapSeconds`
      - `deliveryDetectionSegmentStrideSeconds`
      - `deliveryDetectionMergeWindowSeconds`
      - `deliveryDetectionModel`
    - Extended `GeminiAnalysisService.swift`:
      - `detectDeliveryTimestampsInSegment(segmentURL:segmentDuration:)`
      - robust JSON extraction/parsing for delivery timestamp arrays
    - Reworked `SessionViewModel.prepareDeliveryClips(...)`:
      - real telemetry stages:
        - segment detection
        - merge live + batch detections
        - clip extraction
      - no-live-detection sessions now still run Gemini segment scan before declaring no deliveries
      - merged detections rebuild `session.deliveries` before clipping
  - Added debug logs at major stage boundaries and per-segment outcomes.
- Check:
  - `xcodebuild -workspace wellBowled.xcworkspace -scheme wellBowled -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:wellBowledTests/DeliveryBatchPlannerTests -only-testing:wellBowledTests/WBConfigTests test`
- Result:
  - GREEN: `** TEST SUCCEEDED **`
  - New planner/config tests passed.
- Next action:
  - Run full unit suite (`wellBowledTests`) to confirm no regressions.

## Iteration 6
- Change:
  - Regression verification pass only (no production code changes).
- Check:
  - `xcodebuild -workspace wellBowled.xcworkspace -scheme wellBowled -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:wellBowledTests test`
- Result:
  - GREEN: `** TEST SUCCEEDED **` (full unit test target)
- Next action:
  - Sync canonical strategy doc with implemented runtime behavior and prepare device validation of delivery detection quality at nets.

## Iteration 7
- Change:
  - Fixed camera-switch recording truncation path so delivery detection uses full captured session:
    - `CameraService.swift`
      - close current recording segment before camera flip
      - restart recording immediately after camera flip
      - persist `recordedSegmentURLs` for post-session processing
    - `SessionViewModel.swift`
      - reset segment state at session start
      - resolve recording URL after session end from persisted segments
      - merge multi-segment recordings (camera flips) into one `.mov` before detection
    - `RecordingSegmentPlanner.swift`
      - deterministic segment filtering/dedupe + fallback resolution
  - Hardened app-lock behavior:
    - app remains `isIdleTimerDisabled = true` while active, including recording/front camera flows.
  - Hardened startup cue path:
    - switched startup chirp playback to AVAudioEngine route (no WAV/AVAudioPlayer branch)
    - startup cue uses `playAndRecord + defaultToSpeaker + Bluetooth options` for consistent routing.
  - Improved live mic resampling quality:
    - replaced integer decimation with linear interpolation to true 16kHz output for non-16k source rates (e.g. 44.1kHz).
- Check:
  - `xcodebuild -workspace wellBowled.xcworkspace -scheme wellBowled -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:wellBowledTests test`
  - `xcodebuild -workspace wellBowled.xcworkspace -scheme wellBowled -destination 'platform=iOS,id=00008120-001230560204A01E' -configuration Debug build`
  - `xcrun devicectl device install app --device E40F593B-ABB6-514A-873F-48CD7C4F98F3 <Debug-iphoneos/wellBowled.app>`
  - `xcrun devicectl device process launch --device E40F593B-ABB6-514A-873F-48CD7C4F98F3 --terminate-existing kanarupan.wellBowled`
- Result:
  - GREEN: unit tests passed.
  - GREEN: device build/install/launch succeeded.
- Next action:
  - Validate at nets:
    - startup chirp audibility (speaker + headphones)
    - live mic pickup with Gemini Live
    - camera flip during recording still yields full-session delivery detection.

## Iteration 8
- Change:
  - Hardened Gemini segment delivery parsing in `GeminiAnalysisService`:
    - accepts numeric values as `Double`, `Int`, `NSNumber`, and numeric strings
    - supports fallback payload keys (`release_times_sec`, `release_times`, `release_timestamp`)
    - keeps strict clamp behavior for timestamp/confidence bounds
  - Added richer detection diagnostics:
    - per-segment parsed release preview logs in `GeminiAnalysisService`
    - end-to-end candidate timeline logs in `SessionViewModel`:
      - segment schedule details
      - per-window candidate list
      - raw→merged Gemini candidates
      - live vs Gemini vs merged timeline at rebuild point
  - Added new unit coverage:
    - `Tests/GeminiSegmentDeliveryParsingTests.swift` (4 tests)
      - mixed numeric payload parsing
      - fallback array key parsing
      - clamp behavior
      - invalid JSON failure path
- Check:
  - Source-of-truth edits synced to build copy:
    - `cp .../GeminiAnalysisService.swift`
    - `cp .../SessionViewModel.swift`
    - `cp .../Tests/GeminiSegmentDeliveryParsingTests.swift`
  - Device-only unit run command:
    - `xcodebuild -workspace wellBowled.xcworkspace -scheme wellBowled -destination 'platform=iOS,id=00008120-001230560204A01E' -only-testing:wellBowledTests -allowProvisioningUpdates test`
- Result:
  - Build/signing path is GREEN on device destination.
  - Test execution is currently blocked at destination preflight when phone locks:
    - `Unlock Kanarupan to Continue`
    - run waits until device is unlocked.
- Next action:
  - Re-run the same device-only unit command with `kanarupan` unlocked to capture final GREEN evidence for iteration 8.
