# Top 30 Visual Analysis Techniques — Ranked by Audience Engagement

> Proper biomechanics & broadcast names. Ordered by what makes people
> stop scrolling, save the post, and tag their mates.

---

## #1 — Kinogram (Stroboscopic Sequence)
**Standard name:** Kinogram / Stroboscopic image
Multiple exposures of the bowler composited into ONE frame — every position from run-up to follow-through visible simultaneously. The entire action frozen in a single image.
- **Why it hooks:** The single most iconic sports biomechanics visual. One image tells the whole story. Screenshot-friendly = shares.
- **Cricket use:** Full delivery stride in one frame. Show 8-10 positions of the bowler overlaid with decreasing opacity.
- **Difficulty:** Medium — composite sampled frames with transparency blend.

## #2 — Pose Skeleton Overlay (Stick Figure Diagram)
**Standard name:** Stick figure diagram / Skeletal wireframe overlay
Color-coded skeleton (joints + bones) overlaid on live video in real time, shifting colors by biomechanical quality per phase.
- **Why it hooks:** "X-ray vision" — viewers see what was invisible. The defining visual of the entire channel. No one else has this on cricket.
- **Cricket use:** Green/amber/red bones through run-up → loading → release → follow-through.
- **Difficulty:** Done — this is what we already build.

## #3 — Joint Trajectory Trace (Motion Path)
**Standard name:** Joint trajectory / Endpoint path trace
Track ONE joint across time, drawing its path as a glowing trail. Everything else fades.
- **Why it hooks:** Beautiful. Mesmerizing. The bowling arm arc looks like light painting. Makes speed VISIBLE.
- **Cricket use:** Wrist trajectory from loading through release. Shows the whip. Also: head path (stability check), front foot path (stride visualization).
- **Difficulty:** Low — sample joint position per frame, draw polyline with gradient.

## #4 — Goniogram (Live Angle Arc)
**Standard name:** Goniometric overlay / Joint angle diagram
Semi-transparent arc drawn at a joint showing the exact measured angle with number overlay.
- **Why it hooks:** Numbers = credibility. "162°" next to the front knee makes it look like actual sports science. Shareable because it teaches.
- **Cricket use:** Front knee brace angle, bowling elbow flexion (illegal action check), hip-shoulder separation angle.
- **Difficulty:** Low — compute angle from 3 landmarks, draw arc + text.

## #5 — Elbow Legality Gauge (Flexion Meter)
**Standard name:** Elbow flexion gauge / ICC compliance indicator
Speedometer-style arc around the bowling elbow. Green zone (0-15°), red zone (>15° = illegal). Needle shows real-time flex.
- **Why it hooks:** THE most controversial metric in cricket. "Is this action legal?" Guaranteed comments, debates, rage-shares.
- **Cricket use:** Every bowler ever suspected — Murali, Ajmal, Narine, Hasnain. Instant engagement bait.
- **Difficulty:** Low — elbow angle from 3 landmarks + gauge graphic.

## #6 — Action Type Classification (Bowling Action Label)
**Standard name:** Bowling action classification / Alignment categorization
Label burned into the frame: SIDE-ON / FRONT-ON / SEMI-OPEN / MIXED ACTION.
- **Why it hooks:** Every cricketer argues about action types. Definitive classification with visual proof = debate fuel.
- **Cricket use:** Compare hip-line angle vs shoulder-line angle at back foot contact. Mixed = red warning badge + injury alert.
- **Difficulty:** Medium — needs hip/shoulder line angles at specific phase.

## #7 — Hip-Shoulder Separation (X-Factor Overlay)
**Standard name:** Pelvic-shoulder separation angle / X-factor
Two colored lines — one through hips (pink), one through shoulders (cyan) — showing the rotational lag that generates pace.
- **Why it hooks:** The "secret" of fast bowling pace. Every coach knows it but most fans have never SEEN it. Educational + impressive.
- **Cricket use:** Animate through delivery. Show peak separation with number: "47° — elite range." Directly correlates to speed.
- **Difficulty:** Low — two lines from hip/shoulder landmarks, measure angle between.

