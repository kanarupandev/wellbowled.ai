# Netball Video Analysis - Bowling Action + Speed Estimate

Date: 2026-02-26
Inputs:
- `/Users/kanarupan/Downloads/netball1.mp4`
- `/Users/kanarupan/Downloads/netball2.mp4`

Method:
- Local pose analysis using MediaPipe Pose Landmarker (heavy model).
- Release proxy = peak bowling-wrist velocity.
- Speed estimate = pose-velocity proxy calibrated against prior internal clips.

Important limitation:
- Absolute km/h is low-confidence without ball-tracking or radar calibration.
- Treat speed as a **coarse band** only.

## Summary table

| Video | Arm | Release time | Run-up style | Peak wrist vel (px/s) | Arm extension near release | Estimated speed | Confidence |
|---|---|---:|---|---:|---:|---|---|
| netball1.mp4 | Right | 2.55s | Longer run-up | 1107.3 | 178.6 deg | ~97.6 kph (band: 90-105) | Medium (proxy) |
| netball2.mp4 | Right | 1.17s | Compact run-up | 1618.7 | 173.9 deg | ~98.0 kph (band: 90-105) | Medium (proxy) |

## Action observations

### netball1.mp4
- Likely right-arm delivery action.
- Longer approach before release.
- Bowling arm reaches near-full extension at release (good extension signal).

### netball2.mp4
- Likely right-arm delivery action.
- More compact run-up, quicker gather to release.
- Bowling arm also reaches near-full extension at release.

## Comparative take
- Both clips show similar coarse speed band despite different approach lengths.
- netball2 has higher peak wrist velocity but proxy mapping remains conservative due calibration limits.
- For trustworthy absolute speed, use 240fps + ball tracking (or radar/reference calibration).

## Artifacts
- Raw JSON output: `codex/submission/netball_analysis_2026-02-26.json`
