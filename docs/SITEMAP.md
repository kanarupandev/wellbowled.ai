# Project Site Map

## iOS App (separate repo: `wellBowled/ios/wellBowled/`, not in this repo)

> Files below are **external/unverified in this repo**. Source of truth: `wellBowled` repo, branch `main`.
> Last verified commit: R19 (bug fixes, persona system, tests, brand update — March 2026).

| # | File | Purpose | Status |
|---|------|---------|--------|
| 1 | `GeminiLiveService.swift` | WebSocket wire protocol for Gemini Live API | R19: sendQueue race fix, continuation lock, timeout msg |
| 2 | `AudioSessionManager.swift` | AVAudioSession + AVAudioEngine 24kHz PCM playback | R19: detach safety |
| 3 | `SessionViewModel.swift` | Full pipeline: camera → detection + Live API → analysis | R19: CIContext cache, timestamp offset, idle timer |
| 4 | `HomeView.swift` | API key prompt + persona settings + session entry | R19: fullScreenCover, persona picker, brand |
| 5 | `LiveSessionView.swift` | Camera preview + transcript + session controls | R19: peacock blue theme, status bar |
| 6 | `WBConfig.swift` | Config: API keys, thresholds, 8 mate personas | R19: persona system (4 styles × 2 genders) |
| 7 | `CameraService.swift` | AVCaptureSession with video + audio + recording | external/unverified |
| 8 | `Protocols.swift` | VoiceMateService, DeliveryDetecting, CameraProviding | stable |
| 9 | `DeliveryDetector.swift` | MediaPipe wrist velocity detection | external/unverified |
| 10 | `WristVelocityTracker.swift` | Pure spike detection algorithm | unit tested |
| 11 | `TTSService.swift` | iOS TTS for count announcements | external/unverified |
| 12 | `ClipExtractor.swift` | AVAssetExportSession clip extraction | external/unverified |
| 13 | `GeminiAnalysisService.swift` | REST generateContent for delivery analysis | external/unverified |
| 14 | `Session.swift` | Session struct (value type) + lifecycle | R19: struct fix, unit tested |
| 15 | `SplashView.swift` | Animated splash screen | R19: brand update |
| 16 | `Models.swift` | Delivery, DeliveryAnalysis, PoseLandmark models | unit tested |
| 17 | `Enums.swift` | PaceBand, SessionMode, BowlingArm, DeliveryType/Length/Line | unit tested |
| 18 | `Delivery.swift` | DeliveryAnalysis, SessionSummary structs | stable |

### Tests (in wellBowledTests target)

| # | File | Coverage |
|---|------|----------|
| 1 | `SessionTests.swift` | Session lifecycle, value semantics, challenge scoring |
| 2 | `WBConfigTests.swift` | Persona properties, voice mapping, system instruction |
| 3 | `WristVelocityTrackerTests.swift` | Spike detection, cooldown, arm detection, utilities |
| 4 | `EnumsTests.swift` | PaceBand, Delivery codable, DeliveryAnalysis codable |
| 5 | `SessionLifecycleIntegrationTests.swift` | Full session flow, wire protocol encode/decode, timestamp offset |

## docs/

| # | File | Purpose | Status |
|---|------|---------|--------|
| 1 | `session_onboarding.md` | What this is, how to get running | Active |
| 2 | `dev_process.md` | Development workflow and conventions — **read first, follow always** | Active |
| 3 | `prompting_techniques.md` | Gemini prompt designs, cross-cutting techniques, honest limitations | Active |
| 4 | `architecture_decision.md` | Option B hybrid approach — live detection + post-session analysis | Active |

## research/

| # | File | Purpose | Status |
|---|------|---------|--------|
| 1 | `README.md` | Research index — completed findings, open questions, cross-references | Active |
| 2 | `cricket_resources.md` | Available datasets, models, APIs, open-source tools for cricket bowling | Active |

## experiments/

| # | Directory | Purpose | Status |
|---|-----------|---------|--------|
| 1 | `delivery_detection/` | Scout prompt accuracy, thinkingLevel optimization, MediaPipe ground truth | Phase 2 |
| 1a | `live_speed/` | Live API feasibility, speed estimation (Gemini Pro, YOLO, MediaPipe) | Complete |
| 2 | `deep_analysis/` | Expert biomechanical analysis prompts | Parked |
| 3 | `live_feedback/` | Multimodal Live API streaming | Planned |
| 4 | `legality_assessment/` | Elbow extension observation prompts | Planned |
| 5 | `speed_estimation/` | Speed classification and estimation | Planned |