## #8 — Speed Gradient Trail (Velocity Heatmap on Joints)
**Standard name:** Velocity magnitude mapping / Speed color gradient
Each joint colored by its instantaneous velocity — blue (slow) to red (fast). At release, the wrist blazes while the hips are cool.
- **Why it hooks:** Instantly intuitive. No numbers needed — the color IS the information. Beautiful and unique.
- **Cricket use:** Shows the whip effect. Energy flowing from ground up. Makes the kinetic chain visible as COLOR.
- **Difficulty:** Medium — compute per-joint velocity between frames, map to color scale.

## #9 — Ghost Overlay (Dual Skeleton Comparison)
**Standard name:** Template matching overlay / Reference pose superimposition
Two skeletons on the same frame — current bowler in full color, famous bowler as semi-transparent ghost.
- **Why it hooks:** "How close are you to Bumrah?" Side-by-side proof. Differences immediately visible. The ultimate comparison format.
- **Cricket use:** Align at same phase (release point). Show where joints diverge. "Your arm is 15° lower."
- **Difficulty:** High — needs reference data + phase alignment.

## #10 — Kinetic Chain Pulse (Energy Transfer Animation)
**Standard name:** Kinetic chain visualization / Sequential segment activation
Animated glow traveling up the body: ground → ankle → knee → hip → shoulder → elbow → wrist → ball.
- **Why it hooks:** Looks like electricity flowing through the body. When the chain breaks = where pace is lost. Visually stunning.
- **Cricket use:** Complete chain = effortless speed. Break in chain = "this is why you're stuck at 120 kph."
- **Difficulty:** High — needs velocity sequencing across segments.

## #11 — Stride Length Ruler
**Standard name:** Stride length measurement / Delivery stride overlay
Horizontal line from back foot to front foot with measurement, plus body height percentage.
- **Why it hooks:** Dead simple. Every bowler can immediately measure their own. "Is my stride too long?"
- **Cricket use:** "2.4m — 91% of body height. Optimal is 80-100%." Landing marker on the pitch.
- **Difficulty:** Low — distance between ankle landmarks + reference calibration.

## #12 — Pitch Map (Release Point Cluster)
**Standard name:** Pitch map / Release point distribution
Across multiple deliveries, plot where the ball is released as colored dots forming a heat cluster.
- **Why it hooks:** Borrowed from Hawk-Eye — every cricket fan already understands this visual. Tight cluster = consistent.
- **Cricket use:** "Bumrah's release point consistency in death overs." Analysts LOVE this.
- **Difficulty:** Medium — needs multi-delivery data + calibrated coordinates.

## #13 — Slow-Motion Phase Breakdown (Temporal Decomposition)
**Standard name:** Phase decomposition / Temporal segmentation analysis
Full speed → 0.25x with skeleton → freeze at critical moment → resume. Phase labels appear as transitions.
- **Why it hooks:** Dramatic. The speed contrast creates wow. "This happens in 0.4 seconds — now watch what the body actually does."
- **Cricket use:** Every delivery. The fundamental rhythm of the content.
- **Difficulty:** Low — just editing/compositing technique.

## #14 — Spine Alignment Line (Trunk Verticality)
**Standard name:** Trunk lateral flexion line / Spinal alignment indicator
Line from mid-hip to mid-shoulder showing trunk angle from vertical. Degree overlay.
- **Why it hooks:** Injury content = saves + shares. "Your back is tilting 34° — that's the danger zone."
- **Cricket use:** Excessive lateral flexion at release = lumbar stress fracture risk. THE injury mechanism for fast bowlers.
- **Difficulty:** Low — midpoint of hips, midpoint of shoulders, angle from vertical.

## #15 — Phase Grade Cards (Scorecard Overlay)
**Standard name:** Phase performance grading / Segment quality index
Letter grade (A+ to D) appearing as badges after each phase. Accumulate on screen for full report card.
- **Why it hooks:** Gamification. "What would YOU get?" Viewers mentally grade themselves. Drives "do me next" comments.
- **Cricket use:** Run-Up: A | Loading: B+ | Release: A- | Follow-Through: C
- **Difficulty:** Low — grade assignment from expert analysis, render as badges.

## #16 — Beehive (Pass Point Visualization)
**Standard name:** Beehive plot / Ball pass distribution
Where the ball passes the batsman/stumps. Dots color-coded by outcome (hitting stumps, going over, missing).
- **Why it hooks:** Another Hawk-Eye standard. Fans recognize it instantly. Shows a bowler's accuracy visually.
- **Cricket use:** "Starc's yorker accuracy — 7/10 hitting the base of stumps." Variable bounce visualization.
- **Difficulty:** High — needs ball tracking, not just bowler pose.

