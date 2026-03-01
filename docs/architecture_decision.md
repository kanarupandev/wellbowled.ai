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
- `[HYPOTHESIS]` **Post-session analysis**: generateContent (Gemini Pro) on auto-clipped deliveries — code written, untested end-to-end on device

This is actually better: the core loop (detect → announce) has zero API dependency. The Live API does what it's best at — voice conversation with video understanding.

## Speed Status (R12) — Exploratory, Uncalibrated

Gemini Pro: 96-99 kph avg (4 clips, same bowler, **no radar ground truth**). Per-run ±10 kph spread, cross-delivery ±3 kph spread — but **uncalibrated** (no radar reference). Type classification (medium/slow/quick) is feasible but unvalidated. YOLO not viable at 30fps. Show pace bands, not kph numbers. Treat all speed numbers as rough classification only until radar ground truth is available.

## Session Resumption (R18)

**Current**: Reconnect starts a fresh session — mate forgets everything.
**Fix**: Send `sessionResumption.handle` in setup message on reconnect. Server already sends `sessionResumptionUpdate.newHandle` (code captures it). Handle valid for **2 hours**. Restores full conversation context.

**Latency**: Marketed sub-800ms. Real-world: 1-3s typical, 5-7s spikes on longer sessions. Acceptable for "ask and hear" UX — bowler picks up next ball during response.

## What's Done (R19 — March 2026)

- `[DONE]` Live API WebSocket connects, mate hears and speaks on device
- `[DONE]` Auto-reconnect with 1.5s backoff on TCP abort
- `[DONE]` Screen idle timer disabled during sessions
- `[DONE]` Mate persona system: 4 styles (Aussie, English, Tamil, Tanglish) × 2 genders = 8 options
- `[DONE]` Persona persisted via UserDefaults, voice + system instruction switch dynamically
- `[DONE]` Session struct (value type) — fixes @Observable/@Published mismatch
- `[DONE]` CIContext cached (was creating per frame at 30fps)
- `[DONE]` Timestamp offset for clip extraction (recording-relative, not CMTime-absolute)
- `[DONE]` sendJSON serialized via sendQueue (data race fix)
- `[DONE]` openContinuation thread safety (NSLock against concurrent delegate callbacks)
- `[DONE]` AudioSessionManager detach safety
- `[DONE]` Timeout error message corrected (15s, not 10s)
- `[DONE]` Navigation: fullScreenCover for sessions (fixes dismiss issues)
- `[DONE]` Brand: peacock blue #006D77 + grey blue #8DA9C4 + programmatic app icon
- `[DONE]` Unit tests: Session, WBConfig, WristVelocityTracker, Enums, Delivery codable
- `[DONE]` Integration tests: session lifecycle, wire protocol encode/decode, timestamp offset

## Road Map

> **Convention**: Claude Code commits with default prefix. Codex commits with `codex:` prefix.

### Tier 1: Complete MVP (end-to-end loop) — IN PROGRESS
1. `[DONE]` ~~Session resumption~~ — handle captured but NOT sent on reconnect yet. **Next: wire handle into setup message**
2. **Validate delivery detection on device** — MediaPipe wrist spike → TTS count. Code wired, never confirmed live on device. Needs: MediaPipe model bundled in app (`pose_landmarker_heavy.task`), camera frame → processFrame wiring confirmed
3. **Validate post-session analysis** — end session → clips → Gemini Pro → delivery cards in SessionResultsView. Code written, untested end-to-end
4. **Fix bugs from 2-3** — likely: MediaPipe model bundling path, clip timing edge cases, analysis prompt tuning

### Tier 2: Demo-worthy polish
5. `[DONE]` ~~Mate persona tuning~~ — 4 language styles × 2 genders, dynamic system instructions
6. **Pace band on delivery cards** — Gemini Pro classifies "medium pace" / "fast" from clips
7. **Session summary** — generateSessionSummary() after all deliveries analyzed, display in SessionResultsView
8. **Session resumption handle** — send `sessionResumption.handle` in setup message on reconnect to preserve context

### Tier 3: Challenge Mode (differentiator)
9. **Mate speaks target** — "Try a yorker on off stump" (Q10)
10. **Evaluate delivery against target** — clip → Gemini → success/fail
11. **Track challenge score** — "2 out of 3 so far"
12. Needs end-to-end experiment first (Q10)

### Tier 4: Post-hackathon (parked)
- Ball tracking (YOLO fine-tuned on cricket ball, 240fps)
- Zone-based pitch maps from accumulated classifications
- Biomechanical deep analysis (6-phase Expert prompt)
- Legality observation flags
- Precise speed estimation

## Fallback (Option C)

If Live API unreliable: skip live, upload full video → detect all deliveries → clip → analyze. Strava for bowling.
