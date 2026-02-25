# Architecture: Hybrid Live + Post-Session (Option B)

## Verdict

Delivery detection on uploaded clips **works** (6/7 PASS, 0.04-0.22s precision, ~$0.001/call). Real-time live detection is untested but feasible at lower precision (~1s). Hybrid approach: live for triggers, async for precision.

## Pipeline

```
LIVE                                POST-SESSION
────                                ────────────
Phone records (60fps)
Live API (~1fps) ─── "delivery!" ──► Mark timestamp (±1s)
Show count to bowler                 Clip 5s window [-3s, +2s]
Session ends                         generateContent per clip → analysis card
```

**Why ±1s is fine**: 5-second clip window guarantees release point is captured. Precise timestamp refined by generateContent (proven 0.04-0.22s).

## What works / doesn't

**Works**: Single delivery detection, nets sessions (4/4), replay filtering, ~$1/day at 1K calls
**Doesn't**: Broadcast montage (3/7), real-time overlay (9-12s latency), legality (2D can't measure 15°)
**Speed**: Live API no (1fps). From 5s clip: Gemini gives ±15-25 kph classification ("fast", "medium", "spin"). Precise speed needs 120+ fps ball tracking (post-MVP).

## Key Technical Choices

- **Config E**: temp=0.1, default thinking, simple prompt, File API >5MB, no downscaling, no response schema
- **Clip**: 5 seconds (-3s before detection, +2s after)
- **Model**: gemini-3-flash-preview (both live and analysis)

## Hackathon Scope

**Do**: Record session → live detection with count → auto-clip → post-session analysis cards
**Don't**: Real-time overlay, precise speed, legality assessment, broadcast video

## Fallback (Option C)

If Live API unreliable: skip live, upload full video → detect all deliveries → clip → analyze. Strava for bowling. Still viable.
