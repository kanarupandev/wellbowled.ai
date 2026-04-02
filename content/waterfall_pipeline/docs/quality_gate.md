# Velocity Waterfall v1.0.0 — Quality Gate (80 Checks)

> Every check must PASS before shipping. Grade S = 80/80.

---

## A. Resolution & Format (7)

- [ ] A1. Output exactly 1080×1920 (9:16 portrait)
- [ ] A2. H.264 codec in MP4 container
- [ ] A3. Constant 30fps
- [ ] A4. Bitrate ≥ 4 Mbps
- [ ] A5. Duration 15-35s (Instagram Reels sweet spot)
- [ ] A6. No black frames at start or end
- [ ] A7. File size < 50MB

## B. First Frame / Hook (6)

- [ ] B1. First frame is visually striking (not empty dark canvas)
- [ ] B2. Hook text readable at phone size ("Where does the WHIP come from?")
- [ ] B3. Bowler visible in frame (not too small, not cropped)
- [ ] B4. Text has dark pill/shadow behind it (legible on any background)
- [ ] B5. No overlays cluttering the cold open — raw footage only
- [ ] B6. Works as thumbnail when paused

## C. Graph Design (12)

- [ ] C1. Five distinct, visually separable curves on dark background
- [ ] C2. Curves build progressively (left-to-right, synchronized with video time)
- [ ] C3. Glow effect visible on each curve (not just flat lines)
- [ ] C4. Fill under curves at low alpha (area shading distinguishes overlapping curves)
- [ ] C5. Dashed vertical cursor tracks current frame position
- [ ] C6. Colored dots at cursor-curve intersections (one per segment)
- [ ] C7. Subtle grid lines visible but not distracting
- [ ] C8. Y-axis spans 0% to 120% of max velocity (headroom for wrist overshoot)
- [ ] C9. X-axis zoomed to delivery window (not wasting space on flat pre/post data)
- [ ] C10. Graph occupies bottom 30-38% of canvas
- [ ] C11. After delivery ends, graph stays frozen (complete curves visible)
- [ ] C12. No graph jitter or visual artifacts during progressive build

## D. Typography (9)

- [ ] D1. All text via Pillow (never cv2.putText) — clean anti-aliased rendering
- [ ] D2. All text has dark pill or shadow (legible on video and dark bg)
- [ ] D3. Font hierarchy clear: title (34px) > labels (17px) > legend (14px)
- [ ] D4. Consistent font family (Liberation Sans / Arial / DejaVu)
- [ ] D5. Velocity values don't jump or flicker between frames
- [ ] D6. No text overlaps video content or graph content
- [ ] D7. Minimum 16px safe margin from all edges
- [ ] D8. Legend labels match curve colors exactly
- [ ] D9. Time indicator visible and updating smoothly

## E. Skeleton & Video Overlay (8)

- [ ] E1. Faded skeleton at 30% opacity (visible but not dominant)
- [ ] E2. Active segment landmarks highlighted with colored dots (10px)
- [ ] E3. White outline on highlight dots (2px) for contrast
- [ ] E4. Skeleton only draws during delivery window (not pre/post)
- [ ] E5. Only bowler's skeleton drawn (no bystander, fielder, batsman)
- [ ] E6. Video frame properly letterboxed in top 56% of canvas
- [ ] E7. No cropping of bowler during key delivery phases
- [ ] E8. Smooth skeleton tracking (no teleporting joints)

## F. Color Science (7)

