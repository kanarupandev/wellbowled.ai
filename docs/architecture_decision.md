# Architecture: Hybrid Live + Post-Session (Option B)

> Full detailed version: see commit 294162e

## Verdict

Delivery detection on uploaded clips **works** (6/7 PASS at mixed thresholds: 0.2s broadcast / 0.3s nets, 0.04-0.22s precision, ~$0.001/call). Real-time live detection is untested but feasible at lower precision (~1s). Hybrid approach: live for triggers, async for precision.

## Pipeline

```
LIVE                                POST-SESSION
────                                ────────────
Phone records (60/240fps)
Live API (native-audio)              Mark timestamp (±1s)
  ──► SPEAKS to bowler:              Clip 5s window [-3s, +2s]
  "Delivery! That's 6 today,        generateContent per clip
   medium pace"                      → analysis card
MediaPipe on-device (complement)
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

## Live API Status (R11)

**Audio is the way forward (hypothesis — not yet validated).** Native-audio models (`gemini-2.5-flash-native-audio`) respond via audio — which is ideal for a bowler mid-session who can't look at their phone. The model watches the video stream and speaks feedback aloud: delivery count, pace band, observations.

What's tested: `generateContent` polling detected 2/4 deliveries + 1 phantom (Feb 2026). What's NOT tested yet: end-to-end native-audio Live API streaming video → receiving spoken delivery feedback. This is the next experiment.

MediaPipe wrist velocity spike remains useful as an on-device complement: instant, free, works offline. Proven: peak velocity clearly marks release in all 4 test clips.

## Speed Status (R12)

Gemini Pro: 96-99 kph, ±3 kph cross-delivery, type classification reliable. YOLO not viable at 30fps. Show ranges not precise numbers.

## Fallback (Option C)

If Live API unreliable: skip live, upload full video → detect all deliveries → clip → analyze. Strava for bowling.
