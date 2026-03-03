# Codex Handover Guide — wellBowled

> **Last updated**: R24 (3 March 2026) by Codex
> **Purpose**: Self-contained input for Codex when Claude quota is unavailable.
> **Rule**: Read this ENTIRE document before writing any code.

## CODE PATH — READ THIS FIRST

**ONE repo for everything: `wellbowled.ai`**

```
/Users/kanarupan/workspace/wellbowled.ai/
├── ios/wellBowled/          ← ALL Swift code lives here. EDIT ONLY HERE.
├── ios/wellBowled/Tests/    ← test source files
├── docs/                    ← canonical docs (this guide + architecture_decision.md)
├── experiments/             ← archived, DO NOT USE (see section 10)
├── research/                ← archived, DO NOT USE
└── codex/                   ← old codex research, DO NOT USE
```

**Git repo:**
```
cd /Users/kanarupan/workspace/wellbowled.ai
git branch: codex/dev
```

**DO NOT edit anything under:**
```
/Users/kanarupan/workspace/xcodeProj/     ← disposable build copy, wiped on every sync
/Users/kanarupan/workspace/dont_use_obsolete_wellBowled/    ← OBSOLETE repo, do not use
```

---

## 0. Operating Contract (Non-Negotiable)

1. Do not ask the user how to execute the development process.
2. Use docs + repo + tooling to resolve workflow details:
- `docs/dev_process.md`
- `docs/project_dev_deploy_guide.md`
- this handover guide
3. Ask the user only for hard blockers:
- missing product decision
- missing permission/credential/device access
- unresolved contradiction in canonical docs
4. Any blocker escalation must include:
- commands already attempted
- exact error/evidence
- next best options to proceed
5. Deploy means reinstall/update app on target iPhone and verify launch.

---

## 1. Current State (R24)

### What's DONE and validated
| Feature | Status | Key Files |
|---------|--------|-----------|
| Live API WebSocket (mate hears + speaks) | On device | `GeminiLiveService.swift` |
| Auto-reconnect (1.5s backoff on TCP abort) | On device | `GeminiLiveService.swift` |
| Session resumption handle sent on reconnect | On device | `GeminiLiveService.swift` |
| Proactive waterfall onboarding (greet → plan → 5s reprompt → setup check → pilot run → "Session started") | Code wired, unit tested | `SessionViewModel.swift`, `WBConfig.swift`, `Tests/SessionViewModelPromptTests.swift` |
| Live mode switch tool call (`switch_session_mode`) | Code wired, unit tested | `GeminiLiveService.swift`, `Protocols.swift`, `SessionViewModel.swift`, `Enums.swift` |
| Live mode fine-print label at top-left (`Mode: Free/Challenge`) | Code wired | `LiveSessionView.swift`, `Enums.swift` |
| Live session timeout set to 3 minutes (config one-liner) | Code wired, unit tested | `WBConfig.swift`, `Tests/WBConfigTests.swift` |
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
- Challenge mode evaluation accuracy (hit/miss correctness not benchmarked on real sessions)
- Model-driven mode switching via live tool call on physical device (free ↔ challenge during planning/live)

---

## 2. Roadmap

### DONE — Tiers 1-3
- MVP pipeline (detect → count → clip → analyze)
- Demo polish (personas, pace bands, session summary, results UI)
- BowlingDNA action signature (model, matcher, database, extraction, UI, tests)

