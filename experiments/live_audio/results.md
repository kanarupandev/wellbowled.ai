# Audio Live API Validation Results

## Hypothesis
Native-audio model watches video and proactively speaks about bowling deliveries.

## Verdict: PARTIALLY VALIDATED

The model CAN watch video and understand cricket context. But it's **conversational, not monitoring** — it responds to user speech, not proactively to visual events.

## What Works

| Test | Result |
|------|--------|
| Connection | 0.4-0.7s connect time |
| System instruction | Model follows "expert mate" persona |
| Initial greeting | "Right, I'm watching. Let's see what the bowlers have got." |
| Thinking | "Commencing Nets Observation... tracking each bowling delivery" |
| Audio output | Clear, natural speech (1-3s WAV files) |
| Transcription | `outputAudioTranscription` captures spoken text |
| Session stability | 90s session with context_window_compression — no timeout |

## What Doesn't Work

| Test | Result |
|------|--------|
| Proactive delivery calling | Model goes SILENT after initial greeting — 0 deliveries called across 71 frames |
| Realtime video reaction | Model receives frames but doesn't generate speech without user audio input |
| Text nudges via send_client_content | Only first turn gets a response, subsequent turns ignored |
| Audio silence keepalive | Prevents connection drop but doesn't trigger proactive speech |
| TEXT response modality | "Cannot extract voices from a non-audio request" — native-audio requires AUDIO mode |

## Root Cause

The Live API native-audio model uses **voice activity detection (VAD)** for turn-taking. It speaks after detecting the user has finished speaking. Without detecting user speech, it won't generate output regardless of what it sees in the video.

This is by design — it's a **conversation model**, not a **monitoring model**.

## Approaches Tried

1. **send_realtime_input(media=)** only — model ignores frames after initial turn
2. **send_client_content with inline images** every 5s — only first query gets response
3. **send_realtime_input(media=) + silence audio** — keeps connection alive but no proactive speech
4. **TEXT response modality** — not supported by native-audio model
5. **Periodic text nudges** — ignored after first turn

## Revised Architecture for Hackathon

```
LIVE SESSION (on-device)              CONVERSATION (Live API)
────────────────────────              ──────────────────────
Phone records (60fps)                 Bowler speaks: "How was that?"
MediaPipe detects delivery              ↓
  → instant wrist spike              Live API sees video context +
iOS TTS: "Three. Medium pace."        hears question
  → AVSpeechSynthesizer               ↓
  → zero latency                     Mate responds via audio:
                                     "Good length, nice seam position,
                                      maybe a bit wide of off stump"
```

### Why This Is Better

1. **Delivery detection** is instant (MediaPipe, on-device, proven 4/4)
2. **Count + pace** is zero latency (local TTS)
3. **Conversation** is natural — bowler asks, mate answers with audio
4. Live API does what it's designed for: voice conversation with video context
5. No dependency on API for the core loop (detection + count)

## Model Details

- Model: `gemini-2.5-flash-native-audio-preview-12-2025`
- SDK: `google-genai` v1.64.0
- API version: v1beta
- Voice: Zephyr
- Session config: AUDIO response, LOW media resolution, context compression enabled

## Files

- `validate_audio.py` — experiment script (all approaches)
- `response_audio.wav` — model's audio response ("Right, I'm watching...")
- `transcript.txt` — transcription
- `result_audio_validation.json` — full results
