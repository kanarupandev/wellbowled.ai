# wellBowled — Session Onboarding

## What is this?

An **expert mate** for cricket bowlers. Not a coach — a knowledgeable buddy who watches you bowl, gives you real-time voice feedback, and walks you through a deep biomechanical analysis when you're done.

Built for the **Gemini Live Hackathon 2026**.

## The Use Case: "Bowl. Hear Your Mate."

You're at nets or in the backyard. You set your phone on a tripod. You press Start. You bowl.

### Flow 1: LIVE — Expert Mate (during session)

```
You bowl
    ↓
Gemini Flash detects delivery (30s video segments, queued analysis)
    ↓
iOS TTS speaks: "Three."  ← count, zero latency, on-device
    ↓
Deep analysis runs in background (phases, DNA, speed)
    ↓
Mate speaks feedback: "Front arm's pulling across — that's why you're falling away."
    ↓
You ask: "What do you mean?"
    ↓
Mate rephrases: "When you land, your front arm flings out instead of
pulling down to your hip. Your head follows it off-line."
    ↓
You pick up next ball, keep bowling
```

No screen. No buttons. No stopping. The mate watches, forms opinions across deliveries, picks ONE thing per ball, and handles follow-up questions like a real expert.

### Flow 2: CHALLENGE LOOP

```
Mate speaks: "Try a yorker on off stump."
    ↓
You bowl
    ↓
Mate evaluates: "That was full, but drifting leg side.
                  Close though — 2 out of 3 so far."
    ↓
Mate speaks: "Now try a good length, 4th stump."
```

Challenges target specific biomechanical fixes, not just "hit a spot". Mate can also set action-focused drills: "Next 3 balls, pull your front arm down to your hip."

### Flow 3: POST-SESSION — Review Agent (after session)

```
Session ends
    ↓
Review agent connects (same voice, fresh context with all analysis data)
    ↓
Agent looks at the results screen with the bowler
    ↓
All analysis complete → agent walks through highlights:
  - Phase breakdown per delivery (GOOD / NEEDS WORK + drills)
  - BowlingDNA match (e.g. "82% Starc — high arm, steep bounce")
  - Speed trends, recurring issues, best delivery
    ↓
Agent uses playback tools: slow-mo the release, seek to a phase timestamp
    ↓
Bowler asks questions: "Who do I bowl most like?" / "What drill should I do?"
    ↓
Agent answers from data + own expertise
```

### Flow 4: IMPORTED RECORDING — Analyze any bowling video

```
Home screen → "Analyze Recording" → pick video from Photos
    ↓
Same Gemini Flash segment detection → find deliveries → extract clips
    ↓
Review agent connects with full analysis
    ↓
Identical walkthrough experience as live session
```

## Detection Pipeline

**Gemini Flash is the sole delivery detector** (MediaPipe removed from detection path).

| Stage | Method | When |
|-------|--------|------|
| Live detection | Gemini Flash segment scan (30s segments, 5s overlap, confidence ≥ 0.9) | During live session (Queue A) |
| Live deep analysis | Gemini 3 Pro (phases, DNA, speed) | During live session (Queue B, concurrent) |
| Post-session batch | Gemini Flash segment scan (60s segments, 5s overlap; fallback: 20s, 8s overlap) | After session or for imported recordings |
| Clip extraction | AVAssetExportSession (5s window: 3s pre-roll + 2s post-roll) | Parallel, per delivery |

## What It Analyzes

| Attribute | Method | Status |
|-----------|--------|--------|
| Delivery detection | Gemini Flash segment detection | Validated |
| 5-phase biomechanical breakdown | Gemini 3 Pro deep analysis (run-up, gather, delivery stride, release, follow-through) | Done |
| BowlingDNA action signature | Gemini vision (16 categorical fields) + 20-dimension model | Done — 103 famous bowler database |
| Pace Score + Rough Speed Bucket | Delivery mechanics + Gemini context | Canonical policy |
| Estimated Speed (optional) | Frame-differencing with stump calibration (120fps) | Code complete, unvalidated on device |
| Length / Line / Type | Gemini on clip | Done |
| Challenge evaluation | Gemini on clip vs target | Done in code |

