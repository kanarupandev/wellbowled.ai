# Analysis Techniques — HOW to Visualize

> The values doc says WHAT to measure. This doc says HOW to show it.
> Each technique is a visual method built on MediaPipe's 33 landmarks.

---

## A. Joint Isolation & Tracking

### A1. Single Joint Trail (Wrist Flow)
Track ONE joint across the entire delivery. Fade out everything else.
- **Wrist trail:** Run-up → loading → release. The arc IS the bowling action.
- **Elbow trail:** Shows how the arm unfolds. Kink = flex = illegal?
- **Head trail:** Stable head = accuracy. Bouncing head = control issue.
- Draw as a glowing line with color gradient (cool→warm as speed increases).
- Fading tail: last 10 frames visible, older frames fade to transparent.

### A2. Joint Pair Tracking
Track two joints and the line between them.
- **Shoulder-to-wrist:** The bowling arm as a single lever. Length changes = flex.
- **Hip-to-hip line:** Shows pelvic rotation in real time.
- **Shoulder-to-shoulder line:** Shows chest rotation.
- When hip line and shoulder line diverge = hip-shoulder separation visualized.

### A3. Joint Speed Heatmap
Color each joint by its velocity at that frame.
- Slow joints = blue/cool. Fast joints = red/hot.
- At release: wrist is blazing red, hips are cool. Shows the whip effect.
- Beautiful and instantly intuitive — no numbers needed.

---

## B. Angle Visualization

### B1. Live Angle Arc
Draw a semi-transparent arc at a joint showing the measured angle.
- **Front knee:** Arc between thigh and shin. "162°" overlaid.
- **Bowling elbow:** Arc at elbow. "8°" (legal) or "19°" (red, illegal).
- **Trunk lateral flex:** Arc from vertical to trunk line. "23°" = risky range.
- Arc color matches the verdict: green if optimal, amber if borderline, red if risky.
- Pulse/highlight when angle crosses a threshold.

### B2. Angle Timeline Graph
Small overlay graph showing angle changing over time during delivery.
- X-axis = time (0 to delivery duration). Y-axis = angle.
- Horizontal line showing optimal range.
- Curve goes green inside optimal, red outside.
- "Your knee collapses at 0.12s" — visible as the curve drops.

### B3. Multi-Angle Dashboard
Show 3-4 key angles simultaneously at their joint positions.
- Front knee + bowling elbow + trunk flex + shoulder rotation
- All with arcs and numbers, all color-coded.
- The "full biomechanics X-ray" look — maximum credibility.

---

## C. Alignment & Classification

### C1. Hip Line vs Shoulder Line
Draw two horizontal lines through the body:
- **Pink/magenta line:** Through left hip → right hip
- **Cyan line:** Through left shoulder → right shoulder
- When lines are parallel: front-on or side-on (both aligned).
- When lines diverge: the X-factor / hip-shoulder separation.
- Animate both lines through the delivery — shows the rotation sequence.

### C2. Action Type Classification Label
Classify and LABEL the bowling action:
- **SIDE-ON:** Hips and shoulders aligned, pointing down the pitch at back foot contact.
- **FRONT-ON:** Hips and shoulders aligned, chest facing the batsman.
- **SEMI-OPEN:** Between the two. Most modern fast bowlers.
- **MIXED ACTION:** Hips front-on but shoulders side-on (or vice versa). INJURY RISK.
- Burn the label into the frame with a colored badge:
  - Side-on / Front-on = neutral (white/blue badge)
  - Semi-open = normal (green badge)
  - Mixed = red badge with warning icon
- Classification based on angle between hip line and pitch direction at back foot contact.

### C3. Spine Alignment Line
Draw a line from mid-hip to mid-shoulder (the trunk).
- Vertical = upright. Tilted = lateral flexion.
- Overlaid angle from vertical: "Trunk tilt: 34°"
- At release, excessive tilt = lower back stress.
- Show the tilt change from loading to release as an animation.

