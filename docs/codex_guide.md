# Codex Handover Guide — wellBowled

> **Last updated**: R21 (2 March 2026) by Claude Code
> **Purpose**: Self-contained input for Codex when Claude quota is unavailable.
> **Rule**: Read this ENTIRE document before writing any code.

## CODE PATH — READ THIS FIRST

**All code lives here. Edit ONLY this path:**
```
/Users/kanarupan/workspace/wellBowled/ios/wellBowled/
```

**Tests live here:**
```
/Users/kanarupan/workspace/wellBowled/ios/wellBowled/Tests/
```

**DO NOT edit anything under:**
```
/Users/kanarupan/workspace/xcodeProj/
```
That directory is a disposable build copy. It gets wiped and replaced from the code path above on every sync.

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
| Gemini API key hardcoded default (no setup needed) | Working | `WBConfig.swift` |
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

### WORK HERE (source of truth)
```
/Users/kanarupan/workspace/wellBowled/ios/wellBowled/     ← ALL iOS code lives here
/Users/kanarupan/workspace/wellBowled/ios/wellBowled/Tests/ ← test source files
/Users/kanarupan/workspace/wellbowled.ai/docs/             ← canonical docs (this guide + architecture_decision.md)
```

### DO NOT MODIFY (read-only reference or stale)
```
/Users/kanarupan/workspace/xcodeProj/                      ← Xcode project, overwritten by sync command
/Users/kanarupan/workspace/wellbowled.ai/experiments/      ← archived experiment logs, known stale data (see section 10)
/Users/kanarupan/workspace/wellbowled.ai/research/         ← archived research, superseded findings
/Users/kanarupan/workspace/wellbowled.ai/codex/            ← old codex research/submission docs
/Users/kanarupan/workspace/wellBowled/backend/             ← no backend deployed, not in scope
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

## 5. Development Workflow (MUST follow this loop)

There are TWO separate directories. You write code in the **source of truth**, then copy it to the **Xcode project** to build. Never edit the Xcode project directly — it gets overwritten on every sync.

```
SOURCE OF TRUTH (you edit here)          XCODE PROJECT (build from here)
/Users/kanarupan/workspace/              /Users/kanarupan/workspace/
  wellBowled/ios/wellBowled/               xcodeProj/wellBowled/wellBowled/
       ↓ cp -R                                    ↓ xcodebuild
  Your .swift files                        Compiled app → iPhone
