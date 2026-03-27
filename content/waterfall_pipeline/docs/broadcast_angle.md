# Camera Angle Assumptions — Velocity Waterfall Pipeline

## Primary Input: Nets Session Clips

90%+ of user-generated bowling clips follow this pattern:

- **Position:** Non-striker's end, phone propped or handheld
- **Angle:** Front-on to slightly oblique (0-20° off center)
- **Distance:** 3-8m from bowler
- **Motion:** Bowler runs TOWARD camera → delivers → follows through

## What This Camera Angle Captures Well

| Measurement | Reliability | Notes |
|-------------|------------|-------|
| Vertical arm movement (y) | Excellent | Arm goes hip→overhead→follow-through, full arc visible |
| Hip/shoulder rotation | Good | Shows as apparent torso width change |
| Overall body speed | Good | Run-up velocity visible as size increase (looming) |
| Trunk lateral flexion | Moderate | Visible at release as spine tilts sideways |
| Wrist flick/snap | Moderate | Visible at top of delivery arc |

## What This Camera Angle Captures Poorly

| Measurement | Reliability | Notes |
|-------------|------------|-------|
| Lateral (x) arm position | Poor | Bowler coming straight at camera — depth is compressed |
| Absolute distances | Poor | No depth, no known scale reference |
| Front knee angle | Moderate | Foreshortened, better from side-on |
| Stride length | Poor | Needs side-on view |

## Implication for Velocity Waterfall

The kinetic chain "whip" manifests as:
1. **Pelvis** arrives at crease (vertical deceleration) → FIRST PEAK
2. **Trunk** rotates and flexes laterally → SECOND PEAK
3. **Upper arm** accelerates overhead → THIRD PEAK
4. **Forearm** unfolds → FOURTH PEAK
5. **Wrist** snaps through release point → FINAL PEAK

From front-on camera, the most visible signal is **combined 2D velocity magnitude**.
The absolute velocity values are not meaningful — but the **relative timing of peaks**
(proximal-to-distal sequencing) IS camera-angle-invariant.

## Velocity Computation Strategy

Use **2D velocity magnitude** (sqrt(vx² + vy²)) from normalized coordinates.
This captures:
- Vertical arm whip (dominant from front-on)
- Lateral trunk rotation (visible as horizontal movement)
- Overall body deceleration at crease

The sequencing pattern (pelvis peaks first, wrist peaks last) holds from any camera angle.
This is the core insight: we're measuring WHEN segments peak, not HOW FAST in absolute terms.

## Reference: Broadcast Camera Angles

For future support:
- **End-on:** Behind bowler's arm. Similar to nets, slightly elevated.
- **Side-on:** Square of wicket. Best for stride length, knee angle. Worst for depth.
- **Fine leg:** Behind batsman. Good for release point, action shape.

All angles produce valid sequencing patterns. Absolute velocity scales differ.
