# Content Series Strategy — Upload Order & Reasoning

## Decision: 2026-03-26

### Why X-Factor First

The X-Factor (hip-shoulder separation) is the first video to reach v1.0.0 because:

1. **Universally understood** — two colored lines diverging. A 12-year-old sees it and gets "the bigger the gap, the faster the ball." No cricket knowledge needed to grasp the visual.

2. **Most developed pipeline** — delivery-window gating (overlays only during the delivery stride), Gemini Flash bowler ROI (isolates the bowler, ignores background people), smoothed angle computation with side-on noise filtering. 90% of the engineering is done.

3. **Built-in comparison hook** — verdict card shows You vs Steyn vs Lee on a scale from Untrained (12°) to Elite (47°). Every viewer mentally places themselves on that scale. That's the share trigger.

4. **Establishes the visual language** — hip line = pink, shoulder line = cyan. Once the audience learns this in video #1, every subsequent video builds on it.

5. **Works on any clip** — nets session, match footage, indoor, outdoor, any camera angle. The Gemini Flash call identifies the bowler regardless of setting. No overfitting to one video.

### Upload Series Order

| Order | Technique | Hook | Why this position |
|-------|-----------|------|-------------------|
| **1st** | **X-Factor** | "Where does pace come from?" | Establishes channel. Instant visual comprehension. Steyn comparison = shareability. |
| **2nd** | **Kinogram** | "Your entire action in one frame" | Visual "wow" — gets screenshot-shared. Builds on audience from #1. Nobody else does this for cricket. |
| **3rd** | **Spine Gauge** | "Is your action destroying your back?" | Fear/health drives engagement. Parents tag coaches. Creates discussion in comments. |
| **4th** | **Waterfall** | "This is why fast bowlers are fast" | Science-meets-sport. The whip animation is mesmerizing. Attracts the biomechanics/coaching audience. |
| **5th** | **Goniogram** | "Is this action legal?" | ICC controversy bait. Apply to Murali, Narine, Bumrah = instant debate. Coaching utility. |
| **6th** | **Portrait** | "Every bowler has a fingerprint" | Deepest concept. By now the audience understands the visual language. The signature loop comparison = the DNA match feature. |

### Reasoning Framework

Each video was evaluated on:

- **Instant comprehension** — can someone who's never watched cricket understand the visual in 2 seconds?
- **Share trigger** — does the viewer tag someone, screenshot it, or argue in comments?
- **Technical confidence** — can we deliver v1.0.0 quality (80-point checklist, grade S) today?
- **Generality** — does it work on any random bowling clip, or only specific setups?
- **Content moat** — is anyone else doing this? (No. Nobody in cricket content creates these visualizations from standard video.)

### Quality Gate

No video ships until it passes the 80-point quality gate (see `xfactor_v100_quality_gate.md`). The bar is ESPN broadcast quality. If it wouldn't look right on Sky Sports, it's not v1.0.0.

### Validation Plan

After v1.0.0 on the 3-sec nets clip:
1. Test on 5 diverse clips (different camera angles, indoor/outdoor, different bowlers)
2. Run on a high-quality Dale Steyn clip — the output must show elite separation (~40°+)
3. If all pass → upload to YouTube
