# Delivery Detection: Architecture Comparison

**Date**: 2025-02-25
**Status**: RESEARCH COMPLETE — experiments needed to validate

---

## Approaches

| | A: Gemini-Only | B: MediaPipe-Only | C: Hybrid |
|---|---|---|---|
| **How** | Send video to Gemini API → timestamps | Pose estimation every frame on-device → arm rotation peak | MediaPipe detects instantly, Gemini confirms selectively |

---

## 1. Comparison Matrix

| Dimension | A: Gemini-Only (VERIFIED) | B: MediaPipe-Only (ESTIMATED) | C: Hybrid |
|---|---|---|---|
| **Precision** | +/- 0.1s (measured, 5 runs) | +/- 0.03-0.08s at 30fps | Best of both |
| **Latency** | **~9s** API round-trip | **<100ms** real-time | <100ms detect, 9s async confirm |
| **Cost** | ~$0.000003/call | **$0.00** | ~$0.00 (80% free) |
| **Works offline?** | No | **Yes** | Partial |
| **False positives** | LOW (0/5 measured) | MEDIUM-HIGH (arm waves, stretches) | LOW |
| **False negatives** | LOW | LOW fast; MEDIUM spin | LOWEST |
| **Nets/backyard** | MEDIUM | LOW-MEDIUM (mesh confuses pose) | MEDIUM-HIGH |
| **Low light** | MEDIUM | LOW | MEDIUM |
| **Spin bowling** | GOOD | MEDIUM (lower angular velocity peak) | GOOD |
| **Shadow bowling** | GOOD (semantic) | GOOD (physics identical) | BEST |

---

## 2. Cost Reality: Gemini is essentially free

| Volume | Monthly Cost |
|--------|-------------|
| 100 calls/day | $0.009 |
| 1,000 calls/day | $0.09 |
| 10,000 calls/day | $0.90 |

**Cost is not a decision factor.** Choose based on latency and reliability.

### Latency optimization lever

`thinkingLevel` parameter (Gemini 3 models):

| Level | Expected Latency | Notes |
|-------|-----------------|-------|
| `high` (current) | ~9s | Full reasoning |
| `low` | ~4-6s | Likely sufficient for detection |
| `minimal` | ~3-5s | May degrade edge cases |

---

## 3. MediaPipe Detection Algorithm

### Relevant Landmarks (from 33 pose landmarks)

| Landmark | Index | Role |
|----------|-------|------|
| Bowling arm shoulder | 12 (R) / 11 (L) | Rotation center |
| Bowling arm elbow | 14 (R) / 13 (L) | Fallback when wrist occluded |
| Bowling arm wrist | 16 (R) / 15 (L) | Primary signal: peak angular velocity = release |
| Hips | 23, 24 | Run-up detection via displacement |

### Pipeline

```
Video frames (30fps)
  → MediaPipe Pose Landmarker (per frame)
  → Compute shoulder-to-wrist angle θ(t)
  → Angular velocity ω(t) = dθ/dt (smoothed, 5-frame window)
  → State machine: IDLE → RUN_UP → DELIVERY → FOLLOW_THROUGH
  → Release = argmax(ω) within DELIVERY window
```

### Thresholds

| Action | Peak ω (deg/s) | Detected as delivery? |
|--------|----------------|----------------------|
| Standing still | < 30 | No |
| Walking arm swing | 60-180 | No |
| Underarm throw | 180-480 | No (wrist stays below shoulder) |
| **Spin bowling** | **300-600** | Yes |
| **Medium pace** | **600-1200** | Yes |
| **Fast bowling** | **1200-2100** | Yes |

Detection rule: Peak ω > 480 deg/s AND total rotation > 120° AND wrist reaches above shoulder.

### Critical Limitation

**Wrist occlusion at release**: The exact moment we need is when the data is least reliable. Motion blur + self-occlusion drops wrist confidence to 0.3-0.4 during the fastest part of the arm arc.

Mitigations: interpolation across short gaps, elbow as fallback, envelope detection.

---

## 4. Hybrid Architecture

### When MediaPipe runs
Always — during recording and video import.

### When Gemini is called
Only when needed:

| Condition | Gemini? |
|-----------|---------|
| MediaPipe confidence >= 0.85 | No — instant confirmed card |
| MediaPipe confidence < 0.85 | Yes — Scout confirmation (~9s async) |
| 0 detections in expected segment | Yes — safety net scan |
| User requests analysis | Yes — Expert deep analysis |

### Disagreement handling

| MediaPipe | Gemini | Action |
|-----------|--------|--------|
| DELIVERY | DELIVERY | Confirmed, use MediaPipe timestamp |
| DELIVERY | NO DELIVERY | Downgrade to "Unconfirmed" |
| NO DELIVERY | DELIVERY | Create card from Gemini (delayed) |
| NO DELIVERY | NO DELIVERY | Nothing |

---

## 5. Production Path

| Stage | Approach | Why |
|---|---|---|
| **Hackathon** | Gemini-only | Already verified. Shows Gemini's power. |
| **MVP** | Gemini-only + latency optimization | Reliable, simple. Tune `thinkingLevel`. |
| **Post-MVP** | Hybrid (MediaPipe + Gemini) | Instant detection + semantic confirmation. |
| **Scale** | On-device primary (95%) | Offline capable, real-time, cost-free detection. |

---

## 6. Biggest Risks

1. **MediaPipe false positive rate is UNKNOWN** — zero data on angular velocity thresholding in real conditions
2. **Wrist occlusion at release** — pose data least reliable at the critical moment
3. **Hybrid UX** — card appearing then changing state may feel janky

---

## 7. Next Experiments

| # | Experiment | What it validates | Effort |
|---|-----------|-------------------|--------|
| **002** | Gemini Scout with `thinkingLevel: "low"` and `"minimal"` | Can we cut latency from 9s to 3-5s without losing accuracy? | Low — parameter change |
| **003** | MediaPipe pose on sample video (Python, not iOS) | Can angular velocity peak detect the release within 0.2s? | Medium — need mediapipe pip package |
| **004** | MediaPipe on 5 bowling + 5 non-bowling clips | False positive rate: can we distinguish bowling from arm waves? | Medium — need more sample videos |
| **005** | Hybrid end-to-end | Full flow: MediaPipe detect → Gemini confirm → measure UX timing | High — after 002-004 pass |

---

## 8. Honest Limitations

| Claim | Reality |
|-------|---------|
| "MediaPipe gives 33ms precision" | Only when wrist is visible. Degrades to 50-120ms during release. |
| "Hybrid is always better" | Adds complexity. For hackathon, Gemini-only is correct. |
| "On-device is free" | Free in API cost. Not free in battery, binary size, or engineering. |
| "Angular velocity detects bowling" | **UNVERIFIED.** Needs experiment 003. |
| "9s latency is the floor" | `thinkingLevel` could cut to 3-5s. Needs experiment 002. |
