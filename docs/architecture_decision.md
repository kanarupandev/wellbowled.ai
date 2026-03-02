# Architecture: Hybrid Live + Post-Session (Option B)

> Full detailed version: see commit 294162e

## Verdict

`[VALIDATED]` Delivery detection on uploaded clips **works** (6/7 PASS at mixed thresholds: 0.2s broadcast / 0.3s nets, 0.04-0.22s precision, ~$0.001/call). `[HYPOTHESIS]` Real-time live detection is untested but feasible at lower precision (~1s). Hybrid approach: live for triggers, async for precision.

## Pipeline

```
LIVE (on-device)                    CONVERSATION              POST-SESSION
────────────────                    ────────────              ────────────
Phone records (60fps)               Bowler: "How was that?"   Clip 5s window
MediaPipe detects delivery            ↓                       generateContent
  → wrist velocity spike           Live API audio response:   → analysis card
iOS TTS: "3."                      "Good length, seam up,
  → count only, zero latency         bit wide of off"
```

**Why ±1s is fine**: 5-second clip window guarantees release point is captured. Precise timestamp refined by generateContent (proven 0.04-0.22s).

## What works / doesn't

`[VALIDATED]` **Works**: Single delivery detection, nets sessions (4/4), replay filtering, ~$1/day at 1K calls
`[VALIDATED]` **Doesn't**: Broadcast montage (3/7), real-time overlay (9-12s latency), legality (2D can't measure 15°)

## Speed estimation

- **Live API**: No (1fps, ball gone between frames)
- **Gemini on 5s clip**: ±15-25 kph classification ("fast", "medium", "spin") — hackathon scope
- **240fps ball tracking**: iPhone 15 shoots 240fps natively. Extract 2s post-delivery from original recording → 480 frames → ball tracking → ±5-10 kph. Needs camera calibration. Post-MVP.

## Key technical choices

Config E: temp=0.1, default thinking, simple prompt, File API >5MB, no downscaling, no response schema. Clip: 5s (-3s, +2s).

## Hackathon scope

**Do**: Record → live detection with count → auto-clip → post-session analysis cards
**Don't**: Real-time overlay, precise speed, legality, broadcast video

## Live API Status (R11 + R17 + R18)

`[VALIDATED]` **Live API is conversational, not monitoring.** Native-audio model connects, understands cricket context ("Right, I'm watching. Let's see what the bowlers have got."), but does NOT proactively call out deliveries from video frames. It waits for user speech (VAD turn-taking).

`[VALIDATED R18]` **End-to-end on device (March 2026).** Live API WebSocket connects, mate hears user speech and responds with audio on iPhone 15. Key fixes applied:
- Must NOT send video/audio frames before `setupComplete` — server aborts if data arrives pre-handshake
- iOS TCP stack aborts connection after ~20s of heavy streaming (ECONNABORTED) — auto-reconnect with 1.5s backoff handles this transparently
- Screen idle timer must be disabled during active sessions

**Revised architecture**:
- `[VALIDATED]` **Detection + count**: MediaPipe on-device (wrist velocity spike) — instant, proven 4/4
- `[VALIDATED]` **Count announcement**: iOS TTS (AVSpeechSynthesizer) — count only, zero latency, local. Pace band requires post-clip Gemini analysis
- `[VALIDATED R18]` **Conversation**: Live API — bowler asks "How was that?", mate answers with audio based on video context. Working on device with auto-reconnect.
- `[DONE R24]` **Waterfall startup flow**: proactive greet → plan prompt → 5s natural reprompt if no answer → setup verification → pilot run → explicit "Session started".
- `[DONE R24]` **Mode switch tool call path**: Live API can request `switch_session_mode` and app switches free/challenge dynamically with UI mode badge.
- `[DONE R24]` **Session duration config**: live timeout increased to 3 minutes via `WBConfig.liveSessionMaxDurationSeconds = 180`.
- `[HYPOTHESIS]` **Post-session analysis**: generateContent (Gemini Pro) on auto-clipped deliveries — code written, untested end-to-end on device

This is actually better: the core loop (detect → announce) has zero API dependency. The Live API does what it's best at — voice conversation with video understanding.

