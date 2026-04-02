# v0.0.1 Review — All 6 Technique Pipelines

Reviewed 2026-03-26 against 3-sec nets bowling clip.

## Common Issues (all 6 pipelines)

1. **End card text is unreadable** — "wellBowled.ai" and "Cricket biomechanics, visualized" at ~12px on 1920px canvas. Must be 36-48px minimum.
2. **Blurry fonts** — no anti-aliasing, wrong rendering method. Need Pillow with proper FreeType fonts, not OpenCV putText.
3. **Background person annotated** — no bowler isolation. Need Gemini Flash ROI or delivery-window overlay gating.
4. **No delivery-window gating** — overlays appear during approach/walk-back when pose is unreliable.
5. **2D projection noise** — angles inflated from side-on camera. Need smoothing + capping + minimum-spread filters.
6. **Graph/bar labels too small** — legend text, axis labels, phase pills all unreadable at phone size.
7. **No verdict card with technique-specific insight** — all end with generic dark card.

## Per-Pipeline Review

### 1. X-Factor (24.3s)
- Hip/shoulder lines work on the bowler during delivery
- Delivery-window gating added (linux version) — approach/post-delivery clean
- Freeze card with "PEAK X-FACTOR 28°" readable
- Verdict card has Steyn/Lee comparison bar — needs Untrained baseline added
- **Best candidate for v1.0.0 today**

### 2. Kinogram (11.6s)
- 7 color-coded figures overlay on single frame
- CRITICAL: figures stack on top of each other — unintelligible
- CRITICAL: bystander skeleton included
- Too dark (25% background brightness)
- Phase labels at bottom too small
- **Highest ceiling but needs 2 critical fixes before usable**

### 3. Goniogram (22.3s)
- Red arcs at elbow, knee, shoulder joints
- All arcs are red — looks like everything is wrong (should be color-coded by quality)
- Text at bottom completely unreadable
- Peak knee angle 180° — bogus (should be closer to 0-50°)
- Background person visible
- **Solid coaching tool but not viral content**

### 4. Velocity Waterfall (22.3s)
- Split: video top, velocity curves bottom
- Video portion too small (~40% of frame)
- Graph labels and legend unreadable
- 5 colored curves show sequential peaks — concept works
- "ELITE SEQUENCING" verdict detected correctly
- Background person in video portion
- **Needs bigger video, readable labels. Good for video #3-4 in series**

### 5. Phase Portrait (22.3s)
- Split: video top, parametric loop bottom
- Orange/pink loop traces coordination path
- Loop is noisy/chaotic (2D projection + possible wrong person tracked)
- "Loop tightness: 0.41 (spread)" — needs reference loops to be meaningful
- Abstract concept, needs explanation
- **Best as late-series content. Needs famous bowler reference loops**

### 6. Spine Stress Gauge (22.3s)
- Green skeleton overlay on bowler — looks good
- Risk bar at bottom (green→yellow→red) completely unreadable
- 147.9° combined stress, "HIGH RISK" — bogus from 2D projection
- Real thresholds: safe <25°, caution 25-35°, danger >40°
- **Compelling concept (injury prevention) but irresponsible with wrong numbers**

## Priority Ranking for v1.0.0

1. **X-Factor** — 90% done, highest confidence, best first upload
2. **Kinogram** — highest wow factor but 2 critical fixes needed
3. **Waterfall** — scientifically strong, needs layout fix
4. **Goniogram** — coaching focused, needs color logic fix
5. **Spine Gauge** — needs angle accuracy fix before publishing
6. **Portrait** — needs reference database to be meaningful
