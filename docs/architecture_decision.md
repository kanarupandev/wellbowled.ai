# Architecture Decision: Option B — Hybrid Live + Post-Session

## Decision

**Hybrid approach**: Live API for real-time delivery detection (trigger), `generateContent` for post-session deep analysis (precision).

## Feasibility Assessment (Based on Phase 2 Experiments)

### What works today

| Capability | Method | Accuracy | Latency | Status |
|-----------|--------|----------|---------|--------|
| Delivery detection (uploaded clip) | generateContent, Config E | 6/7 PASS, 0.04-0.22s precision | 9-12s | **Proven** |
| Single delivery (nets/practice) | generateContent, Config E | 4/4 PASS | 9-12s | **Proven** |
| Broadcast single delivery | generateContent, Config E | 2/3 PASS | 9-12s | **Proven** |
| Replay filtering (slo-mo skip) | Prompt-level | 100% filtered | — | **Proven** |
| Cost at scale | File API + Flash | ~$1/day at 1K calls | — | **Proven** |

### What doesn't work

| Capability | Why | Evidence |
|-----------|-----|----------|
| Broadcast montage (rapid cuts) | Scene cuts confuse temporal reasoning | 3/7 best case, count inconsistent |
| Real-time frame-by-frame overlay | 9-12s latency per analysis | Incompatible with live annotation |
| Legality assessment (elbow angle) | 2D video cannot measure 15° extension | Research R8 |
| Precise speed measurement from video | Need 120+ fps ball tracking | Research R7 |

### Unknown / untested

| Capability | Risk | Notes |
|-----------|------|-------|
| Live API delivery detection | Medium | ~1fps sampling = ~1s temporal precision, no thinking mode |
| Live API stability over long sessions | Unknown | Streaming for 30-60min net sessions |

## The Pipeline

```
LIVE SESSION (at the nets)                    POST-SESSION (async)
─────────────────────────                     ────────────────────

Phone records video (60fps)
        │
        ▼
Live API (~1fps stream)
   "Delivery detected!" ──── trigger ────►  Mark timestamp (±1s)
        │                                          │
        ▼                                          ▼
Show notification to bowler                   Clip 5-sec window
(optional: delivery count)                    (-3s before, +2s after)
        │                                          │
        ▼                                          ▼
Session ends                                  Upload clip via File API
                                                   │
                                                   ▼
                                              generateContent (Config E)
                                              - Precise release timestamp
                                              - Biomechanical analysis
                                              - Speed classification
                                                   │
                                                   ▼
                                              Analysis card per delivery
```

### Why ±1s is fine for clipping

Live API detects at ~1fps. Worst case, the detection timestamp is ~1 second off the actual release. The 5-second clip window (-3s to +2s around detection) covers:
- Late run-up and loading phase (-3s to -1s)
- Actual release point (somewhere in the window)
- Follow-through and early ball flight (+0s to +2s)

Even with ±1s detection error, the release point is captured in the clip. The precise timestamp is then refined by `generateContent` on the clip (proven 0.04-0.22s precision).

### Clipping math

```
Detected at:    T (±1s from actual release)
Clip window:    [T - 3s, T + 2s] = 5 seconds
Actual release: somewhere in [T-1s, T+1s] within the clip
Margin:         at least 1s of run-up and 1s of follow-through guaranteed
```

## Speed Estimation

### Live API: No
1fps means the ball appears in at most 1 frame. A 140kph delivery travels ~20m in ~0.5s — the ball is gone between frames. No ball tracking possible.

### 5-sec clip (Gemini classification): Yes, approximate
Gemini can estimate speed qualitatively from biomechanics in the 5-sec clip:
- Arm speed, run-up intensity, wrist position, body rotation
- Accuracy: ±15-25 kph (classification, not measurement)
- Output: "Fast ~130-140 kph" or "Medium pace ~110-120 kph" or "Spin ~70-85 kph"
- Honest and useful for coaching context. Don't show a precise number.

### 5-sec clip (ball tracking, post-MVP): Better
If phone records at 60fps or 240fps (slo-mo), ball tracking (YOLO/TrackNet) on the 5-sec clip could yield ±5-10 kph. Future work.

### 240fps iPhone ball tracking (feasible)
iPhone 15 records 240fps natively. After detecting delivery (±1s), extract 2-second window from original 240fps = 480 frames of ball flight. Run ball tracking on those frames, calculate speed from displacement + known pitch length (~20m). Needs camera position calibration. Strong post-hackathon feature.

## Hackathon Scope

### Must-have (demo day)
1. **Record session** — phone propped at nets, records full session
2. **Live detection** — Live API streams video, detects "delivery happened" with count
3. **Auto-clip** — 5-sec clips cut around each detected delivery
4. **Post-session analysis** — each clip analyzed via generateContent (Config E)
5. **Results screen** — analysis card per delivery (release timestamp, basic feedback)

### Nice-to-have
- Biomechanical phase analysis (6-phase breakdown per delivery)
- Speed classification per delivery
- Session summary (delivery count, consistency observations)
- Delivery-to-delivery comparison

### Don't attempt
- Real-time biomechanical overlay during bowling
- Precise speed numbers (show ranges only)
- Legality/chucking assessment
- Broadcast video analysis

## Technical Decisions

| Decision | Choice | Why |
|----------|--------|-----|
| Detection model | gemini-3-flash-preview | Proven in Phase 2, cheap, fast enough |
| Analysis model | gemini-3-flash-preview (start), gemini-3-pro-preview (if needed) | Flash first, Pro if biomechanical depth needed |
| Temperature | 0.1 | Higher causes phantom hallucinations (Phase 2, Config B) |
| Thinking | Default (no thinkingConfig) | Deeper reasoning improves timestamp accuracy (Phase 2, Config E) |
| Video upload | File API for clips >5MB, inline <5MB | File API critical for accuracy (Phase 2, WhatsApp 0/4→4/4) |
| Prompt style | Simple, no response schema | Constraints hurt accuracy (Phase 2, Config C) |
| Video resolution | Native (no downscaling) | 480p loses release-point detail (Phase 2, Config D) |
| Clip duration | 5 seconds (-3s, +2s) | Covers run-up through follow-through with ±1s detection margin |

## Cost Projection

| Component | Per-call | Daily (50 sessions × 20 deliveries) | Monthly |
|-----------|----------|--------------------------------------|---------|
| Live API (detection) | ~$0.002/min | ~$2 (50 × 10min) | ~$60 |
| generateContent (analysis) | ~$0.001 | ~$1 (1000 clips) | ~$30 |
| File API (storage) | Free (temp) | $0 | $0 |
| **Total** | | **~$3/day** | **~$90/month** |

## Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Live API can't reliably detect deliveries | Medium | High | Fall back to Option C (post-session only, manual clip or full-video analysis) |
| Live API drops connection during session | Medium | Medium | Local recording continues, do full-video analysis post-session |
| 5-sec clip misses release (detection off by >2s) | Low | Medium | Widen clip window to 7s, or fall back to full-video analysis |
| Gemini 3 Flash preview deprecated | Low | High | Migrate to production Gemini 3 Flash when available |

## Fallback: Option C (post-session only)

If the Live API proves unreliable, the app still works as:
1. Record full session on phone
2. Upload video
3. generateContent detects all deliveries in full video (proven: 6/7 PASS)
4. Auto-clip around each detected delivery
5. Deep analysis per clip

This is Strava for bowling — no live feedback, but solid post-session analysis. Still a viable product.
