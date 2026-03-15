# Plan: Live Segment Detection Queues

**Goal:** Replace MediaPipe with Gemini Flash as the **sole** delivery detector. MediaPipe is fully silenced (too many false positives). Two serial queues process 30s segments with 5s overlap and deep analysis independently — all while the session is live. By session end, deliveries are already detected and analyzed.

**Status: COMPLETE** — MediaPipe silenced, overlapping segments, deduplication, buddy feedback all wired.

## Architecture

```
Recording (continuous, fragmented MPEG-4)
  │
  ├─ every 30s: export 30s segment → enqueue to Queue A
  │
  ▼
Queue A (serial) — Detection
  segment → Gemini Flash → delivery timestamps + confidence
  → confidence ≥ 0.9? extract 5s clip → create Delivery → enqueue to Queue B
  → discard segment file
  → next segment from queue
  │
  ▼
Queue B (serial) — Deep Analysis
  5s clip → Gemini vision + DNA + pose (parallel internally)
  → results → feed buddy via sendContext()
  → next clip from queue
```

## Key Details

- **Queue A** processes segments one-by-one; doesn't block the 30s timer from adding more
- **Queue B** processes clips one-by-one; doesn't block Queue A (both run concurrently)
- **90% confidence threshold** filters false positives before expensive deep analysis
- **Deduplicate** by timestamp proximity — don't re-analyze same delivery detected in overlapping segments or by MediaPipe
- **MediaPipe stays** for instant TTS count ("1.", "2.") — cosmetic only, no analysis triggered
- **Post-session segment scan becomes unnecessary** — everything already scanned live
- **Fragmented MPEG-4**: iOS AVCaptureMovieFileOutput writes fragmented MP4, so we can read/export from the file while still recording

## Config (WBConfig.swift)

```swift
// Live segment detection
static let liveSegmentDurationSeconds: Double = 30.0
static let liveSegmentConfidenceThreshold: Double = 0.9
```

## Changes

### SessionViewModel.swift

#### New state
```swift
private var liveSegmentTimerTask: Task<Void, Never>?
private var liveDetectionQueue: [URL] = []          // Queue A: segment URLs waiting for detection
private var liveDeepAnalysisQueue: [UUID] = []      // Queue B: delivery IDs waiting for deep analysis
private var liveDetectionTask: Task<Void, Never>?   // Queue A processor
private var liveDeepAnalysisTask: Task<Void, Never>? // Queue B processor
private var liveScannedUpTo: Double = 0             // recording-time already scanned (avoids overlap)
private var liveDetectedTimestamps: [Double] = []   // for deduplication
```

#### New methods

1. **`startLiveSegmentDetection()`** — called from `startSession()` after recording starts
   - Starts a recurring task: every 30s, export the latest 30s from the live recording and enqueue to Queue A
   - Tracks `liveScannedUpTo` to avoid re-scanning the same time range

2. **`stopLiveSegmentDetection()`** — called from `endSession()`
   - Cancels timer, drains queues, cancels processing tasks

3. **`processDetectionQueue()`** — Queue A processor (runs as long-lived Task)
   - Picks next segment URL from `liveDetectionQueue`
   - Calls `analysisService.detectDeliveryTimestampsInSegment()` (already exists)
   - For each detection with confidence ≥ 0.9:
     - Deduplicate against `liveDetectedTimestamps` (skip if within 3s of existing)
     - Extract 5s clip via `clipExtractor.extractClip()`
     - Create `Delivery`, set `videoURL`, generate thumbnail
     - Notify buddy: `[CLIP READY for delivery N]`
     - Add delivery ID to `liveDeepAnalysisQueue`
   - Clean up segment file
   - Loop: check for next segment in queue

4. **`processDeepAnalysisQueue()`** — Queue B processor (runs as long-lived Task)
   - Picks next delivery ID from `liveDeepAnalysisQueue`
   - Calls existing `runDeepAnalysis(for:)` — this already handles Gemini vision + DNA + pose + buddy feedback
   - Loop: check for next delivery in queue

#### Modified methods

- **`startSession()`**: call `startLiveSegmentDetection()` after recording starts
- **`endSession()`**: call `stopLiveSegmentDetection()`
- **`didDetectDelivery()`**: remove `scheduleLiveClipAndAnalysis` call — MediaPipe only does TTS count now
- **Post-session `startClipPreparation()`**: skip Gemini segment scan if live scanning already found deliveries

### WBConfig.swift
- Add `liveSegmentDurationSeconds = 30.0`
- Add `liveSegmentConfidenceThreshold = 0.9`

### No other file changes needed
- `GeminiAnalysisService.detectDeliveryTimestampsInSegment()` — already exists, reused as-is
- `ClipExtractor.extractClip()` — already exists
- `exportDetectionSegment()` — already exists on SessionViewModel
- `runDeepAnalysis(for:)` — already exists, already feeds buddy

## What This Achieves

- **Reliable detection**: Gemini Flash >> MediaPipe for delivery detection accuracy
- **~30-70s after bowling**: buddy speaks debrief (30s segment wait + ~40s analysis)
- **No false positive waste**: 90% confidence gate before deep analysis
- **Post-session instant**: results page shows pre-analyzed deliveries
- **Demo flow**: bowl → buddy debriefs within ~1 min → adjusts coaching
