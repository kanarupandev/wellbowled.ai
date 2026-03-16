# wellBowled — Devpost Submission

## Project Title
wellBowled — AI Bowling Coach Powered by Gemini Live

## Summary (~200 words)

Solo cricket bowlers at the nets have no expert watching. No real-time feedback, no challenge pressure, no biomechanical analysis — just repetition without direction.

wellBowled puts an elite bowling coach in your earbuds using Gemini Live API. The mate watches your live video feed, hears you through the mic, and coaches in real time — like a knowledgeable friend standing behind the arm.

**How Gemini powers every feature:**
- **Gemini 2.5 Flash (Native Audio)** — Live API voice mate: sees your video stream, hears your voice, gives spoken biomechanical feedback. Drives the session via tool calls (timer, challenges, session end).
- **Gemini 2.5 Flash** — Delivery detection from 30-second rolling segments. Challenge evaluation (hit/miss). Phase-focused guidance.
- **Gemini 3 Pro** — Expert deep analysis of 5-second clips: 5-phase biomechanical breakdown, pace estimation, execution quality rating, bowling DNA extraction, and famous bowler matching against 100 international players.

The mate proactively sets challenge targets, evaluates each delivery, tracks scores, and rotates challenges. Post-session, a dedicated review agent walks through each delivery with voice-controlled video playback. Gemini isn't a feature — it IS the product.

---

## How Gemini Is Central

| Gemini Model | Role | Without It |
|---|---|---|
| Gemini 2.5 Flash Native Audio | Live voice mate — bidirectional audio + video stream, tool calls | No coach. The entire real-time loop dies. |
| Gemini 2.5 Flash | Delivery detection from video segments, challenge evaluation, chip guidance | Can't detect when you bowl or evaluate targets. |
| Gemini 3 Pro | 5-phase biomechanical analysis, execution quality, DNA extraction, pace estimation | No expert analysis, no DNA matching, no post-session insights. |

Every user-facing feature flows through Gemini. Remove any model and the app is non-functional.

**Gemini-powered tool calls (agentic behavior):**
- `set_session_duration` — mate controls the timer
- `set_challenge_target` — mate drives challenge loop
- `end_session` — mate wraps up
- `navigate_delivery` — review agent navigates deliveries
- `control_playback` — review agent controls video (play, pause, slow-mo, seek)

---

## Known Limitations and Next Steps

**Limitations:**
- Speed estimation is video-based (frame differencing), not radar — shown as pace brackets with error margins
- MediaPipe pose overlay not yet rendering on device (linker issue)
- Requires both sets of stumps visible for speed tracking
- DNA matching quality depends on Gemini's visual assessment accuracy

**Next steps:**
- On-device pose overlay with real-time skeleton visualization
- Session history and progress tracking across sessions
- Multi-bowler support (coach multiple players in one session)
- Wearable integration for biomechanical sensor data

---

## Technical Architecture

```
┌─────────────────────────────────────┐
│         iPhone (Native iOS)         │
│                                     │
│  Camera ──→ Video frames ──────────────→ Gemini Live API (2.5 Flash Native Audio)
│  Mic ────→ Audio stream ───────────────→   ↕ Bidirectional voice + video
│  Speaker ←── Audio playback ───────────←   ↕ Tool calls (timer, challenges, playback)
│                                     │
│  30s segments ─→ Gemini 2.5 Flash ──→ Delivery timestamps + confidence
│  5s clips ─────→ Gemini 3 Pro ──────→ Deep analysis + DNA + quality
│  5s clips ─────→ Gemini 2.5 Flash ──→ Challenge evaluation (hit/miss)
│                                     │
│  On-device: AVFoundation recording, │
│  clip extraction, stump calibration,│
│  delivery deduplication, TTS        │
└─────────────────────────────────────┘
```
