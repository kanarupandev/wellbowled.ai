# Speed Gradient — Broadcast Clip Feasibility

## Input Reality

Broadcast replays (IPL, international) give **<1 second** of the actual delivery stride. At 30fps = **10-17 usable frames** from back foot contact to follow-through.

## Is 10-17 Frames Enough?

**Yes.** The kinetic chain fires in ~0.3s (~9 frames at 30fps). The proximal→distal energy wave — hips peak first, then trunk, then shoulder, then elbow, then wrist — spans 4-6 frame offsets. 10-17 frames captures the full sequence.

## What We Can Compute

| Signal | Feasibility | Notes |
|--------|-------------|-------|
| Peak ordering (which joint peaks when) | **Strong** | Only needs relative frame indices. Robust to noise. |
| Segment dominance per frame ("hottest joint") | **Strong** | Comparing 5 values per frame — noise cancels across joints. |
| Smooth velocity curves | **Marginal** | 5-frame Savgol works but curves will be coarse (10-15 data points). |
| Absolute velocity values | **Not useful** | Broadcast resolution + 2D projection = meaningless absolute numbers. |

## Key Risk: Landmark Noise

Velocity = frame-to-frame position difference. At broadcast resolution the bowler is small in frame. MediaPipe jitter ±2-3% normalized coords per frame. When real movement between frames is also small, noise can dominate.

**Mitigations:**
- Savitzky-Golay smoothing (window=5, polyorder=2) — still valid at 15 frames
- Confidence gating — reject landmarks below visibility threshold
- Only use relative peak ordering, not absolute magnitudes
- Compare joints *within* each frame (relative ranking), not across frames

## Approach: Energy-State Threading

Treat each frame as a discrete energy state. Don't try to play a smooth video — instead, hold each frame long enough for the viewer to absorb the color/energy state, and transition between them.

The few frames become a strength: each one is a distinct chapter in the kinetic chain story.

## Conclusion

10-17 broadcast frames is **sufficient for the sequencing signal** (which segment peaks when). Marginal for smooth velocity curves, but that's a presentation choice, not a data limitation.