## #17 — Center of Mass Trajectory (CoM Path)
**Standard name:** Center of mass trajectory / Whole-body CoM trace
Dot tracking the body's center of mass through the entire delivery stride.
- **Why it hooks:** Smooth line = efficient bowler. Jagged line = wasted energy. Simple visual, profound insight.
- **Cricket use:** Compare elite (smooth curve) vs amateur (jerky path). "See why Steyn looked effortless?"
- **Difficulty:** Medium — compute weighted midpoint of all landmarks per frame.

## #18 — Wrist Snap Speedometer (Release Velocity Gauge)
**Standard name:** Angular velocity gauge / Wrist speed indicator
Speedometer dial on the wrist showing velocity building through delivery, peaking at release.
- **Why it hooks:** The final multiplier in the kinetic chain. "28 m/s wrist speed at release." Animated acceleration is satisfying.
- **Cricket use:** Animate: slow buildup → explosive peak at release. Compare wrist-spinners (higher) vs pace bowlers (different profile).
- **Difficulty:** Medium — compute wrist velocity between frames.

## #19 — Bowling Arm Arc (Arm Rotation Sweep)
**Standard name:** Arm circumduction arc / Upper limb rotation path
Full circle drawn showing the bowling arm's rotation path around the shoulder.
- **Why it hooks:** Shows the complete windmill. Gap in the circle = incomplete follow-through. Round-arm vs over-arm visible.
- **Cricket use:** "Malinga's arc is at 8 o'clock. Bumrah's at 11 o'clock. Same speed, completely different geometry."
- **Difficulty:** Low — wrist trajectory relative to shoulder, draw circular arc.

## #20 — Split-Screen Sync (Dual Video Comparison)
**Standard name:** Synchronized dual-view comparison / Phase-locked comparison
Two videos side by side, both with skeleton overlay, synced to the same bowling phase.
- **Why it hooks:** "Who has the better action?" Immediate visual debate. Infinite combinations of bowlers.
- **Cricket use:** "Starc vs Archer at front foot contact." IPL matchups = built-in audience.
- **Difficulty:** Medium — phase detection + temporal alignment.

## #21 — Force Vector Arrows (Ground Reaction Visualization)
**Standard name:** Ground reaction force vector / Force plate overlay
Arrows at contact points showing direction and magnitude of force.
- **Why it hooks:** Makes invisible physics visible. "280% body weight through the front leg" — visceral understanding of the impact.
- **Cricket use:** Front foot landing force, direction of momentum transfer. Why injuries happen.
- **Difficulty:** High — force estimation from pose kinematics (approximation without force plate).

## #22 — Angular Velocity Graph (Joint Speed Timeline)
**Standard name:** Angular velocity-time curve / Joint kinematics graph
Small overlay graph: X = time, Y = joint angular velocity. Shows how fast a joint is rotating at each moment.
- **Why it hooks:** The "science" look. Builds credibility. The curve tells the story — peak = release, dip = deceleration.
- **Cricket use:** Shoulder internal rotation velocity, elbow extension velocity. "Peak: 7000°/s — that's near the human limit."
- **Difficulty:** Medium — compute angular velocity from joint angles across frames.

## #23 — Wagon Wheel (Delivery Outcome Map)
**Standard name:** Wagon wheel / Scoring shot distribution
Radial plot from bowler's end showing where each delivery went — wickets, dots, boundaries.
- **Why it hooks:** Most recognized cricket graphic in the world. Every fan knows it from TV. Instant familiarity.
- **Cricket use:** Overlay on a bowler's spell analysis. "Bumrah's death over spell — 4 dots, 1 wicket, 1 wide."
- **Difficulty:** High — needs outcome data, not just biomechanics.

## #24 — Before/After Delta Overlay (Improvement Visualization)
**Standard name:** Pre-post intervention comparison / Longitudinal technique overlay
Same bowler, two sessions. Session 1 skeleton in amber, Session 2 in green. Delta callouts.
- **Why it hooks:** PROOF that analysis → improvement. "Front knee +12° in 2 weeks." Drives app downloads.
- **Cricket use:** Coaching content. The transformation story. "Here's what 3 sessions of biomechanics coaching did."
- **Difficulty:** Medium — needs two sessions of the same bowler + phase alignment.

