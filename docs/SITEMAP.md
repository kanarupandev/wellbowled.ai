# Project Site Map

## iOS App (separate repo: `wellBowled/ios/wellBowled/`, not in this repo)

| # | File | Purpose | Status |
|---|------|---------|--------|
| 1 | `GeminiLiveService.swift` | WebSocket wire protocol for Gemini Live API | Step 1 done |
| 2 | `AudioSessionManager.swift` | AVAudioSession + AVAudioEngine 24kHz PCM playback | Step 1 done |
| 3 | `SessionViewModel.swift` | Wires CameraService → Live API (video + audio) | Step 1 done |
| 4 | `HomeView.swift` | API key prompt + session entry | Step 1 done |
| 5 | `LiveSessionView.swift` | Camera preview + transcript + connection status | Step 1 done |
| 6 | `WBConfig.swift` | Central config: API keys, thresholds, mate persona | Step 1 done |
| 7 | `CameraService.swift` | AVCaptureSession with video + audio outputs | Step 1 done |
| 8 | `Protocols.swift` | VoiceMateService, DeliveryDetecting, CameraProviding | Step 1 done |
| 9 | `DeliveryDetector.swift` | MediaPipe wrist velocity detection | Step 2.2 (guarded) |
| 10 | `WristVelocityTracker.swift` | Pure spike detection algorithm | Step 2.2 |
| 11 | `TTSService.swift` | iOS TTS for count + pace announcements | Step 2.2 |

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
