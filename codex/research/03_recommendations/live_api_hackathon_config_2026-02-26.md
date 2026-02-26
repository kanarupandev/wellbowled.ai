# Gemini Live API Hackathon Configuration (Deep Research)

Date: 2026-02-26
Scope: Hackathon-only design (no production stack expansion)

## 1) What the docs constrain (must design around)
1. One response modality per session: `TEXT` or `AUDIO`, not both.
2. Audio+video session limit is short (documented as ~2 minutes without compression).
3. Native audio models have larger Live context windows (128k vs 32k for other Live models).
4. Connection lifetime can terminate; session resumption exists and should be used for continuity.
5. `mediaResolution` is configurable; lower resolution is explicitly supported.
6. Live API supports realtime `audio`, `video`, and `text` streams.

## 2) Recommended hackathon architecture

### Goal
Reliable demo loop: stream -> detect -> speak -> clip locally -> optional short clip summary.

### Chosen mode
- Primary: **single Live session with AUDIO response modality** (hands-free coaching UX).
- Parsing aid: enable output transcription so app can parse deterministic event strings from spoken response.

### Why this is best for hackathon
- Satisfies Gemini Live API requirement directly.
- Avoids building a second full pipeline.
- Keeps UX impressive (spoken feedback) while still machine-readable via transcript.

## 3) Concrete session config (recommended baseline)

Model choice:
- Primary: `gemini-2.5-flash-native-audio-preview-12-2025` (as shown in current Live docs examples).
- Fallback if unavailable in project/region: `gemini-2.5-flash-native-audio-preview-09-2025`.

Session setup:
```json
{
  "responseModalities": ["AUDIO"],
  "mediaResolution": "MEDIA_RESOLUTION_LOW",
  "outputAudioTranscription": {},
  "realtimeInputConfig": {
    "automaticActivityDetection": {
      "disabled": false,
      "startOfSpeechSensitivity": "START_SENSITIVITY_LOW",
      "endOfSpeechSensitivity": "END_SENSITIVITY_LOW",
      "prefixPaddingMs": 40,
      "silenceDurationMs": 200
    }
  },
  "thinkingConfig": {
    "thinkingBudget": 0
  },
  "sessionResumption": {}
}
```

Notes:
- `thinkingBudget: 0` is a latency-oriented setting for event detection use.
- `mediaResolution LOW` reduces bandwidth/latency and helps session stability.
- Keep local device recording at high FPS for clips; Live stream does not need high FPS.

## 4) Input streaming profile (hackathon practical)

Video to Live:
- Send ~4-8 fps equivalent frames (not full 60/120/240 fps stream).
- Use low resolution frames for inference.

Audio to Live:
- Input PCM accepted; docs state native 16kHz input and output audio at 24kHz.
- If mic is paused, send `audioStreamEnd` event.

On-device recording:
- Record locally at 60fps (or 240fps if device allows and storage permits).
- Clip extraction remains local: window `[-3s, +2s]` around detected delivery.

## 5) Prompt contract for deterministic event handling

Use system instruction that forces short spoken event tags, example:
- `EVENT DELIVERY count=4 pace=MEDIUM confidence=0.78`
- `EVENT NONE`

App parses `outputAudioTranscription` text for `EVENT` lines while user hears spoken feedback.

## 6) Session lifecycle strategy for 2-minute audio+video constraint

- Open session per bowling burst (target 60-90s active use).
- Before timeout, rotate connection and resume session using last resumption handle.
- If resumption fails, start fresh session and continue local clip capture unaffected.

## 7) Latency/feasibility expectations (hackathon)

What is realistic:
- Near-real-time spoken detection cues (seconds-level), not frame-perfect timestamps.
- Short spikes and occasional misses are acceptable if clip replay/summary is available.

What not to promise:
- Exact km/h from Live stream.
- Guaranteed sub-second delivery timestamps from Live alone.

## 8) Demo-safe fallback ladder

1. Primary: Live AUDIO mode (native audio model).
2. If unstable: Live TEXT mode with same event tags, local TTS for spoken output.
3. If Live drops: continue local clip capture; run post-clip `generateContent` summaries.

## 9) Hackathon success checklist

- Delivery count increments reliably in demo scenario.
- Spoken confirmation arrives consistently enough to feel live.
- Clips are auto-saved on each event and replayable instantly.
- App remains usable when Live reconnects or briefly fails.

## Sources
- Live capabilities + modality/media/VAD/transcription: https://ai.google.dev/gemini-api/docs/live-guide
- Live session limits/resumption/compression behavior: https://ai.google.dev/gemini-api/docs/live-session
- Live WebSocket API reference (realtime input fields): https://ai.google.dev/api/live
- Ephemeral token flow for client-side Live: https://ai.google.dev/gemini-api/docs/ephemeral-tokens
- Rate-limit framework and per-project quota model: https://ai.google.dev/gemini-api/docs/rate-limits
- Model deprecation/update notes for Live audio model IDs: https://ai.google.dev/gemini-api/docs/changelog
