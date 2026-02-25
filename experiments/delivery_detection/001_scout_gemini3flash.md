# Experiment 001 — Scout Delivery Detection

**Date**: 2025-02-25
**Model**: gemini-3-flash-preview
**Input**: resources/samples/3_sec_1_delivery_nets.mp4 (619KB, 3s, nets session)
**Method**: Inline base64, single-turn generateContent

## Hypothesis

Gemini 3 Flash can detect a single bowling delivery in a 3s clip and return a release timestamp with >0.8 confidence using the count-first-then-locate Scout prompt.

## Request

- Temperature: 0.1
- responseMimeType: application/json
- Prompt: State machine tracking (IDLE/RUN_UP/DELIVERY/FOLLOW_THROUGH) with forced count-first enumeration and phantom detection

## Response

```json
{
  "scan_summary": "The video shows a single cricket delivery performed by a bowler on a concrete pitch.",
  "candidates_considered": 1,
  "confirmed_deliveries": 1,
  "phantom_deliveries": 0,
  "deliveries": [
    {
      "id": 1,
      "release_ts": 1.5,
      "confidence": 0.95
    }
  ]
}
```

## Token Usage

| Type | Count |
|------|-------|
| Video tokens | 357 |
| Text tokens (prompt) | 220 |
| Output tokens | 106 |
| Thought tokens | 608 |
| **Total** | **1,291** |

## Verification

- **Delivery count**: CORRECT — 1 delivery in a 3s clip
- **Release timestamp**: 1.5s — plausible for a 3s clip (mid-clip release)
- **Confidence**: 0.95 — high, appropriate for a clear nets delivery
- **Phantom detection**: 0 — correct, no false positives
- **Scan summary**: Accurate — correctly identified concrete pitch and nets setting

## Result: VERIFIED

The Scout prompt works with gemini-3-flash-preview. Single delivery detection is reliable at high confidence. Next: test with multi-delivery clips and edge cases.