## Speed Status (R12) — Exploratory, Uncalibrated

Gemini Pro: 96-99 kph avg (4 clips, same bowler, **no radar ground truth**). Per-run ±10 kph spread, cross-delivery ±3 kph spread — but **uncalibrated** (no radar reference). Type classification (medium/slow/quick) is feasible but unvalidated. YOLO not viable at 30fps. Show pace bands, not kph numbers. Treat all speed numbers as rough classification only until radar ground truth is available.

## Session Resumption (R18)

**Current**: Reconnect starts a fresh session — mate forgets everything.
**Fix**: Send `sessionResumption.handle` in setup message on reconnect. Server already sends `sessionResumptionUpdate.newHandle` (code captures it). Handle valid for **2 hours**. Restores full conversation context.

**Latency**: Marketed sub-800ms. Real-world: 1-3s typical, 5-7s spikes on longer sessions. Acceptable for "ask and hear" UX — bowler picks up next ball during response.

## What's Done (R21 — March 2026)

- `[DONE]` Live API WebSocket connects, mate hears and speaks on device
- `[DONE]` Auto-reconnect with 1.5s backoff on TCP abort
- `[DONE]` **Session resumption handle sent on reconnect** — mate remembers context (2h validity)
- `[DONE]` Screen idle timer disabled during sessions
- `[DONE]` Mate persona system: 4 styles (Aussie, English, Tamil, Tanglish) × 2 genders = 8 options
- `[DONE]` Persona persisted via UserDefaults, voice + system instruction switch dynamically
- `[DONE]` Session struct (value type) — fixes @Observable/@Published mismatch
- `[DONE]` CIContext cached (was creating per frame at 30fps)
- `[DONE]` Timestamp offset for clip extraction (recording-relative, not CMTime-absolute)
- `[DONE]` sendJSON serialized via sendQueue (data race fix)
- `[DONE]` openContinuation thread safety (NSLock against concurrent delegate callbacks)
- `[DONE]` AudioSessionManager detach safety
- `[DONE]` **Parallel post-session analysis** — clip extraction + Gemini API calls run concurrently
- `[DONE]` **Session summary generation** after all deliveries analyzed
- `[DONE]` **Live delivery count flash overlay** — large centered count on detection, fades out
- `[DONE]` **Reconnecting banner with spinner** + error state UI improvements
- `[DONE]` **Session results view with summary** — dominant pace, key observation, challenge score
- `[DONE]` Service account keys removed from repo (security cleanup)
- `[DONE]` Navigation: fullScreenCover for sessions (fixes dismiss issues)
- `[DONE]` Brand: peacock blue #006D77 + grey blue #8DA9C4 + programmatic app icon
- `[DONE]` Unit tests: Session, WBConfig, WristVelocityTracker, Enums, Delivery codable
- `[DONE]` Integration tests: session lifecycle, wire protocol encode/decode, timestamp offset, resumption handle
- `[DONE R21]` **BowlingDNA Action Signature feature** — 20-dimension bowling action fingerprint
- `[DONE R21]` **BowlingDNA model** — 18 categorical + 2 continuous dimensions across 6 bowling phases
- `[DONE R21]` **Vector encoder + weighted matcher** — ordinal encoding, weighted Euclidean distance (release 2x)
- `[DONE R21]` **Famous bowler database** — 10 international bowlers spanning all styles (McGrath, Akram, Warne, Akhtar, Murali, Anderson, Starc, Ashwin, Marshall, Bumrah)
- `[DONE R21]` **Gemini DNA extraction** — vision prompt extracts 16 categorical fields from clip, merged with MediaPipe wristOmega + releaseWristY
- `[DONE R21]` **DNA results UI** — similarity ring, closest phase, biggest difference, signature traits in SessionResultsView
- `[DONE R21]` **wristOmega + releaseWristY** captured from MediaPipe at delivery detection, stored on Delivery
- `[DONE R21]` **pose_landmarker.task in iOS source of truth** — auto-syncs and auto-bundles
- `[DONE R21]` **BowlingDNA unit tests** — vector encoding, matching, partial DNA, normalization, codable round-trip

## Road Map

