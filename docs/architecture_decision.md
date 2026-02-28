# Architecture: Hybrid Live + Post-Session (Option B)

> Full detailed version: see commit 294162e

## Verdict

Delivery detection on uploaded clips **works** (6/7 PASS at mixed thresholds: 0.2s broadcast / 0.3s nets, 0.04-0.22s precision, ~$0.001/call). Real-time live detection is untested but feasible at lower precision (~1s). Hybrid approach: live for triggers, async for precision.

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

**Works**: Single delivery detection, nets sessions (4/4), replay filtering, ~$1/day at 1K calls
**Doesn't**: Broadcast montage (3/7), real-time overlay (9-12s latency), legality (2D can't measure 15°)

## Speed estimation

- **Live API**: No (1fps, ball gone between frames)
- **Gemini on 5s clip**: ±15-25 kph classification ("fast", "medium", "spin") — hackathon scope
- **240fps ball tracking**: iPhone 15 shoots 240fps natively. Extract 2s post-delivery from original recording → 480 frames → ball tracking → ±5-10 kph. Needs camera calibration. Post-MVP.

## Key technical choices

Config E: temp=0.1, default thinking, simple prompt, File API >5MB, no downscaling, no response schema. Clip: 5s (-3s, +2s).

## Hackathon scope

**Do**: Record → live detection with count → auto-clip → post-session analysis cards
**Don't**: Real-time overlay, precise speed, legality, broadcast video

## Live API Status (R11 + R17)

**Validated: Live API is conversational, not monitoring.** Native-audio model connects, understands cricket context ("Right, I'm watching. Let's see what the bowlers have got."), but does NOT proactively call out deliveries from video frames. It waits for user speech (VAD turn-taking).

**Revised architecture**:
- **Detection + count**: MediaPipe on-device (wrist velocity spike) — instant, proven 4/4
- **Count announcement**: iOS TTS (AVSpeechSynthesizer) — count only, zero latency, local. Pace band requires post-clip Gemini analysis
- **Conversation**: Live API — bowler asks "How was that?", mate answers with audio based on video context
- **Post-session analysis**: generateContent (Gemini Pro) on auto-clipped deliveries

This is actually better: the core loop (detect → announce) has zero API dependency. The Live API does what it's best at — voice conversation with video understanding.

## Speed Status (R12) — Exploratory, Uncalibrated

Gemini Pro: 96-99 kph avg (4 clips, same bowler, no radar ground truth). Per-run ±10 kph, cross-delivery ±3 kph. Type classification (medium/slow/quick) is reliable. YOLO not viable at 30fps. Show pace bands, not kph numbers.

## Fallback (Option C)

If Live API unreliable: skip live, upload full video → detect all deliveries → clip → analyze. Strava for bowling.
