# Speed Gradient Trail — v1.0.0 Plan

## What it does

Colors every joint on the bowler's body by its instantaneous velocity. Slow joints = cool blue. Fast joints = blazing red. The kinetic chain becomes VISIBLE — energy flowing from ground → hips → trunk → shoulder → elbow → wrist.

## Why it's the #1 pick

- **Viral:** Looks like thermal/heat imaging on the body. Mesmerizing.
- **Useful:** Amateur sees where their energy dies vs where elite bowlers transfer it.
- **Pace contribution:** The sequence matters — hips must light up BEFORE shoulders. If everything lights up at once = arm bowling = slow.
- **Hidden insight:** Nobody can see energy transfer with their eyes. This reveals it.
- **Camera independent:** Works from broadcast angle, side-on, nets — any footage.

## How it works

### Per frame:
1. Get all 33 MediaPipe landmarks
2. For each joint, compute velocity: `v = distance(pos[t], pos[t-1]) / dt`
3. Normalize velocity to 0-1 range (relative to max velocity in the clip)
4. Map to color: blue(0) → cyan(0.25) → green(0.5) → yellow(0.7) → orange(0.85) → red(1.0)
5. Draw skeleton with each bone colored by the average velocity of its two endpoints
6. Draw joint dots sized by velocity (fast = bigger, slow = smaller)

### Per video:
1. Gemini Flash: identify bowler + bowling window (reuse from X-factor)
2. MediaPipe pose extraction (reuse)
3. Compute per-joint velocity timeseries
4. Smooth velocities (rolling window 3 frames)
5. Normalize globally (max velocity across all joints across all frames = 1.0)
6. Render gradient-colored skeleton per frame
7. Compose: title → slo-mo with gradient overlay → freeze at peak energy → verdict → end

## Video structure (~15s)

```
[0-1.5s]    TITLE CARD
            "Where does the ENERGY go?"
            Blue ● → Red ● gradient legend
            "The faster the joint, the redder it glows"
            wellBowled.ai

[1.5-8s]    SLO-MO WITH GRADIENT OVERLAY (0.25x)
            Bowler's skeleton glows from cool to hot as energy transfers up
            Background: actual video (dimmed 30%)
            Overlay: colored skeleton + joint dots
            No phase labels (let the colors tell the story)
            Velocity number on the wrist: "12.3 m/s" → building to peak

[8-10.5s]   FREEZE AT PEAK
            Frame where wrist velocity is maximum (release point)
            Darken background
            Show full colored skeleton frozen
            "PEAK ENERGY TRANSFER"
            Wrist velocity number large

[10.5-14s]  VERDICT CARD
            "Kinetic Chain Score"
            Sequence order: did hips peak before shoulders before wrist? (correct = elite)
            Visual: 5 bars showing peak timing for each segment
            Rating: ELITE CHAIN / GOOD / BROKEN CHAIN
            wellBowled.ai

[14-15.5s]  END CARD
```

## Color palette

```
Velocity 0.0  → (30, 80, 220)    Deep blue (stationary)
Velocity 0.25 → (0, 200, 220)    Cyan
Velocity 0.5  → (50, 220, 50)    Green
Velocity 0.7  → (255, 220, 0)    Yellow
Velocity 0.85 → (255, 140, 0)    Orange
Velocity 1.0  → (255, 40, 40)    Blazing red
```

## Key joints to track (grouped by kinetic chain segment)

| Segment | Joints | Expected peak order (elite) |
|---------|--------|----------------------------|
| Base | Ankles (27, 28) | First (ground contact) |
| Hips | Left/Right hip (23, 24) | Second |
| Trunk | Shoulders (11, 12) | Third |
| Upper arm | Elbows (13, 14) | Fourth |
| Wrist | Wrists (15, 16) | Last (fastest at release) |

## Verdict: Kinetic Chain Sequencing

The key insight: in elite bowlers, the peak velocity of each segment happens in ORDER from ground up. If the order is wrong (e.g., wrist peaks before hips), the chain is broken.

Score:
- **ELITE CHAIN**: All 5 segments peak in correct order (±1 frame tolerance)
- **GOOD CHAIN**: 4/5 in order
- **BROKEN CHAIN**: 3 or fewer in order — "You're arm bowling"

## Technical notes

- Velocity computed in normalized image coordinates (0-1), not pixels — camera independent
- Smoothing: rolling mean over 3 frames to reduce jitter
- Global normalization: max velocity across ALL joints in the clip = 1.0
- Joint dot radius: 4px (slow) to 12px (fast)
- Bone width: 2px (slow) to 6px (fast)
- Background dimming: 40% for readability

## Reusable from X-Factor pipeline

- Gemini Flash call (bowler identification)
- MediaPipe pose extraction
- Bowling window cropping
- Video composition (title → slo-mo → freeze → verdict → end)
- Font loading, watermark, FFmpeg encoding

## Files

```
content/speed_gradient_pipeline/
├── run.py              # Single standalone file (like xfactor run_v100.py)
└── output/
```
