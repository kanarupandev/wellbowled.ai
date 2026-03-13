# Delivery Detection Hybrid Strategy (Canonical)

**Date**: 2026-03-05  
**Repo**: `/Users/kanarupan/workspace/wellbowled.ai`  
**Status**: Active source-of-truth for delivery timestamp detection

---

## Implementation Status (2026-03-06)

Implemented in iOS source:
1. `DeliveryBatchPlanner` for:
   - rolling segment scheduling
   - timestamp merge/dedupe
2. `GeminiAnalysisService.detectDeliveryTimestampsInSegment(...)`:
   - segment-level release timestamp extraction using Gemini Flash model config
3. `SessionViewModel.prepareDeliveryClips(...)` hybrid path:
   - run segment scan on full recording
   - merge with live MediaPipe detections
   - rebuild delivery list before clip extraction
   - keep replay-first UX contract

Config keys (all in `WBConfig`):
1. `deliveryDetectionSegmentDurationSeconds` (default: 60)
2. `deliveryDetectionSegmentOverlapSeconds` (default: 5)
3. `deliveryDetectionSegmentStrideSeconds` (derived)
4. `deliveryDetectionMergeWindowSeconds` (default: 0.6)
5. `deliveryDetectionModel` (default: `gemini-2.5-flash`)

---

## 1. Decision

Do not rely on a single detector.

Use a hybrid detector:
1. **Live detector (on-device)**: MediaPipe wrist/pose logic for immediate in-session events.
2. **Batch detector (post-session)**: Gemini Flash on full session recording (2-3 min) to recover missed delivery timestamps.
3. **Merge layer**: dedupe and confidence-rank timestamps before clip extraction.

---

## 2. Why

1. MediaPipe-only can miss deliveries in real nets (occlusion, multiple people, framing changes).
2. Gemini batch-only is too latent for live behavior.
3. Hybrid gives both:
   - live responsiveness
   - post-session reliability.

---

## 3. Operational Flow

## 3.1 During live session

1. Start MediaPipe detector immediately.
2. Use live events for:
   - count announcements
   - challenge progression
   - event-grounded live hints (only when confidence is high).

## 3.2 At session end

1. Open full-session replay immediately.
2. Run Gemini Flash batch detection on full recording and request ordered delivery timestamps.
3. Merge with live detector timestamps.
4. Extract 5-second clips from merged timestamps.
5. Auto-switch to delivery carousel when clipping is complete and at least one delivery exists.
6. If none found, remain on replay with `No deliveries found` overlay.

## 3.3 Rolling Segment Detection (RAG-style chunking)

For Gemini batch detection, use rolling chunks with overlap.

Configurable variables:
1. `segmentDurationSeconds` (default: `60`)
2. `segmentOverlapSeconds` (default: `5`)

Derived value:
1. `segmentStrideSeconds = segmentDurationSeconds - segmentOverlapSeconds`

Example with defaults:
1. segment #1: `0 -> 60`
2. segment #2: `55 -> 115`
3. segment #3: `110 -> 170`
4. segment #4: `165 -> 225`

Rules:
1. each segment is sent independently to Gemini Flash
2. response timestamps are segment-local and must be mapped to session-global time
3. overlap duplicates are merged in the merge layer (dedupe threshold + confidence policy).

---

## 4. Timestamp Merge Rules

Recommended defaults:
1. sort all candidate timestamps ascending
2. dedupe window: `0.6s` (configurable)
3. if two timestamps collide inside window:
   - keep higher-confidence source
   - if equal confidence, keep earlier timestamp
4. clamp negative or out-of-range timestamps.

Source confidence policy:
1. high: confirmed by both detectors
2. medium: single detector with strong signal
3. low: weak/ambiguous single-source signal (exclude from auto-clipping by default).

---

## 5. UX Contract

1. No fake telemetry.
2. Show only real pipeline stages for post-session detection/clipping.
3. Replay-first gate remains:
   - minimum replay hold
   - spinner only if clipping still in progress
   - auto-carousel only when ready.

---

## 6. Validation Targets

Real net sessions target:
1. timestamp lag p95 `<= 2s` for live response path
2. recall `>= 90%`
3. precision `>= 90%`.

If targets fail:
1. reduce live claim scope
2. keep post-session analysis as primary reliability path.

---

## 7. Claim Guardrails

Allowed:
1. hybrid event detection
2. relative pacing and coaching feedback
3. post-session clip reliability improvements.

Disallowed:
1. radar-grade speed claims
2. deterministic per-ball precision claim without measured evidence
3. DRS-grade trajectory claims.
