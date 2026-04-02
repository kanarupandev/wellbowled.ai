# X-Factor v1.0.0 — Visual Design Spec

## Video Structure (25-35s total)

```
[0.0s - 2.0s]   COLD OPEN      Raw footage at 1x speed. No overlays.
                                 Action starts immediately.
                                 Bottom pill: "WATCH THE HIPS"

[2.0s - 2.3s]   TRANSITION     Brief fade to slow-mo. 0.3s.

[2.3s - ~14s]   SLOW-MO        0.25x speed. Overlays appear ONLY during
                ANALYSIS        delivery window (BFC → follow-through).
                                 Hip line (pink), shoulder line (cyan),
                                 separation angle pill near torso.
                                 Phase label top-center.
                                 Legend bar at bottom.

[~14s - 17s]    FREEZE          Peak separation frame held for 2.5s.
                                 Darkened background (65% overlay).
                                 Large angle number center.
                                 "PEAK X-FACTOR" label above.

[17s - 20s]     VERDICT CARD    Blurred frame background.
                                 Rating (DEVELOPING / GOOD / ELITE).
                                 Full comparison scale bar.
                                 3 lines of coaching insight.

[20s - 21s]     END CARD        Brand: "wellBowled.ai"
                                 Tagline: "Cricket biomechanics, visualized"
                                 LARGE readable text (72px + 36px).
```

## Overlay Design

### Hip Line
- Color: #FF69B4 (hot pink) — warm, reads as "lower body"
- Width: 4px
- Extension: 25% beyond each joint
- Joint dots: 5px filled + 2px white border
- Only drawn when BOTH LEFT_HIP and RIGHT_HIP visibility > 0.5

### Shoulder Line
- Color: #00CED1 (dark turquoise) — cool, reads as "upper body"
- Width: 4px
- Extension: 25% beyond each joint
- Joint dots: 5px filled + 2px white border
- Only drawn when BOTH LEFT_SHOULDER and RIGHT_SHOULDER visibility > 0.5

### Skeleton
- Color: white, 35% opacity
- Width: 1px
- Only upper body + legs (no face/hands)
- Behind hip/shoulder lines (drawn first)

### Separation Angle Pill
- Position: near torso midpoint (contextual, not floating)
- Background: dark pill (#0A0E14, 80% opacity, border-radius 14px)
- Number: 32px bold, white
- Degree symbol: 18px, same color
- Color transitions: <15° grey, 15-30° yellow, 30-45° green, 45°+ bright green

### Phase Label
- Position: top-center, consistent
- Background: dark pill (#0A0E14, 75% opacity, border-radius 12px)
- Text: 18px bold, white
- Labels: "APPROACH" → "BACK FOOT" → "FRONT FOOT" → "RELEASE" → "FOLLOW THROUGH"

### Legend Bar
- Position: bottom, 30px from bottom edge (safe zone for Instagram)
- Two items: pink dot + "HIPS", cyan dot + "SHOULDERS"
- Background: dark pill, small, unobtrusive

## Freeze Card

- Frame: peak separation frame
- Overlay: 65% dark (#0A0E14)
- "PEAK X-FACTOR": 28px bold, white, centered above angle
- Angle number: 72px bold, accent color (#FF5040), centered
- "° hip-shoulder separation": 22px, light grey, below angle
- Legend at bottom: same as overlay

## Verdict Card

- Background: peak frame, gaussian blur (radius 6), 75% dark overlay
- Title: "X-FACTOR VERDICT" — 36px bold, accent red
- Angle: "XX° peak separation" — 20px, white
- Rating: 36px bold, color-coded
  - ELITE (45°+): green
  - VERY GOOD (35-44°): light green
  - DEVELOPING (28-34°): yellow
  - WORK ON IT (<28°): orange
- Comparison bar: full width, dark background
  - Markers: Untrained (12°), Amateur (20°), Good (30°), Elite (42°), Peak (50°+)
  - "You" marker in white, bold
  - Reference markers in respective colors
- Rating note: 16px, light grey, one sentence
- Coaching insight: 3 lines, 20px, centered, light text
- Brand: "wellBowled.ai" — 14px, muted, bottom

## End Card

- Background: brand dark (#0D1117)
- "wellBowled.ai": 72px bold, brand teal (#006D77)
- "Cricket biomechanics, visualized": 36px, white
- Duration: 1s max

## Font Stack (Linux)
1. /usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf (bold)
2. /usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf (regular)
3. /usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf (fallback bold)
4. /usr/share/fonts/truetype/dejavu/DejaVuSans.ttf (fallback regular)

## Color Palette

| Name | Hex | Use |
|------|-----|-----|
| Hip Pink | #FF69B4 | Hip line, hip joint dots |
| Shoulder Cyan | #00CED1 | Shoulder line, shoulder joint dots |
| Dark BG | #0A0E14 | Pills, overlays, cards |
| Brand Teal | #006D77 | wellBowled.ai text |
| White | #FFFFFF | Primary text |
| Light Grey | #B4BEC8 | Secondary text |
| Accent Red | #FF5040 | Peak angle number, verdict title |
| Safe Green | #64FF64 | Elite rating |
| Warn Yellow | #FFDC50 | Developing rating |
| Work Orange | #FF8C3C | Work on it rating |

## Constraints

- ALL rendering via Pillow (PIL) for anti-aliased text — NO cv2.putText
- Final encode: FFmpeg H.264, CRF 17, yuv420p, faststart, silent AAC track
- Output: 1080x1920, 30fps constant
- No hardcoded timestamps — delivery window detected from pose data
- No hardcoded bowler positions — Gemini Flash or largest-person heuristic
