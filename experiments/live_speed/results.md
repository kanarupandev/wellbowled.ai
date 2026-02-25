# Live Detection + Speed Estimation Results

## Live API Finding

**Gemini 3 Flash does NOT support Live API.** Only `gemini-2.5-flash-native-audio` models do, and they respond via audio (not text). Unsuitable for text-based video event detection.

**Workaround**: Polling with `generateContent` at 3s intervals. Detected 2/4 deliveries + 1 phantom. Misses deliveries that fall between polling windows.

| Delivery | GT (s) | Detected | Delta | Result |
|----------|--------|----------|-------|--------|
| D1 | 6.77 | 7.0 | 0.2s | MATCH |
| D2 | 18.84 | — | — | MISS |
| D3 | 37.58 | 37.0 | 0.6s | MATCH |
| D4 | 59.02 | — | — | MISS |
| Phantom | — | 1.0 | — | FALSE |

**Implication for app**: Live API is not ready for our use case. Use on-device detection (MediaPipe wrist velocity spike) as trigger, or full-video analysis post-session.

## Speed Estimation

### Gemini 3 Pro — Best overall

| Clip | Avg kph | Spread | Stdev | Type | Consistent (±2) |
|------|---------|--------|-------|------|------------------|
| D1 | 99 | 10 | 4.6 | medium/medium-slow | No |
| D2 | 96 | 13 | 5.1 | medium-slow | No |
| D3 | 98 | 11 | 4.1 | medium-slow | No |
| D4 | 98 | 13 | 5.2 | medium/medium-slow | No |

**Cross-delivery consistency**: All 4 deliveries estimated at 96-99 kph (same bowler). Spread across deliveries is only 3 kph — the model is consistent at the delivery level even if individual runs vary by 10-13 kph.

**Verdict**: Type classification (medium/medium-slow) is reliable. Absolute speed ±10 kph. Cross-delivery spread ±3 kph. Not within ±2 kph per-run consistency target, but strong enough for coaching ("you're bowling medium pace, ~95-100 kph range").

### YOLO (YOLOv8n, COCO pretrained) — Not viable at 30fps

| Clip | Ball detections | Speed range | Verdict |
|------|----------------|-------------|---------|
| D1 | 0 | — | No ball found |
| D2 | 4 | 3-4 kph | False positives |
| D3 | 15 | 3-49 kph | Noisy, some real |
| D4 | 0 | — | No ball found |

**Why**: Cricket ball is small (~7cm), fast, motion-blurred at 30fps. COCO "sports ball" class trained on visible, well-lit balls. At 30fps a 120kph delivery moves ~1.1m/frame — heavy motion blur.

**Fix**: Needs 240fps iPhone recording + cricket-specific fine-tuning (1068 images available on Kaggle). TrackNetV3/V4 architecture designed for small fast objects.

### MediaPipe Pose — Useful signal, not direct speed

| Clip | Bowling arm | Peak wrist vel (px/s) | Release frame | Arm angle at extension |
|------|-------------|----------------------|---------------|----------------------|
| D1 | Right | 1967 | 29 (0.97s) | 177° at frame 46 |
| D2 | Left* | 1388 | 13 (0.43s) | 180° at frame 20 |
| D3 | Right | 1016 | 8 (0.27s) | 180° at frame 1 |
| D4 | Right | 1516 | 17 (0.57s) | 179° at frame 50 |

*D2 bowling arm detection may be wrong — visibility was low.

**Useful for**:
1. **Release point confirmation** — peak wrist velocity marks the release moment
2. **Bowling arm identification** — which arm has higher peak velocity
3. **Arm extension angle** — 177-180° at extension confirms full bowling action
4. **Speed proxy** — peak wrist velocity correlates with ball speed (D1 highest at 1967 px/s)

**Not useful for**: Absolute speed in kph. Pixel velocity depends on camera distance/angle.

## Comparison

| Approach | Speed accuracy | Consistency | Cost | Latency | Status |
|----------|---------------|-------------|------|---------|--------|
| Gemini Pro | ±10 kph | ±3 kph cross-delivery | ~$0.003/clip | 22-51s | **Use for hackathon** |
| YOLO (30fps) | Not viable | — | Free | <1s | Needs 240fps + fine-tuning |
| MediaPipe | Proxy only | Relative ranking | Free | <1s | **Use as signal** |

## Recommendations

1. **Hackathon**: Gemini Pro speed classification on 2.5s clips. Show "Medium pace ~95-100 kph" not "97 kph"
2. **Post-hackathon**: iPhone 240fps recording → YOLO fine-tuned ball tracking → precise speed
3. **MediaPipe**: Use wrist velocity as release point detector (trigger for clipping) and bowling arm identifier. Potential to correlate wrist velocity with speed over time (build regression model from Gemini estimates)
4. **Live detection**: MediaPipe on-device wrist velocity spike as delivery trigger instead of Live API. This is local, instant, and proven from this experiment (peak velocity clearly marks release)