- [ ] F1. Five segment colors distinguishable at phone size
- [ ] F2. Colors progress warm→cool (proximal→distal): coral, gold, green, blue, magenta
- [ ] F3. All colors readable on dark background (#0D1117)
- [ ] F4. Verdict card uses dark bg + white/colored text (high contrast)
- [ ] F5. No neon or garish combinations
- [ ] F6. Cursor dots match their curve colors exactly
- [ ] F7. Brand teal (#006D77) consistent across all segments

## G. Velocity Computation (8)

- [ ] G1. Central difference velocity (not forward/backward only)
- [ ] G2. Savitzky-Golay smoothing applied (window=7, polyorder=2)
- [ ] G3. NaN gaps interpolated before smoothing (no holes in curves)
- [ ] G4. Velocities normalized to max wrist velocity (wrist = 1.0)
- [ ] G5. Peak detection restricted to delivery zone only
- [ ] G6. Sequencing check compares peak frame indices in correct order
- [ ] G7. Wrist landmark uses R_INDEX with R_WRIST fallback
- [ ] G8. No negative velocities (clipped to 0)

## H. Pacing & Structure (8)

- [ ] H1. Cold open ≤ 1.5s (don't waste viewer attention)
- [ ] H2. Slo-mo analysis is 50-60% of total duration
- [ ] H3. Peak freeze holds exactly 2s
- [ ] H4. Verdict card ≤ 2.5s
- [ ] H5. End card ≤ 1.5s
- [ ] H6. Every second earns its place (no dead time)
- [ ] H7. Peak wrist velocity frame appears between 40-60% of total video
- [ ] H8. Graph animation builds at readable pace (not too fast, not too slow)

## I. Verdict Card (7)

- [ ] I1. Shows peak order for all 5 segments with colored dots
- [ ] I2. Sequencing verdict in large text (ELITE / GOOD / BLOCKED)
- [ ] I3. 1-2 lines of explanation below verdict
- [ ] I4. Color matches verdict severity (green / yellow / orange-red)
- [ ] I5. Background is blurred peak frame with dark overlay (not solid black)
- [ ] I6. Brand watermark present
- [ ] I7. Readable at phone size (Instagram Stories dimensions)

## J. Brand & Polish (5)

- [ ] J1. "wellBowled.ai" appears in end card (72px teal)
- [ ] J2. Tagline "Cricket biomechanics, visualized" in end card
- [ ] J3. Small brand mark in analysis frames (bottom-right, 20px teal)
- [ ] J4. Consistent visual style with X-Factor pipeline
- [ ] J5. Would not look out of place on ESPN or Sky Sports broadcast

## K. Platform Compliance (4)

- [ ] K1. Plays correctly in QuickTime, VLC, and browser
- [ ] K2. No copyrighted music or audio
- [ ] K3. No third-party watermarks
- [ ] K4. First frame works as YouTube thumbnail (compelling, readable)

## L. Generality & Robustness (8)

- [ ] L1. Works on the nets sample clip (3_sec_1_delivery_nets.mp4)
- [ ] L2. Works on the Steyn clip (steyn_side_on_3sec.mp4) if available
- [ ] L3. Handles multiple people in scene (only bowler tracked)
- [ ] L4. Handles 2-10s clips without crashing
- [ ] L5. No hardcoded frame indices or timestamps
- [ ] L6. Graceful fallback if Gemini Flash unavailable (heuristic delivery zone)
- [ ] L7. Graceful when MediaPipe loses tracking (no overlay rather than wrong overlay)
- [ ] L8. Sequencing verdict is plausible (not always ELITE, not always BLOCKED)

---

## Self-Review Checklist (M) — Run After Every Iteration

- [ ] M1. Extract review frames at 0%, 20%, 40%, 60%, 80%, 95% — visually inspect each
- [ ] M2. Verify end card text is readable (72px brand, 36px tagline)
- [ ] M3. Verify no bystander skeleton or annotation visible
- [ ] M4. Verify graph curves are distinguishable (5 colors, fills, glow)
- [ ] M5. Run ffprobe — confirm 1080x1920, h264, 30fps, duration, bitrate
- [ ] M6. Open video in default player — watch full playback
- [ ] M7. Check verdict card — is the sequencing verdict plausible?
- [ ] M8. Check peak frame — does the freeze show the delivery moment?

---

## Scoring

| Score | Meaning |
|-------|---------|
| 80/80 | SHIP IT — upload ready |
| 75-79 | Almost — minor polish needed |
| 60-74 | Functional but not upload-ready |
| < 60 | Major issues — do not upload |

**Target: 80/80 before declaring v1.0.0.**
