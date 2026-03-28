# Speed Gradient Trail — Evaluation & Feasibility

## Priority Order

### 1. Accuracy & Reliability (MUST PASS)
- [ ] **Deterministic:** Same clip produces identical output every run (20-run test)
- [ ] **Velocity magnitudes correct:** Wrist > forearm > trunk > hips (physics law)
- [ ] **Kinetic chain sequencing correct:** Within delivery window, peaks must follow proximal-to-distal order for elite bowlers
- [ ] **No false readings:** Zero velocity on a frozen frame. No spikes on frame cuts/transitions.
- [ ] **Consistent across resolutions:** Same relative ordering on 360p, 480p, 720p of same clip
- [ ] **Consistent with/without Gemini:** Heuristic fallback produces same velocities as Flash-guided

### 2. Visual Impact (MUST WOW)
- [ ] **Instantly understandable:** Viewer sees blue→red and gets "fast vs slow" in 1 second
- [ ] **Mesmerizing motion:** The color flowing up the body during delivery is satisfying to watch
- [ ] **Clean overlay:** Colored skeleton doesn't clutter the video. Background dimmed enough to read colors.
- [ ] **Readable at phone size:** Color difference between joints is visible on a 6-inch screen
- [ ] **Not garish:** Color palette is premium sports broadcast, not neon cartoon
- [ ] **The "aha" moment:** Viewer sees their wrist barely glowing while Steyn's blazes red

### 3. Generality (MUST WORK ON ANY CLIP)
- [ ] **Broadcast angle (elevated behind):** Works — velocity is mostly camera-independent
- [ ] **Side-on nets:** Works — this is the easiest angle
- [ ] **Phone-filmed amateur:** Works — any angle where MediaPipe detects the person
- [ ] **Multiple people in frame:** Only the bowler is colored (tracker isolates)
- [ ] **Different lighting:** Indoor nets, outdoor day, floodlit night match
- [ ] **Different bowler sizes:** Short bowler, tall bowler — normalized velocity handles both
- [ ] **Comparison:** Amateur's gradient vs Steyn's gradient side-by-side tells the whole story

## Feasibility Assessment

### What is proven
- MediaPipe pose detection: works reliably on bowling clips (proven in X-Factor)
- Velocity computation: deterministic, physics-correct magnitudes
- Bowler isolation: Gemini Flash ROI + tracker (proven in X-Factor)
- Video composition: title → slo-mo → freeze → verdict → end (proven)

### What needs validation
- Color rendering performance at 30fps (Pillow per-frame may be slow)
- Delivery window detection from velocity data alone (alternative to phase timing)
- Kinetic chain sequencing verdict accuracy across 5+ bowlers

### What is honestly limited
- Absolute velocity in m/s: NOT possible without camera calibration
- Depth-direction velocity: LOST in 2D projection (joints moving toward/away from camera)
- Very fast motion (blur): MediaPipe may lose tracking at 150+ km/h real speed
- The comparison is RELATIVE — "your wrist is 60% of Steyn's peak" not "your wrist is 12 m/s"

### Mitigation
- Use normalized velocity (0-1 relative to clip max) not absolute m/s
- Show percentage of peak: "Your wrist reaches 62% of max chain velocity"
- For comparison videos: normalize each bowler to their OWN max so colors are comparable
- Add disclaimer: "Relative speed measurement from video. Actual speeds may vary."

## Test Matrix

| Test | Clip | Expected | Pass Criteria |
|------|------|----------|---------------|
| Determinism | Steyn ×20 | Identical | diff = 0.000 |
| Determinism | Bumrah ×20 | Identical | diff = 0.000 |
| Determinism | Nets ×20 | Identical | diff = 0.000 |
| Velocity order | Steyn | Wrist > Forearm > Trunk > Hips | Correct ranking |
| Velocity order | Bumrah | Wrist > Forearm > Trunk > Hips | Correct ranking |
| Sequencing | Steyn (windowed) | Hips → Trunk → Arm → Wrist | ≥4/5 correct order |
| Visual | Phone screenshot | Colors distinguishable | Non-cricket viewer confirms |
| Generality | Broadcast angle | Colors render correctly | No artifacts |
| Generality | Amateur phone clip | Bowler detected, colors correct | MediaPipe finds person |
