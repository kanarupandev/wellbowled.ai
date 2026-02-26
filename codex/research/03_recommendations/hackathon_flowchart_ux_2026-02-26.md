# Hackathon Flowchart + UX Engagement Design

Date: 2026-02-26
Scope: Gemini Live API hackathon flow emphasizing continuous user engagement.

## Flowchart (system + UX)

```mermaid
flowchart TD
    A["Home: Start Session"] --> B["Pre-Flight Check<br/>camera/mic/network/model ready"]
    B --> C["Countdown (3..2..1) + clear goal<br/>'Bowl 6 balls'"]

    C --> D["LIVE SCREEN (primary)<br/>camera preview + pose ghost + count badge"]
    D --> E["Gemini Live API (native-audio)<br/>low-res stream, AUDIO response"]
    E --> F["Spoken live cue<br/>'Delivery 3, good rhythm'"]
    F --> D

    D --> G["Micro-engagement UI always active:<br/>progress ring, streak, last cue chip,<br/>haptic pulse on event"]
    G --> D

    E --> H["Delivery event parsed from transcript"]
    H --> I["On-device ring buffer clip save<br/>5s rich clip (-3s/+2s)"]

    I --> J["Instant card placeholder (0.2s)<br/>thumbnail + 'Analyzing this ball…'"]
    J --> K["Deep analysis request (Gemini)"]

    K --> L["Structured result:<br/>phase_ranges + events + pros/cons + injury_risks + pace_band"]
    L --> M["Timeline render:<br/>Green=Pro, Yellow=Attention, Red=Injury Risk<br/>(colors from Gemini labels)"]
    L --> N["MediaPipe overlay render at key timestamps<br/>(pose/angles/paths visualized)"]
    M --> O["Delivery Detail Screen"]
    N --> O

    O --> P["Phase-focused Chat<br/>'Ask about release/follow-through' chips"]
    P --> Q["Tap chip or ask question"]
    Q --> R["Jump player to referenced time range"]
    R --> O

    L --> S["Action signature builder (100-300 features)"]
    S --> T["Vector DB match vs bowling DNA set"]
    T --> U["Similarity panel:<br/>closest bowlers + differences"]

    D --> V["End Session"]
    V --> W["Session Summary:<br/>count, highlights, top 1 pro / top 1 risk,<br/>next focus suggestion"]
    U --> W
```

## Label ownership (important)
- MediaPipe does not assign semantic labels like `PRO/ATTENTION/INJURY_RISK`.
- Gemini deep analysis assigns those labels with timestamp evidence.
- App applies color mapping:
  - `PRO -> Green`
  - `ATTENTION -> Yellow`
  - `INJURY_RISK -> Red`

## UX anti-idle rules
1. Every waiting moment must show progress + purpose text.
2. After each delivery, show immediate placeholder card before deep analysis completes.
3. Keep multi-sensory event confirmation (audio + visual badge + haptic).
4. Keep one-tap actions available while analysis runs (`Replay`, `Ask about release`, `Next ball`).
5. Start chat with quick phase chips to avoid blank-state friction.
6. End session with exactly one prioritized next focus area.

## Suggested deep-analysis response contract
```json
{
  "phase_ranges": [{"name": "release", "start_s": 2.1, "end_s": 2.8}],
  "events": [{"type": "release", "time_s": 2.42}],
  "pros": [{"label": "Stable head", "time_s": 2.3, "evidence": "..."}],
  "cons": [{"label": "Late trunk collapse", "time_s": 3.1, "evidence": "..."}],
  "injury_risks": [{"label": "Front-knee overload", "severity": "medium", "time_s": 2.9, "evidence": "..."}],
  "pace_band": {"label": "medium", "range_kph": "95-105", "confidence": 0.74},
  "signature_vector": [0.123, 0.456, 0.789]
}
```
