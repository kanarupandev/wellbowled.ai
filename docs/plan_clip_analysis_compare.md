# Plan: Clip Analysis & Comparison

## Overview

Each bowling delivery clip is enriched with full biomechanics data via a single Gemini call. Users compare any 2 clips side-by-side to see exactly what changed — technique, speed, quality — across 23 parameters.

## Architecture: 2 Gemini Calls Per Session

1. **Call #1 (start)**: Scene understanding / stump calibration from single frame
2. **Call #2 (end)**: Post-analysis of user's hand-picked top 3 clips

Everything else is on-device.

---

## Flow

```
CLIP LIBRARY (grid)
  All clips across all sessions
  Tile: thumbnail + speed + release dot + date/time

  [Select 2-3] --> [Analyze]   (Gemini call #2)
  [Select 2]   --> [Compare]   (on-device, both must be analyzed)
```

### Analyze (Gemini)
- User picks up to 3 clips from any session/time
- Single Gemini call with video clips
- Returns per-clip: 5-phase breakdown, DNA (18 categorical + 2 continuous), 5 quality scores, drills, expert joint feedback
- Results stored on Delivery struct

### Compare (On-Device)
- Pick any 2 analyzed clips
- Requires both clips to have Gemini analysis data
- Pure juxtaposition — no extra Gemini call

---

## Compare View Layout

```
+---------------------------+
|  COMPARE                  |
|                           |
|  +----------+----------+  |  PINNED TOP
|  | Clip A   | Clip B   |  |
|  | video+sk | video+sk |  |  (skeleton overlay)
|  | 102kph   | 97kph    |  |  (speed on video)
|  | Mar 3    | Mar 1    |  |  (date on video)
|  +----------+----------+  |
|                           |
|  --- scrollable rows ---  |  SORTED: biggest diff first
|                           |
|  [dark red]  arm path     high    round   |
|  [dark red]  run speed    fast    mod     |
|  [med red]   wrist w      0.8     0.6    |
|  [med red]   alignment    side    semi    |
|  [light red] balance      good    ok      |
|  [white]     stride       long    long    |
|  [white]     angle        str     str     |
|  ...                                      |
+-------------------------------------------+
```

### 3 columns only
- Parameter name | Clip A value | Clip B value
- NO 4th column bar — the row background color IS the diff indicator

### Red intensity = diff magnitude
- `pow(magnitude, 0.7) * 0.35` opacity
- Darker red = bigger difference
- White/transparent = identical
- Same-value rows sink to bottom naturally (sorted by diff descending)

### Speed + timestamp on the video itself
- NOT in the delta table
- Burned on each clip thumbnail: speed badge + date/time

---

## 23 Comparable Parameters

### Phase 1: Run-Up (3)
- Stride (short/medium/long)
- Speed (slow/moderate/fast/explosive)
- Approach angle (straight/angled/wide)

### Phase 2: Gather (3)
- Body alignment (front_on/semi/side_on)
- Back-foot contact (braced/sliding/jumping)
- Trunk lean (upright/slight/pronounced)

### Phase 3: Delivery Stride (3)
- Stride length (short/normal/over_striding)
- Front arm action (pull/sweep/delayed)
- Head stability (stable/tilted/falling)

### Phase 4: Release (5, weighted 2x in matching)
- Arm path (high/round_arm/sling)
- Release height (high/medium/low)
- Wrist position (behind/cocked/side_arm)
- Wrist angular velocity (0-1 continuous)
- Release wrist Y (0-1 continuous)

### Phase 5: Seam/Spin (2)
- Seam orientation (upright/scrambled/angled)
- Revolutions (low/medium/high)

### Phase 6: Follow-Through (2)
- Direction (across/straight/wide)
- Balance (balanced/falling/stumbling)

### Quality Scores (5)
- Run-up quality (0.1-1.0)
- Gather quality (0.1-1.0)
- Delivery stride quality (0.1-1.0)
- Release quality (0.1-1.0)
- Follow-through quality (0.1-1.0)

---

## Diff Calculation

Uses same ordinal encoding as `BowlingDNAVectorEncoder`:
- 3-value enum: 0.0, 0.5, 1.0
- 4-value enum: 0.0, 0.33, 0.67, 1.0
- Continuous: raw value (0-1)
- Diff = absolute difference between ordinal values
- Only rows where BOTH clips have values are shown
- Nil fields excluded

---

## What's Built (as of 2026-03-24)

- [x] `DNADiffCalculator.swift` — 23-param diff engine, sorted output
- [x] `ClipCompareView.swift` — pinned dual video + scrollable delta table
- [x] `Tests/DNADiffCalculatorTests.swift` — 8 test cases
- [x] Build verified on generic/iOS

## What's Next

- [ ] Wire ClipCompareView into session results (pick 2 deliveries to compare)
- [ ] ClipLibraryView — cross-session clip grid with multi-select
- [ ] Cross-session persistence layer (sessions + deliveries to disk)
- [ ] Thumbnail overlay rendering (speed + date burned on thumbnail image)
- [ ] Synced dual video playback with skeleton overlay in compare view
- [ ] Batch Gemini analysis call (send 2-3 clips, get enriched results)

---

## Key Questions for User

- How should clips be persisted across sessions? (JSON on disk? CoreData?)
- Clip library accessible from home screen or only post-session?
- Should compare be drag-and-drop or tap-to-select?
