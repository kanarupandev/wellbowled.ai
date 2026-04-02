# Bumrah vs Steyn — Execution Log

## Decisions

1. **Format:** Frame Battle (side-by-side comparison)
2. **Duration:** 35-40 seconds
3. **Resolution:** 1080x1920 (9:16 portrait)
4. **Clips needed:** One side-on delivery each for Bumrah and Steyn
5. **SAM 2 isolation:** Required for both (remove background people)
6. **Annotations:** Skeleton overlay with key angle differences highlighted

## Structure (from duration spec)

```
0-3s:   Hook — "This looks wrong."
         Show Bumrah's unusual action, freeze at peak
3-10s:  Show Bumrah — isolated, annotated, slow-mo
10-20s: Compare to Steyn — side-by-side at same phase
20-32s: Show why different still works — overlay key metrics
32-40s: Close — "Different does not mean broken." + wellBowled.ai
```

## Step-by-Step Plan

### Step 1: Source clips
- Bumrah: need side-on delivery clip (we have bumrah_side_on_3sec.mp4)
- Steyn: need side-on delivery clip (we have steyn_side_on_3sec.mp4)
- Check quality: are they usable?

### Step 2: SAM 2 isolate both bowlers
- Already done for nets bowler
- Need to do for Bumrah and Steyn clips
- Or: use existing MediaPipe on clean clips without isolation

### Step 3: Find matching phase frames
- Front foot contact frame for both
- Release/arm-over frame for both
- Match them so side-by-side shows same delivery moment

### Step 4: Measure key visual differences
- Hip-shoulder separation (proven metric)
- Front knee angle (proven metric)
- Trunk lean (if formula is fixed)
- These are for the "20-32s explain" section

### Step 5: Render
- Title card (hook)
- Bumrah solo section (slow-mo, annotated)
- Side-by-side section (both at same phase)
- Metrics overlay section
- Close card

### Step 6: Encode and review