### NEXT — Tier 4: Challenge Mode (differentiator)
| Step | Task | Requirements | Approach |
|------|------|-------------|----------|
| 4.1 | Mate speaks challenge target | Mate says "Try a yorker on off stump" | `speakChallenge(target:)` added; sends context through Live API with TTS fallback in SessionViewModel. |
| 4.2 | Generate random targets | Target pool: yorker/bouncer/off-stump/leg-stump combos | `WBConfig.challengeTargets` + `ChallengeEngine` rotation/reset wiring in SessionViewModel. |
| 4.3 | Evaluate delivery vs target | After clip extraction, send clip + target to Gemini | `evaluateChallenge(clipURL:target:)` wired in post-session Phase 2b. |
| 4.4 | Track + display challenge score | "2 out of 3 yorkers landed (67%)" | `Session.recordChallengeResult(hit:)` updates summary score path. |
| 4.5 | Validate challenge accuracy | Confirm hit/miss quality over real clips | Run controlled device sessions and review false hit/miss cases. |
| 4.6 | Complete mode-entry UI wiring | Start `.challenge` from Home, pass mode into live session start | Finish and validate `HomeView` + `LiveSessionView` mode handoff. |
| 4.7 | Unit tests for challenge flow | Target generation, formatting, score path, mode wiring regressions | Add `Tests/ChallengeEngineTests.swift` and update affected tests. |

### PARKED — Tier 5: Post-hackathon
- Ball tracking (YOLO 240fps)
- Zone-based pitch maps
- Biomechanical deep analysis (6-phase Expert)
- Precise speed estimation (radar ground truth needed)
- BowlingDNA trend tracking across sessions
- DNA sharing / comparison

---

## 3. File Locations

### WORK HERE (source of truth — all in wellbowled.ai repo)
```
/Users/kanarupan/workspace/wellbowled.ai/ios/wellBowled/       ← ALL iOS code
/Users/kanarupan/workspace/wellbowled.ai/ios/wellBowled/Tests/ ← test source files
/Users/kanarupan/workspace/wellbowled.ai/docs/                 ← canonical docs
```

### DO NOT MODIFY
```
/Users/kanarupan/workspace/xcodeProj/                          ← disposable Xcode build copy
/Users/kanarupan/workspace/dont_use_obsolete_wellBowled/      ← OBSOLETE, do not use
/Users/kanarupan/workspace/wellbowled.ai/experiments/          ← archived, stale (see section 10)
/Users/kanarupan/workspace/wellbowled.ai/research/             ← archived, superseded
/Users/kanarupan/workspace/wellbowled.ai/codex/                ← old codex research
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
/Users/kanarupan/workspace/wellbowled.ai/ios/wellBowled/Tests/
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

You write code in `wellbowled.ai/ios/wellBowled/`, then copy it to the Xcode project to build. Never edit the Xcode project directly — it gets overwritten on every sync.

```
SOURCE OF TRUTH (you edit here)             XCODE PROJECT (build from here)
/Users/kanarupan/workspace/                 /Users/kanarupan/workspace/
  wellbowled.ai/ios/wellBowled/               xcodeProj/wellBowled/wellBowled/
       ↓ cp -R                                       ↓ xcodebuild
  Your .swift files                           Compiled app → iPhone