> **Convention**: Claude Code commits with default prefix. Codex commits with `codex:` prefix.

### Tier 1: Complete MVP (end-to-end loop) — DONE
1. `[DONE]` Session resumption handle — sent on reconnect, restores mate context
2. `[DONE]` Delivery detection pipeline — MediaPipe wrist spike → TTS count → Live API context
3. `[DONE]` Post-session analysis — parallel clip extraction + parallel Gemini Pro analysis → delivery cards
4. **Validate on device** — run full session, confirm detection fires, clips extract, analysis returns

### Tier 2: Demo-worthy polish — DONE
5. `[DONE]` Mate persona tuning — 4 language styles × 2 genders, dynamic system instructions
6. `[DONE]` Pace band classification — returned from Gemini Pro analysis, displayed in delivery cards
7. `[DONE]` Session summary — generated after analysis, displayed in SessionResultsView
8. `[DONE]` Session resumption handle — sent on reconnect via setup message

### Tier 3: BowlingDNA Action Signature — DONE
9. `[DONE]` BowlingDNA 20-dimension model (6 phases, 18 categorical + 2 continuous)
10. `[DONE]` Vector encoder + weighted Euclidean matcher (release fields 2x weight)
11. `[DONE]` Famous bowler database (10 international bowlers)
12. `[DONE]` Gemini DNA extraction prompt + MediaPipe wrist field merge
13. `[DONE]` DNA results UI in SessionResultsView (similarity ring, traits, closest phase)
14. `[DONE]` Unit tests for encoding, matching, normalization

### Tier 4: Challenge Mode (differentiator) — IN PROGRESS
15. `[DONE IN CODE]` Mate speaks target and rotates target per ball
16. `[DONE IN CODE]` Evaluate delivery against target (clip -> Gemini -> hit/miss)
17. `[DONE IN CODE]` Track challenge score in session summary
18. `[UNVERIFIED]` Accuracy of challenge evaluation on real-device sessions
19. `[UNVERIFIED]` End-to-end device validation under demo conditions

### Tier 5: Post-hackathon (parked)
- Ball tracking (YOLO fine-tuned on cricket ball, 240fps)
- Zone-based pitch maps from accumulated classifications
- Biomechanical deep analysis (6-phase Expert prompt)
- Legality observation flags
- Precise speed estimation
- BowlingDNA trend tracking across sessions (improvement over time)
- DNA sharing / comparison with friends

## Deployment Guide

### iOS App (iPhone 15)

```bash
# 1. Sync source → Xcode project
rm -rf /Users/kanarupan/workspace/xcodeProj/wellBowled/wellBowled/*.swift && \
cp -R /Users/kanarupan/workspace/wellbowled.ai/ios/wellBowled/ \
     /Users/kanarupan/workspace/xcodeProj/wellBowled/wellBowled/

# 2. Remove Tests dir from app target (XCTest can't import in app target)
rm -rf /Users/kanarupan/workspace/xcodeProj/wellBowled/wellBowled/Tests

# 3. Copy tests to test target
cp /Users/kanarupan/workspace/wellbowled.ai/ios/wellBowled/Tests/*.swift \
   /Users/kanarupan/workspace/xcodeProj/wellBowled/wellBowledTests/

# 4. Build + install to physical device
cd /Users/kanarupan/workspace/xcodeProj/wellBowled && \
xcodebuild -workspace wellBowled.xcworkspace \
  -scheme wellBowled \
  -destination "platform=iOS,id=00008120-001230560204A01E" \
  -configuration Debug clean build

# 5. Build for simulator (testing)
cd /Users/kanarupan/workspace/xcodeProj/wellBowled && \
xcodebuild -workspace wellBowled.xcworkspace \
  -scheme wellBowled \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" build
```

### Prerequisites
- Xcode 16+ with iOS 17 SDK
- CocoaPods installed (`pod install` in Xcode project dir)
- MediaPipeTasksVision pod (for pose detection)
- Gemini API key set in app Settings or Info.plist `GEMINI_API_KEY`

## Fallback (Option C)

If Live API unreliable: skip live, upload full video → detect all deliveries → clip → analyze. Strava for bowling.
