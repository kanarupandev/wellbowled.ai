# Codex Handover Guide — wellBowled

> **Last updated**: R21 (2 March 2026) by Claude Code
> **Purpose**: Self-contained input for Codex when Claude quota is unavailable.
> **Rule**: Read this ENTIRE document before writing any code.

---

## 1. Current State (R21)

### What's DONE and validated
| Feature | Status | Key Files |
|---------|--------|-----------|
| Live API WebSocket (mate hears + speaks) | On device | `GeminiLiveService.swift` |
| Auto-reconnect (1.5s backoff on TCP abort) | On device | `GeminiLiveService.swift` |
| Session resumption handle sent on reconnect | On device | `GeminiLiveService.swift` |
| 8 mate personas (4 lang × 2 gender) | On device | `WBConfig.swift`, `HomeView.swift` |
| MediaPipe delivery detection (wrist spike) | Code wired, builds | `DeliveryDetector.swift`, `WristVelocityTracker.swift` |
| Post-session analysis (clips → Gemini Pro) | Code wired, builds | `SessionViewModel.swift`, `GeminiAnalysisService.swift` |
| **BowlingDNA action signature (20-dim)** | Code wired, builds, unit tested | `BowlingDNA.swift`, `BowlingDNAMatcher.swift`, `FamousBowlerDatabase.swift` |
| BowlingDNA UI (similarity ring + traits) | Code wired, builds | `BowlingDNAView.swift`, `LiveSessionView.swift` |
| wristOmega + releaseWristY on Delivery | Code wired | `Models.swift`, `DeliveryDetector.swift` |
| Gemini DNA extraction prompt | Code wired | `GeminiAnalysisService.swift` |
| pose_landmarker.task in iOS source | Bundled | `ios/wellBowled/pose_landmarker.task` |
| Brand (peacock blue + grey blue + logo) | On device | `DesignSystem.swift` |
| Unit tests (Session, WBConfig, WristVelocity, DNA) | Passing | `Tests/` |

### What's NOT validated on device yet
- Delivery detection firing live (MediaPipe + camera frames)
- Post-session clip extraction + Gemini analysis end-to-end
- BowlingDNA extraction from real clips (Gemini vision prompt)
- Challenge mode (not started)

---

## 2. Roadmap

### DONE — Tiers 1-3
- MVP pipeline (detect → count → clip → analyze)
- Demo polish (personas, pace bands, session summary, results UI)
- BowlingDNA action signature (model, matcher, database, extraction, UI, tests)

### NEXT — Tier 4: Challenge Mode (differentiator)
| Step | Task | Requirements | Approach |
|------|------|-------------|----------|
| 4.1 | Mate speaks challenge target | Mate says "Try a yorker on off stump" | Add `speakChallenge(target:)` to `VoiceMateService` protocol. Send text via Live API `sendContext()`. TTS fallback if Live API disconnected. |
| 4.2 | Generate random targets | Target pool: yorker/bouncer/off-stump/leg-stump combos | Static array in `WBConfig.swift`. Rotate after each delivery. |
| 4.3 | Evaluate delivery vs target | After clip extraction, send clip + target to Gemini | Use existing `evaluateChallenge(clipURL:target:)` in `GeminiAnalysisService.swift`. Already implemented, just not wired. |
| 4.4 | Wire challenge into SessionViewModel | On delivery detect → extract clip → evaluate → update score | In `runPostSessionAnalysis`, after Phase 2 analysis, add Phase 2b: challenge evaluation if `session.mode == .challenge`. |
| 4.5 | Track + display challenge score | "2 out of 3 yorkers landed (67%)" | `Session.recordChallengeResult(hit:)` already exists. Show in `SessionResultsView` summary section. |
| 4.6 | Challenge mode entry in HomeView | Button to start challenge session | Add `.challenge` mode option. Pass to `startSession(mode:)`. |
| 4.7 | Unit tests for challenge flow | Test target generation, score tracking, evaluation wiring | `Tests/ChallengeTests.swift` |

### PARKED — Tier 5: Post-hackathon
- Ball tracking (YOLO 240fps)
- Zone-based pitch maps
- Biomechanical deep analysis (6-phase Expert)
- Precise speed estimation (radar ground truth needed)
- BowlingDNA trend tracking across sessions
- DNA sharing / comparison

---

## 3. File Locations

### iOS Source of Truth
```
/Users/kanarupan/workspace/wellBowled/ios/wellBowled/
```

### Key Files by Feature Area