```

### Target Device
- **Name**: Kanarupan
- **Model**: iPhone 15 (iPhone15,4)
- **CoreDevice UUID**: `E40F593B-ABB6-514A-873F-48CD7C4F98F3` (verify with `xcrun devicectl list devices`)
- **Connection**: USB cable to Mac, phone must be unlocked

### The Loop: Edit → Sync → Build → Install → Monitor → Iterate

#### Step 0: AUTONOMOUS STARTUP — no process questions

Before editing:
```bash
cd /Users/kanarupan/workspace/wellbowled.ai && git log --oneline -15
```
Resolve workflow details from docs and repo state. Ask user only for hard blockers listed in section 0.

#### Step 1: IMPLEMENT — edit code in source of truth

All code changes go here and ONLY here:
```
/Users/kanarupan/workspace/wellbowled.ai/ios/wellBowled/
```
Never touch files under `/Users/kanarupan/workspace/xcodeProj/` — they get wiped on sync.

#### Step 2: SYNC — copy source to Xcode project

This replaces all Swift files in the Xcode project with the source of truth:
```bash
rm -rf /Users/kanarupan/workspace/xcodeProj/wellBowled/wellBowled/*.swift && \
cp -R /Users/kanarupan/workspace/wellbowled.ai/ios/wellBowled/ \
     /Users/kanarupan/workspace/xcodeProj/wellBowled/wellBowled/
```

Then remove Tests/ from the app target (XCTest can't be imported in app target):
```bash
rm -rf /Users/kanarupan/workspace/xcodeProj/wellBowled/wellBowled/Tests/
```

Copy test files to the separate test target:
```bash
cp /Users/kanarupan/workspace/wellbowled.ai/ios/wellBowled/Tests/*.swift \
   /Users/kanarupan/workspace/xcodeProj/wellBowled/wellBowledTests/
```

#### Step 3: BUILD + REINSTALL — compile and deploy to iPhone

```bash
cd /Users/kanarupan/workspace/xcodeProj/wellBowled && \
xcodebuild -workspace wellBowled.xcworkspace \
  -scheme wellBowled \
  -destination "platform=iOS,id=E40F593B-ABB6-514A-873F-48CD7C4F98F3" \
  -configuration Debug clean build

APP_PATH=$(find /Users/kanarupan/Library/Developer/Xcode/DerivedData/wellBowled-* \
  -path '*/Build/Products/Debug-iphoneos/wellBowled.app' -type d | grep -v 'Index.noindex' | sort | tail -n 1) && \
xcrun devicectl device install app --device E40F593B-ABB6-514A-873F-48CD7C4F98F3 "$APP_PATH"
```

Wait for `** BUILD SUCCEEDED **`. Then confirm install succeeded. Launch from the home screen, or launch from terminal:

```bash
xcrun devicectl device process launch --device E40F593B-ABB6-514A-873F-48CD7C4F98F3 kanarupan.wellBowled
```

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
xcrun devicectl device process logstream --device E40F593B-ABB6-514A-873F-48CD7C4F98F3 \
  --process-name wellBowled
```

Alternative — filter by subsystem (matches `Logger(subsystem: "com.wellbowled", ...)`):
```bash
log stream --device E40F593B-ABB6-514A-873F-48CD7C4F98F3 \
  --predicate 'subsystem == "com.wellbowled"' --style compact
```

Key log categories to watch:
- `com.wellbowled/SessionVM` — session lifecycle, delivery detection, analysis progress
- `com.wellbowled/Analysis` — Gemini API calls, DNA extraction
- `com.wellbowled/Live` — WebSocket connection, audio, reconnects

If the app crashes, get the crash log:
```bash
xcrun devicectl device process crashlog --device E40F593B-ABB6-514A-873F-48CD7C4F98F3
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
cd /Users/kanarupan/workspace/wellbowled.ai && \
git add ios/wellBowled/<changed files> && \
git commit -m "codex: <description>" && \
git push
```

### Troubleshooting
- **"device not found"** → iPhone must be plugged in via USB cable and unlocked
- **"Unable to launch ... device was not unlocked"** → unlock iPhone screen, then retry `xcrun devicectl device process launch`
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
- Tests source of truth: `wellbowled.ai/ios/wellBowled/Tests/`
- Tests Xcode target: `wellBowledTests/` (synced via Step 3 above)
- Existing coverage: Session lifecycle, WBConfig, WristVelocityTracker, Enums, Delivery codable, BowlingDNA (encoding, matching, normalization, codable round-trip)

---

## 7. Commit Conventions

- **Codex**: prefix with `codex:` (e.g. `codex: add challenge mode entry point`)
- **Claude Code**: standard prefixes (`fix:`, `feat:`, `docs:`)
- Small, self-contained commits
- Always `git pull` before starting — check for commits from both agents
- Read `git log --oneline -10` before touching any file area
- **Single repo**: `/Users/kanarupan/workspace/wellbowled.ai` (branch: `codex/dev`)

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
wellbowled.ai/ios/wellBowled/
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
