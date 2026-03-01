# Codex Handover Guide

Quick reference for Codex to pick up iOS work on wellBowled.

---

## Current State (R19 — March 2026)

### What Works (validated on device)
- Live API WebSocket: mate hears user speech, responds with audio on iPhone 15
- Auto-reconnect with 1.5s backoff on TCP abort (~20s streaming limit)
- Screen idle timer disabled during sessions
- 8 mate personas: Aussie/English/Tamil/Tanglish × Male/Female
- Persona persisted via UserDefaults, voice + system instruction switch dynamically
- Brand: peacock blue #006D77 + grey blue #8DA9C4 + programmatic app icon
- Navigation: fullScreenCover for sessions

### What's NOT Validated on Device
- Delivery detection (MediaPipe wrist velocity spike → TTS count) — code wired, never confirmed live
- Post-session analysis (end session → clips → Gemini Pro → delivery cards) — code written, untested end-to-end
- Session resumption handle — captured but NOT sent on reconnect

---

## Roadmap: What to Build Next

### Tier 1: Complete MVP (end-to-end loop) — CRITICAL PATH
1. **Wire session resumption handle** — send `sessionResumption.handle` in setup message on reconnect. Handle already captured in `GeminiLiveService.swift`
2. **Validate delivery detection on device** — MediaPipe wrist spike → TTS count. Needs: model bundled (`pose_landmarker_heavy.task`), camera frame → `processFrame` wiring confirmed
3. **Validate post-session analysis** — end session → auto-clip → Gemini Pro → delivery cards in `SessionResultsView`
4. **Fix bugs from 2-3** — likely: model bundling path, clip timing edge cases, analysis prompt tuning

### Tier 2: Demo-worthy polish
5. **Pace band on delivery cards** — Gemini Pro classifies "medium pace" / "fast" from clips
6. **Session summary** — `generateSessionSummary()` after all deliveries analyzed
7. **Live delivery count overlay** — show count in `LiveSessionView` as deliveries are detected

### Tier 3: Challenge Mode (differentiator for hackathon)
8. Mate speaks target ("Try a yorker on off stump")
9. Evaluate delivery against target via clip → Gemini
10. Track challenge score

---

## File Locations

### iOS Source of Truth
```
/Users/kanarupan/workspace/wellBowled/ios/wellBowled/
```

### Key Files
| File | Purpose |
|------|---------|
| `GeminiLiveService.swift` | WebSocket wire protocol for Gemini Live API |
| `SessionViewModel.swift` | Full pipeline: camera → detection + Live API → analysis |
| `AudioSessionManager.swift` | AVAudioSession + AVAudioEngine 24kHz PCM playback |
| `CameraService.swift` | AVCaptureSession with video + audio + recording |
| `DeliveryDetector.swift` | MediaPipe wrist velocity detection |
| `WristVelocityTracker.swift` | Pure spike detection algorithm |
| `ClipExtractor.swift` | AVAssetExportSession clip extraction |
| `GeminiAnalysisService.swift` | REST generateContent for delivery analysis |
| `Session.swift` | Session struct (value type) + lifecycle |
| `WBConfig.swift` | Config: API keys, thresholds, 8 mate personas |
| `HomeView.swift` | API key prompt + persona settings + session entry |
| `LiveSessionView.swift` | Camera preview + transcript + session controls |
| `Protocols.swift` | VoiceMateService, DeliveryDetecting, CameraProviding |
| `TTSService.swift` | iOS TTS for count announcements |

### Tests
```
/Users/kanarupan/workspace/wellBowled/ios/wellBowled/Tests/
```
Tests go to `wellBowledTests/` target in Xcode — NOT in `Tests/` subfolder of app source (XCTest can't be imported in app target).

### Xcode Project
```
/Users/kanarupan/workspace/xcodeProj/wellBowled/
```

---

## Build Commands

```bash
# Sync source → Xcode project (always do this before building)
rm -rf /Users/kanarupan/workspace/xcodeProj/wellBowled/wellBowled/*.swift && \
cp -R /Users/kanarupan/workspace/wellBowled/ios/wellBowled/ \
     /Users/kanarupan/workspace/xcodeProj/wellBowled/wellBowled/

# Must remove Tests/ dir from app target after sync
rm -rf /Users/kanarupan/workspace/xcodeProj/wellBowled/wellBowled/Tests/

# Build for physical device (iPhone 15)
cd /Users/kanarupan/workspace/xcodeProj/wellBowled && \
xcodebuild -workspace wellBowled.xcworkspace \
  -scheme wellBowled \
  -destination "platform=iOS,id=00008120-001230560204A01E" \
  -configuration Debug clean build

# Build for simulator
cd /Users/kanarupan/workspace/xcodeProj/wellBowled && \
xcodebuild -workspace wellBowled.xcworkspace \
  -scheme wellBowled \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" build
```

---

## Architecture Decisions (Must Respect)

1. **Session is a struct** (value type) — NOT @Observable class. Must be struct for @Published propagation in SessionViewModel.
2. **CIContext must be cached** — instance property on SessionViewModel, not per-frame creation.
3. **Delivery timestamps need recording offset** — CMTime is arbitrary start, recording starts at 0.
4. **sendJSON must go through sendQueue.async** — thread safety for WebSocket sends.
5. **openContinuation needs NSLock protection** — URLSession delegates fire on arbitrary threads.
6. **AudioSessionManager.detach** — guard with isPlayerAttached flag to prevent crash on double-stop.
7. **No video/audio frames before setupComplete** — server aborts if data arrives pre-handshake.
8. **Gemini 3 models only** — Scout: `gemini-3-flash-preview`, Coach: `gemini-3-pro-preview`.
9. **Detection + count is on-device** — MediaPipe wrist velocity spike + iOS TTS. Zero API dependency for core loop.
10. **Live API is conversational, not monitoring** — it does NOT proactively call out deliveries. It responds to user speech.

---

## Testing Conventions

- TDD: write tests before implementation
- Never use mocks in production code paths
- Tests live in `ios/wellBowled/Tests/` (source of truth) and are synced to `wellBowledTests/` in Xcode project
- Existing test coverage: Session lifecycle, WBConfig, WristVelocityTracker, Enums, wire protocol encode/decode

---

## Commit Conventions

- **Codex**: prefix with `codex:` (e.g. `codex: add session resumption handle`)
- **Claude Code**: default prefix (e.g. `fix:`, `feat:`, `docs:`)
- Small commits. Each self-contained and honest.
- Always pull latest before starting — check for commits from both agents.
- Read `git log --oneline -10` before touching any file area.

---

## GCP Backend

- Project ID: `gen-lang-client-0673130950`
- Cloud Run: `wellbowled` in `us-central1`
- GCS bucket: `wellbowled-ai-clips`
- Bearer token: set in `AppConfig.swift`

---

## Dev Process

Follow `docs/dev_process.md` — no exceptions. The loop:
1. UNDERSTAND → 2. RESEARCH → 3. EXPERIMENT → 4. VERIFY → 5. PLAN → 6. TIDY → 7. TEST FIRST → 8. IMPLEMENT → 9. VERIFY AGAIN → 10. DOCUMENT

Sync docs at every step transition.
