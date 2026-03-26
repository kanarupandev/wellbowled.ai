# Energy Transfer Analysis — Design

## Core Concept

At each transition in the kinetic chain, energy either **transfers efficiently** (next segment accelerates) or **leaks** (energy lost, next segment doesn't accelerate enough).

## What to show at each pause

### 1. Transfer Efficiency Ratio

At each transition (e.g., Trunk → Arm), compute:
```
efficiency = (peak_velocity_next_segment / peak_velocity_current_segment) × 100
```

- **>100%**: Energy AMPLIFIED (elite — the whip effect is working)
- **80-100%**: Good transfer
- **50-80%**: Energy leaking — this is where pace is lost
- **<50%**: Broken chain — major leak

Display as: "Trunk → Arm: 120% ⚡" (energy amplified) or "Trunk → Arm: 60% ⚠️ LEAK"

### 2. Visual at each pause

```
[TRUNK → ARM]
Transfer: 120% ⚡
"Energy amplified — whip effect"

vs

[TRUNK → ARM]
Transfer: 55% ⚠️
"Energy leaking here — arm not accelerating enough"
"Fix: Lead with hip rotation, delay arm longer"
```

### 3. Benchmark comparison

Compare each ratio against elite bowlers:
```
Your transfer:  Trunk → Arm: 60%
Elite average:  Trunk → Arm: 115%
Gap: -55% ← "This is where you're losing pace"
```

From research (Worthington 2013, segmental kinetic energy in cricket bowling):
- Elite: proximal-to-distal amplification, each segment peaks HIGHER than previous
- Amateur: energy dissipates, each segment peaks LOWER
- The ratio between segments IS the differentiator

### 4. Summary verdict card

```
YOUR KINETIC CHAIN

Hips → Trunk:    85%  ● Good
Trunk → Arm:     55%  ● LEAK ⚠️
Arm → Wrist:    120%  ● Elite ⚡

Overall: 65% efficient
Elite benchmark: 95%+

"Your energy leaks at the trunk-to-arm transition.
Work on delaying the arm and leading with trunk rotation."
```

## What we CAN'T do (honestly)

- Absolute force/energy in Newtons or Joules — need force plates
- 3D velocity — we have 2D projection only
- Exact comparison to published elite data — our units don't match lab units

## What we CAN do

- Relative velocity ratios between segments — THIS IS VALID from any camera angle
- The RATIO is camera-independent (both segments are equally affected by projection)
- Compare ratios between bowlers filmed from the same angle
- Show WHERE in the chain the efficiency drops

## Implementation plan

1. At each transition pause, compute and display the transfer ratio
2. Color the ratio: green (>100%), yellow (80-100%), red (<80%)
3. Add one-line coaching insight per transition
4. Verdict card: full chain with ratios + overall efficiency + coaching summary
5. For comparison videos: show both bowlers' ratios side by side

## Camera angle note

The transfer RATIO is more reliable than absolute velocity because:
- If the camera foreshortens both hips and trunk equally, their ratio is preserved
- The ratio measures "how much did the next segment speed up relative to the previous one"
- This works from broadcast, side-on, nets — any consistent angle within a clip