**Core Pipeline**
| File | Purpose |
|------|---------|
| `SessionViewModel.swift` | Full pipeline orchestrator: camera → detection + Live API → analysis → DNA |
| `GeminiLiveService.swift` | WebSocket wire protocol for Gemini Live API |
| `GeminiAnalysisService.swift` | REST generateContent for delivery analysis + DNA extraction |
| `CameraService.swift` | AVCaptureSession with video + audio + recording |
| `AudioSessionManager.swift` | AVAudioSession + AVAudioEngine 24kHz PCM playback |

**Delivery Detection**
| File | Purpose |
|------|---------|
| `DeliveryDetector.swift` | MediaPipe PoseLandmarker → wrist tracking → spike detection |
| `WristVelocityTracker.swift` | Pure spike detection algorithm (angular velocity) |
| `ClipExtractor.swift` | AVAssetExportSession 5s clip extraction |
| `TTSService.swift` | iOS TTS for count announcements |

**BowlingDNA**
| File | Purpose |
|------|---------|
| `BowlingDNA.swift` | DNA struct (20 fields) + all enums (18 categorical types) + `BowlingDNAMatch` |
| `BowlingDNAMatcher.swift` | `BowlingDNAVectorEncoder` (ordinal encoding) + `BowlingDNAMatcher` (weighted Euclidean) |
| `FamousBowlerDatabase.swift` | 10 bowler profiles: McGrath, Akram, Warne, Akhtar, Murali, Anderson, Starc, Ashwin, Marshall, Bumrah |
| `BowlingDNAView.swift` | UI: similarity ring, closest phase, biggest difference, signature traits |

**Models & Config**
| File | Purpose |
|------|---------|
| `Models.swift` | `Delivery` struct (incl. wristOmega, releaseWristY, dna, dnaMatches) |
| `Session.swift` | Session struct (value type) + lifecycle + challenge state |
| `Enums.swift` | PaceBand, BowlingArm, DeliveryType/Length/Line, ChallengeResult |
| `Delivery.swift` | DeliveryAnalysis + SessionSummary (Gemini response types) |
| `Protocols.swift` | All protocols: DeliveryDetecting, VoiceMateService, ClipExtracting, etc. |
| `WBConfig.swift` | API keys, thresholds, model names, persona configs |

**Views**
| File | Purpose |
|------|---------|
| `LiveSessionView.swift` | Camera preview + session controls + `SessionResultsView` + `DeliveryRow` |
| `HomeView.swift` | API key prompt + persona settings + session entry |
| `BowlingDNAView.swift` | DNA match cards + detail view |

