# Phase 1: Single-Clip Delivery Detection

**Sample**: `3_sec_1_delivery_nets.mp4` (30fps, 111 frames, 3.70s)
**Ground truth**: Frame 30 = **1.000s**

## Results

| thinkingLevel | Release ts | Delta | Latency | Tokens | Runs |
|---------------|-----------|-------|---------|--------|------|
| **minimal** | 0.96s avg | **0.04s** | 4.53s | 843 | 5/5 correct |
| low | 0.86s avg | 0.14s | 4.29s | 840 | 5/5 correct |
| default | 1.38s avg | 0.38s | 9.09s | 1,589 | 5/5 correct |

MediaPipe (heavy model, peak ω): 1.30s — delta 0.30s (wrist occlusion delays peak)

## Findings

1. All thinkingLevels detect 1 delivery, 0 phantoms — **detection is robust**
2. `MINIMAL` is most accurate for release timing (0.04s delta)
3. `default` overshoots — thinking tokens land on follow-through, not release
4. MediaPipe wrist visibility drops to 0.38 during delivery — unreliable alone for timestamp
5. Timestamp consistency within each level: 0.10-0.30s range across 5 runs

## Decision

Use `thinkingLevel: MINIMAL` for Scout. Best accuracy + half the latency + half the tokens.