## What It Doesn't Do

- Exact/radar-grade speed claims
- Legality assessment (2D video can't measure 15° elbow extension)
- Broadcast video analysis (scene cuts break detection)
- Real-time video overlay (latency prohibitive)
- Batting, fielding, or non-bowling analysis

## Stack

- **Delivery detection**: Gemini Flash (`gemini-2.5-flash`) segment scanning — sole detector for both live and imported recordings
- **Count announcement**: iOS TTS (AVSpeechSynthesizer) — on-device, zero latency
- **Voice conversation**: Gemini Live API (`gemini-2.5-flash-native-audio`) — bidirectional audio, 8 personas (4 languages × 2 genders)
- **Deep analysis**: Gemini 3 Pro (`gemini-3-pro-preview`) — 5-phase breakdown, expert biomechanical annotations
- **BowlingDNA**: Gemini vision extraction + weighted Euclidean matcher against 103 bowler profiles
- **Review agent**: Fresh Gemini Live API session with full analysis data, navigation + playback tools
- **iOS client**: Swift 5.9+ / iOS 17+ / SwiftUI + Combine
- **Config**: temp=0.1, JSON response format, 5s clip window

## Expert Mate Personality

The mate is an expert, not a template. Key behaviors:
- **Watches before speaking** — first ball is quiet, forms opinions by ball 2-3, commits to the biggest issue by ball 4+
- **ONE thing per ball** — never lists multiple points
- **Varies responses** — never says the same thing twice in the same words
- **Uses silence** — doesn't comment on every delivery; a bowler in rhythm doesn't need commentary
- **Handles cross-questions** — rephrases with analogies, explains biomechanical chains, compares to famous bowlers
- **Research-grade biomechanics** — references joint angles, kinetic chain sequencing, injury risk flags (mixed action → L4/L5 stress, trunk lateral flexion >50°)
- **Uses own knowledge** — swing physics, famous bowler actions, death bowling tactics, drill prescription
- **Stays on bowling** — gently steers back if user drifts to non-bowling topics

## Review Agent

Connects after session ends (or after imported recording analysis). Behaves like an expert looking at the results screen with the bowler:
- Waits for analysis to complete naturally
- Leads with what strikes them most (not delivery 1)
- Uses playback tools to SHOW moments (slow-mo, seek to phase timestamps)
- Explains DNA matches properly (who, why, where they diverge, signature traits)
- References drills from analysis data
- Connects dots across deliveries (recurring issues, speed trends, DNA shifts)
- Handles questions from own expertise + session data

## Competitive Landscape

| Tool | Approach | Our Differentiation |
|------|----------|-------------------|
| **FullTrack AI** | Ball tracking, pitch maps. 3M+ users. | They track pixels. We understand bowling semantically. They give data. We give an expert mate who talks to you. |
| **PitchVision** | 2 cameras + laptop + activation sensor. | Hardware kit. We're phone-only. |
| **CricVision** | Cloud-based ball tracking. | No live audio feedback. No biomechanical analysis. |
| **Catapult** | Wearable GPS/inertial sensors. IPL teams. | Different market (professional workload). |

## Repo Structure

```
wellbowled.ai/
├── ios/wellBowled/       # Source of truth (92 Swift files)
│   └── Tests/            # 21 test files
├── docs/                 # Architecture, prompts, process (52 files)
├── experiments/          # Archived research
├── research/             # Research index
└── codex/                # Codex agent research
```

## Previous Demo

Gemini 3 hackathon (Feb 2026): https://www.youtube.com/watch?v=Gpif-vPtYTc