**Tests**
```
/Users/kanarupan/workspace/wellBowled/ios/wellBowled/Tests/
```
Tests go to `wellBowledTests/` target in Xcode — NOT in `Tests/` subfolder of app source (XCTest can't be imported in app target).

---

## 4. Architecture Decisions (MUST RESPECT)

1. **Session is a struct** (value type) — NOT @Observable class. Required for @Published propagation.
2. **CIContext must be cached** — instance property on SessionViewModel, NOT per-frame.
3. **Delivery timestamps need recording offset** — `CMTime` is arbitrary start, recording starts at 0.
4. **sendJSON must go through sendQueue.async** — thread safety for WebSocket sends.
5. **openContinuation needs NSLock** — URLSession delegates fire on arbitrary threads.
6. **No video/audio frames before setupComplete** — server aborts pre-handshake data.
7. **Gemini 3 models only** — Scout: `gemini-3-flash-preview`, Coach: `gemini-3-pro-preview`.
8. **Detection + count is on-device** — zero API dependency for core loop.
9. **Live API is conversational, not monitoring** — responds to user speech, does NOT proactively detect.
10. **BowlingDNA fields are all optional** — partial DNA is valid (graceful degradation).
11. **Release dimensions weighted 2x** in DNA matching — most discriminating phase.
12. **wristOmega normalization**: `clamp((|omega| - 800) / 1200, 0, 1)`.

---

## 5. Build & Deploy

### Sync + Build (ALWAYS do this sequence)

```bash
# Step 1: Sync iOS source → Xcode project
rm -rf /Users/kanarupan/workspace/xcodeProj/wellBowled/wellBowled/*.swift && \
cp -R /Users/kanarupan/workspace/wellBowled/ios/wellBowled/ \
     /Users/kanarupan/workspace/xcodeProj/wellBowled/wellBowled/

# Step 2: Remove Tests/ from app target (XCTest can't import in app target)
rm -rf /Users/kanarupan/workspace/xcodeProj/wellBowled/wellBowled/Tests/

# Step 3: Copy tests to test target
cp /Users/kanarupan/workspace/wellBowled/ios/wellBowled/Tests/*.swift \
   /Users/kanarupan/workspace/xcodeProj/wellBowled/wellBowledTests/

# Step 4a: Build for simulator (fast iteration)
cd /Users/kanarupan/workspace/xcodeProj/wellBowled && \
xcodebuild -workspace wellBowled.xcworkspace \
  -scheme wellBowled \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" build

# Step 4b: Build for physical device (iPhone 15)
cd /Users/kanarupan/workspace/xcodeProj/wellBowled && \
xcodebuild -workspace wellBowled.xcworkspace \
  -scheme wellBowled \
  -destination "platform=iOS,id=00008120-001230560204A01E" \
  -configuration Debug clean build

# Step 5: Run tests
cd /Users/kanarupan/workspace/xcodeProj/wellBowled && \
xcodebuild -workspace wellBowled.xcworkspace \
  -scheme wellBowled \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" test
```

### GCP Backend
```bash
# Project: gen-lang-client-0673130950
# Service: wellbowled in us-central1
# Bucket: wellbowled-ai-clips

# Deploy backend
gcloud run deploy wellbowled --source backend/ --region us-central1

# Check service
gcloud run services describe wellbowled --region us-central1
```

### Prerequisites
- Xcode 16+ with iOS 17 SDK
- CocoaPods: `cd /Users/kanarupan/workspace/xcodeProj/wellBowled && pod install`
- MediaPipeTasksVision pod (for pose detection)
- Gemini API key: set in app Settings or Info.plist `GEMINI_API_KEY`

---

## 6. Testing Conventions

- **TDD**: write tests before implementation
- **Never use mocks in production code paths**
- Tests source of truth: `ios/wellBowled/Tests/`
- Tests Xcode target: `wellBowledTests/` (synced via Step 3 above)
- Existing coverage: Session lifecycle, WBConfig, WristVelocityTracker, Enums, Delivery codable, BowlingDNA (encoding, matching, normalization, codable round-trip)

---

## 7. Commit Conventions

- **Codex**: prefix with `codex:` (e.g. `codex: add challenge mode entry point`)
- **Claude Code**: standard prefixes (`fix:`, `feat:`, `docs:`)
- Small, self-contained commits
- Always `git pull` before starting — check for commits from both agents
- Read `git log --oneline -10` before touching any file area
- Repos:
  - iOS: `/Users/kanarupan/workspace/wellBowled` (branch: `codex/full-dev-takeover`)
  - Docs/experiments: `/Users/kanarupan/workspace/wellbowled.ai` (branch: `claude/ios-fresh-build`)

---

## 8. Brand

| Token | Hex | SwiftUI |
|-------|-----|---------|
| Peacock Blue | `#006D77` | `Color(red: 0, green: 0.427, blue: 0.467)` |
| Grey Blue | `#8DA9C4` | `Color(red: 0.55, green: 0.66, blue: 0.77)` |
| Dark BG | `#0D1117` | `Color(red: 0.051, green: 0.067, blue: 0.09)` |

---

## 9. Quick Reference: What's Where

```
wellBowled/ios/wellBowled/
├── BowlingDNA.swift              # DNA struct + 18 enum types + BowlingDNAMatch
├── BowlingDNAMatcher.swift       # Vector encoder + weighted Euclidean matcher
├── BowlingDNAView.swift          # DNA UI cards (similarity ring, traits)
├── FamousBowlerDatabase.swift    # 10 famous bowler profiles
├── DeliveryDetector.swift        # MediaPipe pose → wrist spike detection
├── WristVelocityTracker.swift    # Angular velocity algorithm
├── GeminiLiveService.swift       # WebSocket Live API
├── GeminiAnalysisService.swift   # REST analysis + DNA extraction
├── SessionViewModel.swift        # Pipeline orchestrator
├── CameraService.swift           # AVCaptureSession
├── ClipExtractor.swift           # 5s clip extraction
├── AudioSessionManager.swift     # Audio engine
├── TTSService.swift              # Speech synthesis
├── Models.swift                  # Delivery, PoseLandmark, etc.
├── Session.swift                 # Session struct
├── Enums.swift                   # PaceBand, BowlingArm, etc.
├── Protocols.swift               # All protocol definitions
├── WBConfig.swift                # Config + personas
├── LiveSessionView.swift         # Camera + session UI + results
├── HomeView.swift                # Entry point + settings
├── pose_landmarker.task          # MediaPipe model (9MB, auto-bundled)
└── Tests/
    └── BowlingDNATests.swift     # DNA unit tests
```

---

## 10. Dev Process

Follow `docs/dev_process.md` — no exceptions:
1. UNDERSTAND → 2. RESEARCH → 3. EXPERIMENT → 4. VERIFY → 5. PLAN → 6. TIDY → 7. TEST FIRST → 8. IMPLEMENT → 9. VERIFY AGAIN → 10. DOCUMENT

Sync docs at every step transition.