## #25 — Release Height Marker (Vertical Reference)
**Standard name:** Release point height / Ball release elevation
Vertical line from ground to wrist at release with height measurement.
- **Why it hooks:** Quantifies the tall-bowler advantage. "Archer releases at 2.3m. That's why it bounces."
- **Cricket use:** Compare release heights across bowlers. Explains bounce and difficulty.
- **Difficulty:** Low — wrist Y-coordinate at release + calibrated height reference.

## #26 — Mixed Action Alert (Injury Risk Classification)
**Standard name:** Mixed bowling action detection / Counter-rotation hazard flag
Red warning overlay when hip alignment and shoulder alignment conflict at back foot contact.
- **Why it hooks:** FEAR. Every fast bowler's nightmare. "Mixed action = stress fracture waiting to happen."
- **Cricket use:** Flash red, show the hip vs shoulder lines diverging, explain the risk. Parents share this.
- **Difficulty:** Medium — compare hip-line and shoulder-line angles at back foot contact phase.

## #27 — Segment Angular Momentum (Rotation Contribution)
**Standard name:** Segmental angular momentum / Rotation contribution breakdown
Bar chart showing how much each body segment contributes to total rotation.
- **Why it hooks:** "Your trunk generates 45% of your rotation. Bumrah's generates 62%. That's the difference."
- **Cricket use:** Shows what to train. If arm contributes too much = arm-dominant = injury risk.
- **Difficulty:** High — needs segment mass estimation + angular velocity.

## #28 — Bowling Crease Reference Line (Spatial Anchor)
**Standard name:** Crease reference overlay / Spatial calibration line
Horizontal line marking the bowling crease. Front foot position relative to it.
- **Why it hooks:** No-ball check. "Was that legal?" Every DRS moment in history was about this line.
- **Cricket use:** Ground reference that makes all other measurements meaningful. Spatial context.
- **Difficulty:** Medium — needs crease detection or manual calibration.

## #29 — Symmetry Score (Bilateral Comparison)
**Standard name:** Bilateral symmetry index / Left-right movement symmetry
Percentage showing how symmetrical the body moves during delivery.
- **Why it hooks:** Asymmetry = injury risk + inefficiency. Simple number, clear implication.
- **Cricket use:** "76% symmetry — your left side is doing less work." One number that captures a lot.
- **Difficulty:** Medium — compare corresponding left/right joint kinematics.

## #30 — 3D Rotation Viewer (Multi-Angle Reconstruction)
**Standard name:** 3D pose reconstruction / Multi-view visualization
Rotate the skeleton in 3D space — viewers can see the action from any angle.
- **Why it hooks:** Futuristic. "We built a 3D model of your bowling action." Pure tech-flex content.
- **Cricket use:** Show the action from behind, from side, from above. Each angle reveals different mechanics.
- **Difficulty:** Very high — needs 3D pose estimation or multi-camera input.

---

## Quick Reference: Engagement Tiers

### Tier S — Maximum Virality (use in EVERY video)
1. Kinogram
2. Pose Skeleton Overlay
3. Joint Trajectory Trace
4. Goniogram
5. Elbow Legality Gauge

### Tier A — High Engagement (rotate across videos)
6–10: Action Classification, X-Factor, Speed Gradient, Ghost Overlay, Kinetic Chain Pulse

### Tier B — Strong Content (series-specific)
11–20: Stride Ruler, Pitch Map, Phase Breakdown, Spine Line, Grade Cards, Beehive, CoM, Wrist Speedo, Arm Arc, Split-Screen

### Tier C — Authority Building (deep content)
21–30: Force Vectors, Angular Velocity Graph, Wagon Wheel, Before/After, Release Height, Mixed Action Alert, Angular Momentum, Crease Line, Symmetry Score, 3D Viewer

---

## The Formula

**Every 20-60s clip uses 3-5 techniques from this list.**

Frame 1: Kinogram (the thumbnail, the hook)
Body: Skeleton overlay + 2-3 targeted techniques from Tier A/B
Close: Grade cards or improvement callout

That's the content. That's the channel.
