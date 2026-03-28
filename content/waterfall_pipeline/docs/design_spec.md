# Velocity Waterfall v1.0.0 — Design Specification

## Concept

Stacked velocity-time curves for 5 body segments (pelvis → trunk → upper arm →
forearm → wrist) animated alongside slo-mo bowling video. Shows the kinetic chain
"whip" — elite bowlers have sequential peaks (proximal-to-distal); amateurs
have simultaneous or reversed peaks.

**Academic basis:** Putnam 1993 (sequential motions), Felton et al. 2023
(bowling variations biomechanics), velocity summation principle.

**Camera angle:** End-on broadcast (IPL/international) or non-striker's end nets.
Bowler runs toward camera. Velocity measured as 2D magnitude — sequencing
pattern is camera-angle-invariant.

---

## Video Structure (20-30s total)

| Segment | Duration | Content |
|---------|----------|---------|
| 1. Cold Open | 1.5s | Raw footage at 1x. Hook text: "Where does the WHIP come from?" |
| 2. Slo-Mo Analysis | 8-12s | 0.25x with animated waterfall graph building alongside |
| 3. Peak Freeze | 2s | Freeze at peak wrist velocity. Badge + peak order annotation |
| 4. Verdict Card | 2.5s | Blurred bg. Sequencing verdict + comparison + insight |
| 5. End Card | 1s | wellBowled.ai + tagline |

---

## Canvas Layout (1080 × 1920)

```
┌─────────────────────────┐ 0
│      TITLE (34px)       │ 20-60
│   "VELOCITY WATERFALL"  │
├─────────────────────────┤ 80
│                         │
│    VIDEO FRAME          │
│    (56% of height)      │
│    + faded skeleton     │
│    + active segment     │
│      highlight          │
│                         │
├─────────────────────────┤ ~1155  (separator line)
│                         │
│    VELOCITY GRAPH       │
│    (33% of height)      │
│    5 colored curves     │
│    glow + fill          │
│    dashed cursor        │
│    cursor dots          │
│                         │
├─────────────────────────┤ ~1810
│  LEGEND  |  TIME  | ⌂  │ 1820-1920
└─────────────────────────┘
```

---

## Segment Colors (5 body segments)

| Segment | RGB | Hex | Role |
|---------|-----|-----|------|
| Pelvis | (255, 107, 107) | #FF6B6B | Coral — warm, grounding |
| Trunk | (255, 217, 61) | #FFD93D | Gold — rotational engine |
| Upper Arm | (107, 203, 119) | #6BCB77 | Green — transfer link |
| Forearm | (77, 150, 255) | #4D96FF | Blue — acceleration phase |
| Wrist | (255, 0, 255) | #FF00FF | Magenta — the whip tip |

Chosen for maximum distinguishability on dark background. Colors progress
from warm (proximal) to cool/electric (distal).

---

## Graph Design

- **X-axis:** Time (frames within delivery window, zoomed to interesting region)
- **Y-axis:** Normalized velocity (0-1.2, relative to max wrist velocity)
- **Curves:** 3-layer rendering per segment:
  1. Alpha fill under curve (10% opacity) — area shading
  2. Gaussian-blurred glow (25% opacity, 7px width) — neon halo
  3. Sharp polyline (3px width, LINE_AA) — the actual curve
- **Cursor:** Dashed white vertical line at current frame
- **Cursor dots:** 5px filled circles in segment color where cursor intersects each curve
- **Grid:** Subtle (30, 33, 40) lines at 25% intervals
- **Axes:** Y-axis left, X-axis bottom, (60, 65, 75) lines

---

## Overlay Rules

1. **Delivery-window gating:** Overlays (skeleton, highlights, graph curves) only
   render during delivery zone (DELIVERY_START to graph_end)
2. **Visibility gate:** All segment landmarks must have visibility > 0.3 to draw
3. **Active segment highlight:** The segment with highest velocity at current frame
   gets bright colored dots (10px) with white outline (2px) on the video
4. **Faded skeleton:** 30% opacity, white, 2px connections — always behind highlights
5. **Post-delivery:** Graph stays frozen (complete), no cursor, no skeleton

---

## Verdict Card Design

**Background:** Peak frame, Gaussian blur (radius=8), 75% dark overlay

**Content layout:**
```
        KINETIC CHAIN ANALYSIS
        ─────────────────────

        ● Pelvis:    frame 7     (coral dot)
        ● Trunk:     frame 7     (gold dot)
        ● Upper Arm: frame 8     (green dot)
        ● Forearm:   frame 9     (blue dot)
        ● Wrist:     frame 9     (magenta dot)

        ELITE SEQUENCING          (green, 30px bold)
        Sequential energy transfer —
        the hallmark of express pace.

        ────────────────────────
        wellBowled.ai
```

**Rating system:**
| Pattern | Verdict | Color |
|---------|---------|-------|
| All peaks in correct proximal→distal order | ELITE SEQUENCING | Green |
| Mostly correct, ≤1 swap | GOOD SEQUENCING | Yellow-green |
| 2+ swaps or simultaneous | BLOCKED ROTATION | Orange-red |

---

## Typography

All text via **Pillow** (never cv2.putText).

| Element | Font | Size | Color |
|---------|------|------|-------|
| Title | Bold | 34px | White |
| Subtitle | Regular | 17px | (140,140,140) grey |
| Hook text (intro) | Bold | 32px | White on dark pill |
| Angle/value readout | Bold | 28px | Segment color |
| Legend labels | Regular | 14px | (180,180,180) grey |
| Time indicator | Regular | 15px | (120,120,120) grey |
| Brand | Bold | 20px | (0,109,119) teal |
| Verdict title | Bold | 42px | White |
| Verdict rating | Bold | 30px | Rating color |
| Verdict body | Regular | 22px | (160,160,160) grey |
| End card brand | Bold | 72px | (0,109,119) teal |
| End card tagline | Regular | 36px | White |

**Font stack:** Liberation Sans (Linux) → Arial (macOS) → DejaVu (fallback)

---

## Velocity Computation

1. **Extract positions** per segment per frame (normalized 0-1 coordinates)
2. **Central difference:** v[i] = sqrt((x[i+1]-x[i-1])² + (y[i+1]-y[i-1])²) / (2·dt)
3. **NaN interpolation** for missing landmarks
4. **Savitzky-Golay smooth:** window=7, polyorder=2 (0.7s at 10fps)
5. **Normalize:** all velocities / max_wrist_velocity → 0-1 range
6. **Graph zoom:** X-axis from DELIVERY_START to last_peak + 6 frames
7. **Sequencing check:** compare peak frame indices

---

## FFmpeg Encoding

```
ffmpeg -y -framerate 30
  -i input_%06d.jpg
  -c:v libx264 -preset medium -crf 18
  -pix_fmt yuv420p -movflags +faststart
  output.mp4
```

CRF 18 — high quality, YouTube/Instagram compliant.
