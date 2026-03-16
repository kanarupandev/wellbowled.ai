# wellBowled.ai — System Architecture

> Google Gemini API Developer Competition 2025

## High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                        wellBowled.ai iOS App                        │
│                     Swift · SwiftUI · iOS 17+                       │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  ┌──────────────┐   ┌──────────────┐   ┌──────────────────────┐    │
│  │  Live Mode   │   │ Upload Mode  │   │  History/Favorites   │    │
│  │  (Camera)    │   │ (Video Import│   │  (Browse & Replay)   │    │
│  └──────┬───────┘   └──────┬───────┘   └──────────────────────┘    │
│         │                  │                                        │
│         ▼                  ▼                                        │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │              SessionViewModel (Orchestrator)                 │   │
│  │  Coordinates camera, detection, live coaching, analysis,     │   │
│  │  clip extraction, speed estimation, DNA matching             │   │
│  └──────────┬──────────┬──────────┬──────────┬────────────┘    │   │
│             │          │          │          │                  │   │
│     ┌───────▼──┐ ┌─────▼────┐ ┌──▼───────┐ ┌▼───────────┐   │   │
│     │ Camera   │ │ Delivery │ │ Live     │ │ Post-      │   │   │
│     │ Service  │ │ Detector │ │ Coaching │ │ Session    │   │   │
│     │          │ │          │ │          │ │ Analysis   │   │   │
│     └────┬─────┘ └────┬─────┘ └────┬─────┘ └────┬───────┘   │   │
│          │            │            │            │             │   │
└──────────┼────────────┼────────────┼────────────┼─────────────┘   │
           │            │            │            │                  │
           ▼            ▼            ▼            ▼                  │
┌──────────────┐ ┌───────────┐ ┌──────────┐ ┌────────────────┐     │
│   Hardware   │ │ On-Device │ │  Gemini  │ │    Gemini      │     │
│   Camera     │ │ MediaPipe │ │ Live API │ │ generateContent│     │
│   + Mic      │ │ Pose      │ │ (Audio)  │ │ (Video)        │     │
└──────────────┘ └───────────┘ └──────────┘ └────────────────┘     │
                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

## Detailed Component Architecture

```
┌─────────────────────────────────── REAL-TIME LAYER ─────────────────────────────────────┐
│                                                                                          │
│   Camera (30fps)                                                                         │
│       │                                                                                  │
│       ├──▶ Video Frames ──▶ MediaPipe PoseLandmarker (on-device, 33 joints)             │
│       │                         │                                                        │
│       │                         ▼                                                        │
│       │                    WristVelocityTracker                                          │
│       │                    (angular velocity over 5-frame window)                         │
│       │                         │                                                        │
│       │                         ▼                                                        │
│       │                    DeliveryDetector                                               │
│       │                    (spike > 450 rad/s → delivery detected)                       │
│       │                         │                                                        │
│       │                         ├──▶ TTS Announcement ("1. Medium pace")                │
│       │                         │    AVSpeechSynthesizer (on-device, zero latency)       │
│       │                         │                                                        │
│       │                         └──▶ Session.addDelivery(timestamp, paceBand, omega)     │
│       │                                                                                  │
│       ├──▶ Audio PCM ──────────────────────────┐                                        │
│       │                                         │                                        │
│       └──▶ .mov Recording ──▶ ClipExtractor     │                                        │
│                 (continuous file for post-use)   │                                        │
│                                                  │                                        │
└──────────────────────────────────────────────────┼────────────────────────────────────────┘
                                                   │
┌──────────────────────── GEMINI LIVE API (Voice Coaching) ────────────────────────────────┐
│                                                   │                                      │
│   ┌────────────┐    WebSocket (bidirectional)    │    ┌──────────────────────────┐       │
│   │ User Voice │◀══════════════════════════════▶│══▶│ gemini-2.5-flash-native  │       │
│   │ + Camera   │    wss://generativelanguage    │    │ -audio-preview           │       │
│   │   Frames   │    .googleapis.com              │    │                          │       │
│   └────────────┘                                 │    │ Persona: 8 mates         │       │
│                                                  │    │ (Aussie/Eng/Tamil/       │       │
│   Outbound:                                      │    │  Tanglish × M/F)         │       │
│   • PCM audio (user speech)                      │    │                          │       │
│   • Camera snapshots (2fps, 512px JPEG)          │    │ Tools:                   │       │
│   • Delivery events (count, pace, speed)         │    │ • end_session            │       │
│                                                  │    │ • navigate_delivery      │       │
│   Inbound:                                       │    │ • playback_control       │       │
│   • Audio stream (mate's voice)                  │    │ • set_session_duration   │       │
│   • Text transcript                              │    │ • set_challenge_target   │       │
│   • Tool calls (structured actions)              │    └──────────────────────────┘       │
│                                                                                          │
└──────────────────────────────────────────────────────────────────────────────────────────┘

┌──────────────────── GEMINI generateContent (Post-Session Analysis) ──────────────────────┐
│                                                                                           │
│   5-second delivery clip (.mp4)                                                           │
│       │                                                                                   │
│       ├──▶ Standard Analysis (gemini-3-flash-preview)                                    │
│       │    → pace, length, line, type, observation, confidence                            │
│       │                                                                                   │
│       ├──▶ Deep Analysis (gemini-3-pro-preview)                                          │
│       │    → 5 phase assessments (GOOD / NEEDS WORK)                                     │
│       │    → per-phase observation + drill tip                                            │
│       │    → expert joint feedback (good / slow / injury_risk)                            │
│       │    → 20-dimension BowlingDNA signature                                            │
│       │    → 5 execution quality ratings (0.1–1.0)                                       │
│       │                                                                                   │
│       ├──▶ Challenge Evaluation (gemini-3-flash-preview)                                 │
│       │    → target match (true/false), detected length/line                              │
│       │                                                                                   │
│       └──▶ Stump Detection (single frame, gemini-3-pro-preview)                          │
│            → bowler_end + striker_end normalized centres                                   │
│            → enables speed estimation calibration                                         │
│                                                                                           │
└───────────────────────────────────────────────────────────────────────────────────────────┘

┌───────────────────────── ON-DEVICE ML & COMPUTATION ─────────────────────────────────────┐
│                                                                                           │
│   ┌─────────────────────┐    ┌──────────────────────┐    ┌─────────────────────────┐    │
│   │ MediaPipe Pose      │    │ Speed Estimation     │    │ Bowling DNA Matcher     │    │
│   │ Landmarker          │    │                      │    │                         │    │
│   │                     │    │ Calibration:         │    │ 20D weighted Euclidean  │    │
│   │ • 33-point skeleton │    │  Gemini stump detect │    │ vs 103 famous bowlers   │    │
│   │ • Real-time (30fps) │    │  → bowler/striker ROI│    │                         │    │
│   │ • Dual confidence   │    │                      │    │ Quality dampener:       │    │
│   │   profiles (primary │    │ Estimation:          │    │ adjusted = base ×       │    │
│   │   + high-recall)    │    │  Frame differencing  │    │   min(1, userQ/bowlerQ) │    │
│   │ • Skeleton overlay  │    │  in calibrated ROIs  │    │                         │    │
│   │   video generation  │    │  Transit time → kph  │    │ Output: ~N kph          │    │
│   │                     │    │  ±error margin       │    │ (tilde = estimate)      │    │
│   └─────────────────────┘    └──────────────────────┘    └─────────────────────────┘    │
│                                                                                           │
└───────────────────────────────────────────────────────────────────────────────────────────┘
```

## Data Flow: Complete Bowling Session

```
                    ┌─────────────────────────────────┐
                    │         USER STARTS SESSION      │
                    └───────────────┬─────────────────┘
                                    │
                    ┌───────────────▼─────────────────┐
                    │   Gemini Live API connects       │
                    │   Mate greets bowler by name      │
                    │   Camera starts (30fps capture)   │
                    │   Calibration overlay appears     │
                    └───────────────┬─────────────────┘
                                    │
              ┌─────────────────────▼─────────────────────┐
              │          STUMP CALIBRATION (once)          │
              │                                            │
              │   Guide boxes (40%×35%) shown on screen    │
              │   User aligns stumps in portrait view      │
              │           │                                │
              │           ▼                                │
              │   Gemini vision detects stump positions    │
              │   (or user taps manually as fallback)      │
              │           │                                │
              │           ▼                                │
              │   Corridor overlay: bowler ──▶ striker     │
              │   Speed estimation calibrated              │
              └─────────────────────┬─────────────────────┘
                                    │
           ┌────────────────────────▼────────────────────────┐
           │            BOWLING LOOP (per delivery)          │
           │                                                  │
           │   Camera Frame                                   │
           │       │                                          │
           │       ├──▶ MediaPipe → Wrist Velocity Tracker   │
           │       │       │                                  │
           │       │       ▼                                  │
           │       │    SPIKE DETECTED (>450 rad/s)          │
           │       │       │                                  │
           │       │       ├──▶ Delivery #N added to session │
           │       │       ├──▶ TTS: "3. Quick." (on-device) │
           │       │       ├──▶ Flash indicator on screen     │
           │       │       └──▶ Gemini Live notified          │
           │       │              │                           │
           │       │              ▼                           │
           │       │         Mate responds (voice)            │
           │       │         "Good pace! Try aiming           │
           │       │          at off stump next."             │
           │       │                                          │
           │       └──▶ Audio/Video → Gemini Live (context)  │
           │                                                  │
           └────────────────────────┬────────────────────────┘
                                    │ (session ends: timeout / voice / tap)
                                    │
           ┌────────────────────────▼────────────────────────┐
           │         POST-SESSION ANALYSIS PIPELINE          │
           │                                                  │
           │   For each delivery (parallel async):           │
           │                                                  │
           │   ┌──────────┐  ┌──────────┐  ┌─────────────┐  │
           │   │ Clip     │  │ Gemini   │  │ MediaPipe   │  │
           │   │ Extract  │  │ Deep     │  │ Pose        │  │
           │   │ (5s mp4) │  │ Analysis │  │ Extraction  │  │
           │   └────┬─────┘  └────┬─────┘  └──────┬──────┘  │
           │        │             │                │          │
           │        │        ┌────▼─────┐    ┌────▼──────┐   │
           │        │        │ 5 Phase  │    │ Skeleton  │   │
           │        │        │ Feedback │    │ Overlay   │   │
           │        │        │ + DNA    │    │ Video     │   │
           │        │        │ + Quality│    └───────────┘   │
           │        │        └────┬─────┘                    │
           │        │             │                          │
           │   ┌────▼─────┐ ┌────▼──────────┐               │
           │   │ Speed    │ │ DNA Matcher   │               │
           │   │ Estimate │ │ (103 bowlers) │               │
           │   │ (~kph)   │ │ + Quality     │               │
           │   │          │ │   Dampener    │               │
           │   └──────────┘ └───────────────┘               │
           │                                                  │
           └────────────────────────┬────────────────────────┘
                                    │
           ┌────────────────────────▼────────────────────────┐
           │              RESULTS & REVIEW                    │
           │                                                  │
           │   Delivery carousel (swipe through)             │
           │       │                                          │
           │       ├──▶ Phase-by-phase feedback              │
           │       ├──▶ ~120 kph speed badge                 │
           │       ├──▶ "Your action matches Dale Steyn 67%" │
           │       ├──▶ Skeleton overlay replay               │
           │       ├──▶ Interactive chips (focus/slowmo)     │
           │       └──▶ Chat-driven video coaching           │
           │                                                  │
           └─────────────────────────────────────────────────┘
```

## Gemini API Usage Map

```
┌─────────────────────────────────────────────────────────────────┐
│                    GEMINI API TOUCHPOINTS                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│   1. LIVE COACHING (Gemini Live API — WebSocket)                │
│      Model: gemini-2.5-flash-native-audio-preview               │
│      Input: PCM audio + camera snapshots (2fps)                 │
│      Output: Voice responses + tool calls                        │
│      Duration: Entire session (5-30 min)                         │
│      Cost driver: Audio streaming minutes                        │
│                                                                  │
│   2. DEEP ANALYSIS (generateContent — REST)                     │
│      Model: gemini-3-pro-preview                                │
│      Input: 5s video clip (base64 MP4)                          │
│      Output: Phase analysis + DNA + quality ratings             │
│      Calls: 1 per delivery (post-session)                       │
│                                                                  │
│   3. STANDARD ANALYSIS (generateContent — REST)                 │
│      Model: gemini-3-flash-preview                              │
│      Input: 5s video clip (base64 MP4)                          │
│      Output: Pace, length, line, type, observation              │
│      Calls: 1 per delivery (quick pass)                         │
│                                                                  │
│   4. CHALLENGE EVALUATION (generateContent — REST)              │
│      Model: gemini-3-flash-preview                              │
│      Input: 5s clip + target description                        │
│      Output: Match/no-match + explanation                        │
│      Calls: 1 per challenge delivery                             │
│                                                                  │
│   5. STUMP DETECTION (generateContent — REST)                   │
│      Model: gemini-3-pro-preview                                │
│      Input: Single JPEG frame                                    │
│      Output: Bowler/striker stump centres (normalized)           │
│      Calls: 1 per session (calibration)                          │
│                                                                  │
│   6. DELIVERY DETECTION (generateContent — REST)                │
│      Model: gemini-3-flash-preview                              │
│      Input: Video segment (30-60s chunks)                       │
│      Output: Release timestamps + confidence                     │
│      Calls: Used in upload/import mode (segment scanning)        │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## Technology Stack

```
┌──────────────────────────────────────────────────────────┐
│                     TECHNOLOGY STACK                      │
├──────────────────────────────────────────────────────────┤
│                                                           │
│   CLIENT                                                  │
│   ├── Swift 5 / SwiftUI                                  │
│   ├── iOS 17+ (iPhone)                                   │
│   ├── AVFoundation (camera, recording, clip extraction)  │
│   ├── MediaPipe Tasks Vision (33-point pose detection)   │
│   ├── AVSpeechSynthesizer (on-device TTS)               │
│   └── URLSession + WebSocket (Gemini API transport)      │
│                                                           │
│   AI / ML                                                 │
│   ├── Gemini 2.5 Flash Native Audio (live coaching)      │
│   ├── Gemini 3 Pro Preview (deep analysis, stump detect) │
│   ├── Gemini 3 Flash Preview (quick analysis, challenges)│
│   ├── MediaPipe PoseLandmarker (on-device, real-time)    │
│   └── Frame Differencing (on-device speed estimation)    │
│                                                           │
│   CLOUD                                                   │
│   ├── Google Cloud Run (backend API)                     │
│   ├── Google Cloud Storage (clip storage)                │
│   └── Gemini API (generativelanguage.googleapis.com)     │
│                                                           │
│   DATA                                                    │
│   ├── 103 famous bowler DNA profiles                     │
│   ├── 20-dimension BowlingDNA signature                  │
│   ├── 5 execution quality factors per phase              │
│   └── Local persistence (UserDefaults + file system)     │
│                                                           │
└──────────────────────────────────────────────────────────┘
```