### C4. Bowling Crease Reference Line
Draw a horizontal line where the bowling crease is.
- Front foot position relative to crease = no-ball check.
- Release point height measured from this baseline.
- Gives spatial context — the skeleton floating in space now has a ground reference.

---

## D. Comparison Techniques

### D1. Ghost Overlay
Two skeletons on the same frame:
- Current bowler in full color.
- Reference bowler (e.g., Bumrah) as a semi-transparent ghost.
- Aligned at the same phase (release point).
- Differences immediately visible: "Your arm is 15° lower at release."

### D2. Split Screen Sync
Side-by-side videos, both with skeleton overlay, synced to the same phase.
- Left: Bowler A. Right: Bowler B.
- Phase labels synced. Same moment, different bodies.
- "Starc vs Archer at front foot contact — look at the knee difference."

### D3. Before/After Overlay
Same bowler, two sessions.
- Session 1 skeleton in amber. Session 2 skeleton in green.
- Delta callouts: "Front knee: 148° → 163° (+15°)"
- The proof that analysis → improvement.

### D4. Percentile Bar
Where does this value sit in the population?
- Bar graph: "Your stride length is in the 72nd percentile of fast bowlers."
- Shows context — is 2.3m stride good or bad? The bar tells you.

---

## E. Flow & Energy Visualization

### E1. Kinetic Chain Pulse
Animated glow traveling up the body during delivery:
- Ground → ankle → knee → hip → trunk → shoulder → elbow → wrist → ball
- Speed of the pulse = speed of energy transfer.
- Break in the pulse = break in the kinetic chain = pace leak.
- Gorgeous visual — looks like electricity flowing through the body.

### E2. Motion Blur Trail
Full skeleton with motion blur on the fast-moving limbs.
- Slow limbs = sharp. Fast limbs = blurred.
- At release: wrist/hand is a blur, legs are sharp.
- Instantly communicates which parts of the body are doing the work.

### E3. Rotation Circles
Draw circular arcs showing the rotation path of key segments.
- Shoulder rotation: circle around the spine axis.
- Hip rotation: circle around the vertical axis.
- Arm rotation: circle around the shoulder joint.
- Radius of circle = range of motion. Gap in circle = incomplete rotation.

---

## F. Labeling & Classification

### F1. Bowler Profile Card
On-screen card with bowler classification:
```
┌──────────────────────────┐
│  JASPRIT BUMRAH    🇮🇳   │
│  Fast  ·  Semi-Open      │
│  Right Arm Over           │
│  145.2 kph avg            │
│  87% DNA: Wasim Akram     │
└──────────────────────────┘
```
- 2-3 seconds at start of video. Sets context.

### F2. Phase Verdict Badges
As each phase completes, a badge appears:
- ✅ Run-Up: GOOD
- ⚠️ Loading: NEEDS WORK — late shoulder rotation
- ✅ Release: GOOD
- ❌ Follow-Through: INJURY RISK — incomplete deceleration
- These accumulate on screen → by end, you see the full report card.

### F3. Micro-Insight Text Pops
1-line insights that pop on screen at the relevant moment:
- "Front knee locked — textbook brace" (as front foot lands)
- "Elbow flex: 8° — legal action" (at release)
- "Mixed action detected — injury risk" (at back foot contact)
- Timed to appear WITH the skeleton at that exact moment.
- Font: clean sans-serif, white on dark pill. 1.5s display time.

---

## Production Sequence (Per Video)

1. **0-1s:** Bowler profile card (F1) + full-speed clip
2. **1-3s:** Replay at 0.5x with full skeleton overlay (A: joints + sticks)
3. **3-8s:** Phase-by-phase with:
   - Isolated joint trails (A1/A2) for the key insight
   - Angle arcs (B1) on the critical joints
   - Action type label (C2)
   - Micro-insight text pops (F3)
4. **8-12s:** Verdict badges accumulate (F2)
5. **12-15s:** Overall rating + DNA match + "Fix this one thing"

**Total: 15-20 seconds for a tight reel.**
Scale to 60s by adding comparisons (D1/D2) and deeper angle analysis (B2/B3).
