# Experiment 003: Ground Truth Comparison

**Date**: 2025-02-25
**Status**: VERIFIED

## Ground Truth

- Video: 3_sec_1_delivery_nets.mp4 (30fps, 111 frames, 3.70s)
- **Release frame: 30** (human-verified)
- **Release timestamp: 1.000s**

## Results

| Method | Release ts | Delta | Within 0.2s? |
|--------|-----------|-------|--------------|
| **Gemini minimal** | 0.96s | **0.04s** | YES |
| **Gemini low** | 0.86s | **0.14s** | YES |
| **Gemini default** | 1.38s | **0.38s** | NO |
| **MediaPipe (peak ω)** | 1.30s | **0.30s** | NO |

## Key Findings

1. **Gemini minimal is best**: 0.04s delta, 4.5s latency, 0 thought tokens
2. **Gemini low is good**: 0.14s delta, 4.3s latency, 0 thought tokens
3. **Default thinking overshoots**: +0.38s late. The thinking tokens overthink and land on follow-through, not release.
4. **MediaPipe peak ω is late**: Wrist occlusion delays the detected peak by ~0.3s. The angular velocity peak occurs after the ball has left the hand because the wrist visibility drops during the actual release.

## Revised Recommendation

- **Use `thinkingLevel: MINIMAL`** for Scout detection
- Latency: 4.5s (vs 9s default) — **53% reduction**
- Accuracy: 0.04s from ground truth — **best of all approaches**
- Cost: ~840 tokens/call (vs ~1,500 default) — **44% token reduction**

## MediaPipe Limitation Confirmed

MediaPipe's wrist visibility drops to 0.38 during the delivery arc. The angular velocity peak is delayed because:
- Motion blur makes wrist undetectable at the actual release
- The detected "peak" is when the wrist becomes trackable again post-release
- This makes raw MediaPipe unreliable for precise release timing without interpolation
