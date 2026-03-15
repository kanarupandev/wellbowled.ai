# wellBowled — Session Onboarding

## What is this?

An **expert mate** for cricket bowlers. Not a coach — a knowledgeable buddy who watches you bowl, calls out your count and pace, challenges you with targets, and gives you a session report when you're done.

Built for the **Gemini Live Hackathon 2026**.

## The Use Case: "Bowl. Hear Your Mate."

You're at nets or in the backyard. You set your phone on a tripod. You press Start. You bowl.

### Flow 1: LIVE — Audio Mate (during session)

```
You bowl
    ↓
MediaPipe detects delivery (wrist velocity spike, on-device, instant)
    ↓
iOS TTS speaks: "Three."  ← count only, zero latency, no network
    ↓
You ask: "How was that?"
    ↓
Live API hears you + sees video context
    ↓
Mate speaks: "Good length, nice seam position, bit wide of off."
    ↓
You pick up next ball, keep bowling
```

No screen. No buttons. No stopping. Detection + count is instant and local. Conversation is natural — ask when you want.

### Flow 2: CHALLENGE LOOP (implemented in code path)

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

Simulates match pressure with target evaluation and score tracking implemented in the analysis pipeline. Home currently starts sessions in Free mode; direct challenge-mode entry wiring is tracked in roadmap docs.

### Flow 3: POST-SESSION — Delivery Cards (after session)

```
Session ends
    ↓
App auto-clips each delivery (5s window)
    ↓
Gemini Pro analyzes each clip
    ↓
Delivery card: Pace Score, Rough Speed Bucket, length, line, key observation
Session summary: count, Pace Score trend, challenge mode score
```

45 min of raw video → 36 bite-sized clips you'll actually watch.

## What It Detects

| Attribute | Method | Accuracy | Status |
|-----------|--------|----------|--------|
| Delivery count | MediaPipe wrist spike + Gemini | High | Proven (4/4 nets) |
| Pace Score + Rough Speed Bucket | Delivery mechanics signal + Gemini clip context | Relative metric (not radar speed) | Canonical policy |
| Estimated Speed (optional) | Personal calibration model + confidence gate | Shown only when calibration quality is sufficient | Conditional |
| Length (yorker/full/good/short) | Gemini on clip (visual) | ~75-85% estimated | To validate |
| Line (off/middle/leg) | Gemini on clip (visual) | ~60-70% estimated | To validate |
| Type (seam/spin) | Gemini on clip (action) | ~80%+ estimated | To validate |
| Pitch map (zone-based) | Accumulated Gemini classifications | Approximate zones | To build |

## What It Doesn't Do

- Exact/radar-grade speed claims — not supported in this product.
- Legality assessment — 2D video can't measure 15° elbow extension
- Broadcast video analysis — scene cuts break detection
- Real-time video overlay — latency kills it

## Stack

- **Delivery detection**: MediaPipe Pose on-device (wrist velocity spike) — instant, proven 4/4
- **Count announcement**: iOS TTS (AVSpeechSynthesizer) — count only, zero latency, local
- **Voice conversation**: Gemini Live API (`gemini-2.5-flash-native-audio`) — AUDIO mode, bowler asks → mate answers (R17+R18+R19 validated on device, 8 personas)
- **Challenge mode evaluation**: Gemini on clip (generateContent) — delivery type + success assessment
- **Post-session analysis**: Gemini 3 Pro (`gemini-3-pro-preview`) via generateContent
- **Pace/speed output model**: Pace Score (primary), Rough Speed Bucket (secondary), Estimated Speed only when calibrated with confidence
- **iOS client**: Swift, camera capture + pose overlay
- **Config**: Config E — temp=0.1, default thinking, simple prompt, File API >5MB

## Competitive Landscape

| Tool | Approach | Our Differentiation |
|------|----------|-------------------|
| **FullTrack AI** | Single iPhone behind stumps, ball tracking, pitch maps. 3M+ users. Peer-reviewed (ICC >0.96). | They track the ball pixel-by-pixel. We understand the bowling semantically. They give you data. We give you a mate who talks to you. |
| **PitchVision** | 2 cameras + laptop + activation sensor. Professional coaching. | Hardware kit. We're phone-only. |
| **CricVision** | Cloud-based ball tracking + analysis. | Similar approach but no live audio feedback. |
| **Catapult** | Wearable GPS/inertial sensors. IPL teams. | Hardware. Different market (professional workload management). |

## Repo Structure

```
wellbowled.ai/
├── docs/              # Architecture, prompts, process
├── experiments/       # Detection, speed, live API experiments
├── research/          # Research index, cricket resources
└── codex/             # Codex agent research (parallel)
```

## Previous Demo

Gemini 3 hackathon (Feb 2026): https://www.youtube.com/watch?v=Gpif-vPtYTc

## Key Research (R1-R16)

See `research/README.md` for full index. Highlights:
- **R9**: Config E is best (6/7 PASS at mixed thresholds)
- **R11+R17**: Live API is conversational, not monitoring — revised to MediaPipe detection + iOS TTS + Live API conversation
- **R12+**: Pace Score metric model adopted — relative improvement tracking first, rough bucket context, calibrated estimated speed only
- **R13**: MediaPipe wrist velocity spike: proven delivery trigger
- **R14**: Delivery type detection feasible (length ~75-85%, line ~60-70%)
- **R15**: Competitive landscape — nobody does live audio feedback
- **R16**: Ball tracking SOTA — YOLOv8 viable on mobile via CoreML
