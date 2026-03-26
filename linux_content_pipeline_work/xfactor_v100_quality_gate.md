# X-Factor v1.0.0 Quality Gate

Source: `docs/video_quality_checklist.md` (75 points). Grade S (100%) required for v1.0.0 upload.

## A. RESOLUTION & FORMAT (7 checks)

- [ ] A1. Output is exactly 1080x1920 (9:16 portrait)
- [ ] A2. H.264 codec, MP4 container
- [ ] A3. 30fps constant frame rate
- [ ] A4. Bitrate >= 6 Mbps
- [ ] A5. Duration between 15s and 60s
- [ ] A6. No black frames at start or end
- [ ] A7. File size under 100MB

## B. FIRST FRAME / HOOK (6 checks)

- [ ] B1. First frame is visually striking — would you stop scrolling?
- [ ] B2. Hook text appears within first 0.5s
- [ ] B3. Hook is readable at phone size (minimum 48px font equivalent)
- [ ] B4. No blank/black/loading frame at start — action begins immediately
- [ ] B5. Bowling action is visible in frame 1
- [ ] B6. Color contrast: text readable against video background

## C. OVERLAY DESIGN — LINES & SKELETON (10 checks)

- [ ] C1. Hip line clearly distinct from shoulder line (pink vs cyan)
- [ ] C2. Line colors pop against ALL backgrounds (dark & light areas)
- [ ] C3. Line width 3-5px at 1080p
- [ ] C4. Lines extend 20-30% beyond joints
- [ ] C5. Joint dots have white border (1.5-2px)
- [ ] C6. Skeleton is subtle — 30-40% opacity, NOT competing with hip/shoulder lines
- [ ] C7. Lines track the bowler smoothly — no jitter, no frame-to-frame jumping
- [ ] C8. Lines disappear gracefully when landmarks lose visibility (fade, don't snap)
- [ ] C9. At peak separation, lines are maximally diverged and visually dramatic
- [ ] C10. No overlay elements obscure the bowler's face or key body parts

## D. TYPOGRAPHY & TEXT (9 checks)

- [ ] D1. Font is clean sans-serif (Liberation Sans, DejaVu Sans — NOT default bitmap)
- [ ] D2. All text has dark pill/shadow behind it — readable on any background
- [ ] D3. Pill backgrounds rounded (border-radius >= pill height / 2)
- [ ] D4. Pill opacity 55-70% black
- [ ] D5. Angle numbers use consistent digit width (no jumping)
- [ ] D6. Text size hierarchy: angle (large 32px+) > phase label (medium 20px+) > legend (small 16px+)
- [ ] D7. No text overlaps other text
- [ ] D8. No text cut off by screen edges (minimum 16px safe margin)
- [ ] D9. Text appears/disappears with subtle transition

## E. ANIMATION & MOTION (8 checks)

- [ ] E1. Slow-motion is smooth — no stuttering
- [ ] E2. Speed transitions (1x to 0.25x) have brief ramp
- [ ] E3. Freeze frame has subtle pulse/flash when it locks
- [ ] E4. Angle number animates smoothly as separation changes
- [ ] E5. Phase label transitions use slide or fade
- [ ] E6. "PEAK X-FACTOR" badge has entrance animation
- [ ] E7. End card fades in
- [ ] E8. Pacing feels rhythmic — each segment breathes

## F. COLOR SCIENCE (7 checks)

- [ ] F1. Hip line: warm pink/magenta (#FF69B4)
- [ ] F2. Shoulder line: cool cyan/turquoise (#00CED1)
- [ ] F3. Two colors on opposite sides of color wheel (warm vs cool)
- [ ] F4. Separation angle number: white with dark shadow
- [ ] F5. Peak badge uses accent color
- [ ] F6. Verdict card uses brand dark background (#0D1117) with white text
- [ ] F7. No neon/garish colors — premium sports broadcast palette

## G. COMPOSITION & LAYOUT (8 checks)

- [ ] G1. Bowler centered or rule-of-thirds positioned
- [ ] G2. Portrait crop keeps bowler in frame throughout
- [ ] G3. No important content in top 10% or bottom 10% (Instagram UI covers these)
- [ ] G4. Angle number positioned near torso (contextually placed)
- [ ] G5. Phase label top-center, consistent across frames
- [ ] G6. Legend bar bottom of frame, outside action area
- [ ] G7. At most 3-4 overlay elements visible simultaneously
- [ ] G8. Negative space respected — video breathes

## H. PACING & STRUCTURE (8 checks)

- [ ] H1. Cold open (full speed, no overlay) is 1-2s max
- [ ] H2. Slow-mo analysis is longest segment (50-60% of total)
- [ ] H3. Freeze at peak holds exactly 2-3s
- [ ] H4. Verdict card 2-3s max
- [ ] H5. End card 1s max
- [ ] H6. Every second earns its place — no filler
- [ ] H7. Peak separation reveal lands between 40-60% of video
- [ ] H8. Rewatchable — viewer wants to see details again

## I. CONTENT & INSIGHT (6 checks)

- [ ] I1. Insight is SPECIFIC — "28° separation at front foot contact"
- [ ] I2. Non-cricketer understands the visual (two lines diverging = power)
- [ ] I3. Serious bowler learns something applicable
- [ ] I4. Verdict text is actionable — "work on hip mobility" not "needs improvement"
- [ ] I5. Comparison scale shows full range: Untrained → Amateur → Good → Elite (with reference bowler names if applicable, but NOT hardcoded to any specific bowler)
- [ ] I6. Video answers one question: "Where does pace come from?"

## J. BRAND & POLISH (6 checks)

- [ ] J1. wellBowled.ai watermark present — bottom corner, semi-transparent
- [ ] J2. Color legend shows: pink = hips, cyan = shoulders
- [ ] J3. Consistent visual style
- [ ] J4. No visual artifacts — no encoding glitches, no half-rendered frames
- [ ] J5. Feels premium — would not look out of place on ESPN broadcast
- [ ] J6. No background person annotated at ANY point in the video

## K. PLATFORM COMPLIANCE (5 checks)

- [ ] K1. Plays correctly in video player
- [ ] K2. No copyrighted music
- [ ] K3. No watermarks from other apps
- [ ] K4. First frame is compelling at thumbnail size
- [ ] K5. Caption drafted with hashtags

## L. GENERALITY — MUST NOT OVERFIT (8 checks)

- [ ] L1. Pipeline produces correct output on ANY bowling clip (nets, match, indoor, outdoor)
- [ ] L2. Works with any camera angle (side-on, front-on, behind stumps, elevated)
- [ ] L3. Handles multiple people in frame — ONLY the bowler gets annotated
- [ ] L4. Handles clips from 2s to 10s duration without crashing or producing garbage
- [ ] L5. No hardcoded timestamps, crop regions, or bowler positions
- [ ] L6. Graceful fallback when Gemini API is unavailable (heuristics still produce usable output)
- [ ] L7. Graceful handling when MediaPipe can't detect the bowler (no overlays rather than wrong overlays)
- [ ] L8. Angle computation produces plausible values (15-60° range for real bowling) — no 130° or 0° noise

## M. SELF-REVIEW GATE (5 checks)

- [ ] M1. I (Claude) extracted and viewed frames at 0s, 25%, 50%, 75%, 100% of video
- [ ] M2. I verified end card text is readable at the image resolution I can see
- [ ] M3. I verified no background person has overlay annotations in ANY sampled frame
- [ ] M4. I verified the angle number is plausible for the bowling action shown
- [ ] M5. I ran ffprobe and confirmed resolution, codec, bitrate, duration all pass section A

## TOTAL: 93 checks. ALL must pass for v1.0.0.

## Scoring

| Grade | Pass Rate | Action |
|-------|-----------|--------|
| **S** | 93/93 (100%) | Ship it. Upload to YouTube. |
| **A** | 84-92 (90%+) | Fix failures before upload. |
| **B** | 74-83 (80%+) | Major rework needed. |
| **C** | <74 (<80%) | Not upload-ready. Back to v0.0.x. |
