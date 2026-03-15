# Plan: Live Background Analysis During Session

**Goal:** Auto-analyze deliveries in real-time during the live session. When MediaPipe detects a delivery, extract the clip from the ongoing recording and run deep analysis (Gemini vision + DNA + pose) in the background. Feed results back to the Live API buddy so it can debrief mid-session and adjust coaching.

## Why
- Currently analysis only runs post-session or on-demand tap
- In a 30-min session, the buddy is blind to action quality until the session ends
- With live analysis, buddy sees phases/DNA/pace ~10s after each delivery and can intervene
- Closed loop: detect → analyze → debrief → coach → next delivery

## How It Works

### Flow
```
MediaPipe spike detected (delivery N)
  ↓ 2.5s delay (postRoll buffer)
  ↓ Extract 5s clip from live recording (3s pre + 2s post)
  ↓ Auto-trigger deep analysis (parallel: Gemini vision + DNA + pose)
  ↓ ~8s later: results arrive
  ↓ Feed to buddy: [ANALYSIS COMPLETE for delivery N] phases, DNA, pace
  ↓ Buddy speaks natural debrief between deliveries
  ↓ Buddy adjusts coaching based on patterns
```

### Key Insight
iOS `AVCaptureMovieFileOutput` uses fragmented MPEG-4, so we can read from the recording file while it's still being written. No need to stop/restart recording.

## Config (WBConfig)
- `enableLiveAutoAnalysis: Bool = true` — master toggle
- `liveAutoAnalysisDelaySeconds: Double = 2.5` — wait after detection before clip extraction

## Changes

### SessionViewModel.swift
- In `didDetectDelivery()`: after creating delivery and notifying buddy, schedule background task
- New method `scheduleLiveClipAndAnalysis(deliveryID, timestamp)`:
  1. Wait `liveAutoAnalysisDelaySeconds`
  2. Get `cameraService.currentRecordingURL`
  3. Compute clip timestamp (delivery timestamp - recording offset)
  4. Extract clip via `clipExtractor.extractClip()`
  5. Set `delivery.videoURL`, generate thumbnail
  6. Set status to `.queued`, then auto-call `runDeepAnalysis(for: deliveryID)`
  7. Results auto-fed to buddy (already wired from previous commit)

### WBConfig.swift
- Add 2 new config values

### No other file changes needed
- ClipExtractor, GeminiAnalysisService, BowlingDNAMatcher, feedback loop — all already wired

## What This Achieves
- Buddy gives spoken debrief ~12s after each delivery (2.5s delay + ~8s analysis)
- Buddy tracks patterns across deliveries and adjusts coaching live
- Post-session results page shows pre-analyzed deliveries (no waiting)
- For 30-min sessions: continuous feedback loop throughout
