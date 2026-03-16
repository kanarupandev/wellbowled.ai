# wellBowled.ai — AI Bowling Coach Powered by Gemini Live

A native iOS app that puts an elite cricket bowling coach in your earbuds. Gemini Live watches your video feed, hears you through the mic, and coaches you in real time — like a knowledgeable friend standing behind the arm at the nets.

## What It Does

- **Real-time voice coaching** via Gemini Live API — the mate sees your video, hears your voice, and gives spoken biomechanical feedback after each delivery
- **Automatic delivery detection** from 30-second rolling video segments using Gemini 2.5 Flash
- **Challenge-driven training** — the mate sets targets ("Yorker on off stump"), evaluates hit/miss, tracks your score, and rotates challenges
- **Deep biomechanical analysis** of 5-second delivery clips using Gemini 3 Pro — 5-phase breakdown, pace estimation, execution quality rating
- **Bowling DNA matching** against 103 famous international bowlers with quality-dampened similarity scoring
- **Post-session review agent** — a dedicated voice agent walks through each delivery with voice-controlled video playback (play, pause, slow-mo, seek)

## Architecture

```
┌───────────────────────────────────────────────────────────┐
│                    iPhone (Native iOS)                     │
│                                                           │
│  Camera + Mic ──→ Gemini Live API (2.5 Flash Native Audio)│
│       ↕ Bidirectional voice + video                       │
│       ↕ Tool calls: timer, challenges, playback, nav      │
│                                                           │
│  30s video segments ──→ Gemini 2.5 Flash                  │
│       → Delivery timestamps + confidence                  │
│                                                           │
│  5s delivery clips ───→ Gemini 3 Pro                      │
│       → Phase analysis + DNA + quality + pace             │
│                                                           │
│  5s delivery clips ───→ Gemini 2.5 Flash                  │
│       → Challenge evaluation (hit/miss)                   │
│                                                           │
│  On-device: AVFoundation, clip extraction, stump          │
│  calibration, delivery dedup, TTS, audio session mgmt     │
└───────────────────────────────────────────────────────────┘
```

**3 Gemini models, 5 tool calls, 2 agent lifecycles.**

## How Gemini Is Central

| Model | Role | Without It |
|---|---|---|
| Gemini 2.5 Flash Native Audio | Live voice mate — bidirectional audio + video stream | No coach. Entire real-time loop dies. |
| Gemini 2.5 Flash | Delivery detection, challenge evaluation, chip guidance | Can't detect when you bowl or evaluate targets. |
| Gemini 3 Pro | 5-phase biomechanical analysis, DNA extraction, quality rating, pace estimation | No expert analysis, no DNA matching. |

Every user-facing feature flows through Gemini. Remove any model and the app is non-functional.

## Prerequisites

- **macOS** with Xcode 15+ installed
- **Physical iPhone** running iOS 17+ (camera + mic required; simulator won't work for Live API)
- **Gemini API key** from [Google AI Studio](https://aistudio.google.com/apikey)

## Setup & Testing

### 1. Clone the repo

```bash
git clone https://github.com/kanarupandev/wellbowled.ai.git
cd wellbowled.ai
```

### 2. Open in Xcode

The iOS source code lives in `ios/wellBowled/`. To build:

```bash
# Copy source into the Xcode project workspace
cp -R ios/wellBowled/ <your-xcode-project>/wellBowled/

# Open the Xcode workspace and build for your physical device
```

Alternatively, use the included deploy script (update device UDID and paths first):

```bash
chmod +x deploy.sh
./deploy.sh
```

### 3. Enter your API key

On first launch, the app prompts for your Gemini API key. Enter it in the Settings screen. The key is stored locally in UserDefaults — it is never sent anywhere except to `generativelanguage.googleapis.com`.

You can get a free API key at [aistudio.google.com/apikey](https://aistudio.google.com/apikey).

### 4. Run a session

1. **Tap "Live Session"** — camera opens, Gemini Live connects
2. **The mate greets you** — it sees your video and hears your voice
3. **Bowl a delivery** — detected automatically from video, count flashes on screen
4. **Mate gives feedback** — one specific biomechanical cue per ball
5. **Challenge mode activates** — mate sets targets, evaluates hit/miss
6. **End session** — review agent takes over, walk through deliveries by voice

### 5. Run tests

Tests are in `ios/wellBowled/Tests/`. To run in Xcode:

```bash
cd <your-xcode-project>
xcodebuild -workspace wellBowled.xcworkspace \
  -scheme wellBowled \
  -destination "platform=iOS Simulator,name=iPhone 16 Pro" \
  test
```

Key test suites:
- `BowlingDNATests` — DNA matching, quality dampener, vector encoding
- `SessionTests` — session lifecycle, challenge scoring
- `RobustnessTests` — edge cases, error handling, codable round-trips
- `SpeedEstimationServiceTests` — pace estimation and error margins
- `SessionLifecycleIntegrationTests` — full session flow

## Project Structure

```
ios/wellBowled/
├── SessionViewModel.swift        — Session brain: detection, analysis, mate lifecycle
├── GeminiLiveService.swift       — WebSocket connection to Gemini Live API
├── GeminiAnalysisService.swift   — REST calls to Gemini for analysis + detection
├── AudioSessionManager.swift     — Mic capture + playback engine
├── CameraService.swift           — AVFoundation capture + recording
├── BowlingDNA.swift              — 25-dimension action signature model
├── BowlingDNAMatcher.swift       — Weighted euclidean + quality dampener
├── FamousBowlerDatabase.swift    — 103 famous bowler profiles
├── ChallengeEngine.swift         — Target rotation + evaluation formatting
├── LiveSessionView.swift         — Full-screen live session UI
├── WBConfig.swift                — All configuration: models, endpoints, thresholds
└── Tests/                        — Unit + integration tests
```

## Built With

- Swift / SwiftUI
- AVFoundation
- Gemini Live API (WebSocket, bidirectional audio + video)
- Gemini 2.5 Flash (delivery detection, challenge evaluation)
- Gemini 3 Pro (deep biomechanical analysis, DNA extraction)
- MediaPipe (pose landmark extraction)
- WebSockets

## Known Limitations

- Speed estimation is video-based (frame differencing), not radar — shown as pace brackets with error margins
- MediaPipe pose overlay not yet rendering on device (linker issue in progress)
- Requires both sets of stumps visible for speed tracking
- DNA matching quality depends on Gemini's visual assessment accuracy

## What's Next

- On-device pose overlay with real-time skeleton visualization
- Session history and progress tracking across sessions
- Multi-bowler support
- Wearable integration for biomechanical sensor data
