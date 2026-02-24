# wellBowled — Session Onboarding

## What is this?

An expert buddy for cricket bowlers. Not a coach — a research partner that uses video and pose data to help bowlers understand and experiment with their action.

Built for the **Gemini Live Hackathon 2026**.

## Stack

- **Engine**: Gemini 3 Flash (Multimodal Live API)
- **Vision**: MediaPipe Pose (client-side) + Gemini reasoning (server-side)
- **iOS client**: Swift, camera capture + pose overlay
- **Backend**: Python, prompt engine + Gemini API

## Three Modes

| Mode | Purpose | Latency |
|------|---------|---------|
| **Detection** | Identify when a delivery starts/ends | Ultra-low |
| **Live Analysis** | Real-time phase slicing + conversational feedback | Low |
| **Deep-Dive** | Post-session biomechanical signature + benchmarking | Async |

## The 6 Phases

Run-up → Back Foot Contact (BFC) → Front Foot Contact (FFC) → Release → Follow-through

Target: phase detection delta < 0.2s (achieved via dual-track MediaPipe timestamps + Gemini semantics).

## Repo Structure

```
wellbowled.ai/
├── docs/           # You are here
├── backend/        # Python — Gemini API, prompt engine
├── ios/            # Swift — MediaPipe + camera
└── prompts/        # System prompts (Detection, Live, Deep-Dive)
```

## Setup

_TBD — will be filled as components are built._