```

### Target Device
- **Name**: Kanarupan
- **Model**: iPhone 15 (iPhone15,4)
- **CoreDevice UUID**: `00008120-001230560204A01E`
- **Connection**: USB cable to Mac, phone must be unlocked

### The Loop: Edit → Sync → Build → Install → Monitor → Iterate

#### Step 1: IMPLEMENT — edit code in source of truth

All code changes go here and ONLY here:
```
/Users/kanarupan/workspace/wellBowled/ios/wellBowled/
```
Never touch files under `/Users/kanarupan/workspace/xcodeProj/` — they get wiped on sync.

#### Step 2: SYNC — copy source to Xcode project

This replaces all Swift files in the Xcode project with the source of truth:
```bash
rm -rf /Users/kanarupan/workspace/xcodeProj/wellBowled/wellBowled/*.swift && \
cp -R /Users/kanarupan/workspace/wellBowled/ios/wellBowled/ \
     /Users/kanarupan/workspace/xcodeProj/wellBowled/wellBowled/
```

Then remove Tests/ from the app target (XCTest can't be imported in app target):
```bash
rm -rf /Users/kanarupan/workspace/xcodeProj/wellBowled/wellBowled/Tests/
```

Copy test files to the separate test target:
```bash
cp /Users/kanarupan/workspace/wellBowled/ios/wellBowled/Tests/*.swift \
   /Users/kanarupan/workspace/xcodeProj/wellBowled/wellBowledTests/
```

#### Step 3: BUILD + INSTALL — compile and deploy to iPhone

```bash
cd /Users/kanarupan/workspace/xcodeProj/wellBowled && \
xcodebuild -workspace wellBowled.xcworkspace \
  -scheme wellBowled \
  -destination "platform=iOS,id=00008120-001230560204A01E" \
  -configuration Debug clean build
```

Wait for `** BUILD SUCCEEDED **`. The app is now installed on the iPhone. Open it from the home screen.

If you only need a compile check (no device needed):
```bash
cd /Users/kanarupan/workspace/xcodeProj/wellBowled && \
xcodebuild -workspace wellBowled.xcworkspace \
  -scheme wellBowled \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" build
```

#### Step 4: VERIFY — monitor device logs

Stream live logs from the iPhone to see print statements, os.Logger output, and crashes:
```bash
# Stream all wellBowled logs from the device
xcrun devicectl device process logstream --device 00008120-001230560204A01E \
  --process-name wellBowled
```

Alternative — filter by subsystem (matches `Logger(subsystem: "com.wellbowled", ...)`):
```bash
log stream --device 00008120-001230560204A01E \
  --predicate 'subsystem == "com.wellbowled"' --style compact
```

Key log categories to watch:
- `com.wellbowled/SessionVM` — session lifecycle, delivery detection, analysis progress
- `com.wellbowled/Analysis` — Gemini API calls, DNA extraction
- `com.wellbowled/Live` — WebSocket connection, audio, reconnects

If the app crashes, get the crash log:
```bash
xcrun devicectl device process crashlog --device 00008120-001230560204A01E
```

#### Step 5: RUN TESTS

```bash
cd /Users/kanarupan/workspace/xcodeProj/wellBowled && \
xcodebuild -workspace wellBowled.xcworkspace \
  -scheme wellBowled \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" test
```

#### Step 6: ITERATE — go back to Step 1

Fix issues found in Step 4/5, then repeat the loop: Edit → Sync → Build → Install → Monitor.

#### Step 7: COMMIT — when feature is working

```bash
cd /Users/kanarupan/workspace/wellBowled && \
git add <changed files> && \
git commit -m "codex: <description>" && \
git push
```

### Troubleshooting
- **"device not found"** → iPhone must be plugged in via USB cable and unlocked
- **"unable to install"** → Trust the developer certificate on iPhone: Settings → General → VPN & Device Management → trust the dev profile
- **"BUILD FAILED"** → Read the error lines. Fix in source of truth (Step 1), NOT in Xcode project
- **Pods out of date** → `cd /Users/kanarupan/workspace/xcodeProj/wellBowled && pod install`
- **App crashes on launch** → Check crash log (Step 4), likely a missing nil check or force unwrap

### Prerequisites
- Xcode 16+ with iOS 17 SDK
- CocoaPods installed (pods already in repo, run `pod install` only if missing)
- MediaPipeTasksVision pod (included via CocoaPods)
- Gemini API key: hardcoded default — works out of the box, no setup needed

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

## 10. Known Doc Inconsistencies (DO NOT be misled)

The `experiments/` and `research/` folders contain historical exploration logs with known stale data. **Do NOT use them as source of truth.** Only this guide and `docs/architecture_decision.md` are canonical.

| Stale Artifact | What's Wrong | Correct Answer |
|----------------|-------------|----------------|
| `experiments/delivery_detection/003_results.json` | Shows `release_ts: 0.0333`, `bowling_arm: left` | Orphaned from a different video/old run. 003_findings.md says ground truth is right arm at 1.000s. **Ignore this JSON.** |
| `experiments/delivery_detection/003_findings.md` | Recommends `thinkingLevel: MINIMAL` | **SUPERSEDED by Phase 2.** MINIMAL overfits on smoke tests, degrades on real video. App uses DEFAULT thinking. |
| `experiments/delivery_detection/phase2_configs.md` | "6/7 PASS" headline | Uses mixed thresholds (0.2s broadcast, 0.3s nets). Strict 0.2s alone is ~4/5. The architecture doc already says "6/7 PASS at mixed thresholds" — the caveat is baked in. |
| `experiments/live_audio/result_audio_validation.json` | File name suggests audio validation results | It's a raw failed run: 0 deliveries detected from 71 video frames. Confirms Live API is conversational only — does NOT proactively detect. This is the correct and final conclusion. |
| Various codex research docs | Mix of "hypothesis" vs "validated" for Live API | **Final answer**: Live API voice conversation = VALIDATED on device. Live API delivery detection = DOES NOT WORK (by design — it's conversational, not monitoring). Detection is on-device MediaPipe only. |

**Rule: Only read files in `ios/wellBowled/` for implementation. Treat `experiments/` and `research/` as archived history.**

---

## 11. Dev Process

Follow `docs/dev_process.md` — no exceptions:
1. UNDERSTAND → 2. RESEARCH → 3. EXPERIMENT → 4. VERIFY → 5. PLAN → 6. TIDY → 7. TEST FIRST → 8. IMPLEMENT → 9. VERIFY AGAIN → 10. DOCUMENT

Sync docs at every step transition.
