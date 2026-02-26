# Results Claim Manifest

Date: 2026-02-26
Purpose: Prevent claim drift by mapping each headline claim to exact source artifacts.

## Delivery detection

| Claim | Canonical source files | Notes |
|---|---|---|
| Config E is best overall among A/C/E on current benchmark set | `experiments/delivery_detection/result_E_*.json` compared with `result_A_*.json`, `result_C_*.json` | Use strict and operational metrics side-by-side |
| `6/7 PASS` headline | `experiments/delivery_detection/phase2_configs.md` + `result_E_umran_malik_150kph.json`, `result_E_kapil_jones_swing.json`, `result_E_whatsapp_nets_session.json` | Mixed threshold framing; not strict 0.2s-only metric |
| Config C smoke-test overfit | `result_C_3_sec_1_delivery_nets.json` vs `result_C_umran_malik_150kph.json`, `result_C_kapil_jones_swing.json`, `result_C_whatsapp_nets_session.json` | Strong degradation outside smoke clip |
| Montage limitation (bumrah) remains open | `result_E_bumrah_bairstow_swing.json` | Count instability across runs (5, 8, 6 vs GT 7) |

## Live detection

| Claim | Canonical source files | Notes |
|---|---|---|
| Polling fallback detects 2/4 deliveries with 1 phantom | `experiments/live_speed/result_live_detection.json` | This is measured evidence in repo |
| Native-audio Live API is likely direction | `experiments/live_speed/results.md` (interpretation) | Treat as hypothesis unless direct measured experiment artifact is added |

## Speed estimation

| Claim | Canonical source files | Notes |
|---|---|---|
| Gemini speed outputs are cluster-consistent across deliveries | `experiments/live_speed/result_speed_gemini.json` | Cross-delivery mean spread ~2.2 kph in current set |
| YOLO COCO model not viable at current settings | `experiments/live_speed/result_speed_yolo.json` | Mostly false/no ball detections |
| MediaPipe wrist velocity useful as release proxy | `experiments/live_speed/result_speed_mediapipe.json` | Useful proxy, not calibrated km/h |

## Governance rule
When updating any summary doc (`research/README.md`, `docs/architecture_decision.md`, `experiments/*/results.md`), include source file references from this manifest for each quantitative claim.
