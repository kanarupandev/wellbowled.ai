# Phase 2 Results — Tool Fit Validation

## Step 2.1: extract_angles.py compatibility

Selected clip is `steyn_side_on_3sec.mp4` — already hard-coded. **No change needed.**

---

## Step 2.2: Landmark confidence on hero frames

### Steyn — ALL PASS

Every hero frame (f024, f036, f042) passes every overlay group with high confidence (min 0.794 across all). No issues whatsoever. Steyn's outdoor nets clip has clean pose detection.

### Bumrah — Passes where it matters

| Frame | Used for | Overlay needed | Hip/Sho | Knee | Arm path | Verdict |
|-------|----------|---------------|---------|------|----------|---------|
| f036 | Beat 2 (gather) | **None** — skeleton only on last two frames | PASS | FAIL | PASS | **OK** — no overlay on this frame |
| f060 | Beat 2 (FFC) + **hero side-by-side** | Knee triangle + arm path | PASS | PASS | PASS | **PASS** — all groups clear |
| f066 | Not in final script | — | PASS | FAIL | FAIL | **N/A** — not a hero frame |
| f072 | Beat 1 (hook) + Beat 2 (release) | Hip line + shoulder line + spine | PASS | PASS | L:PASS R:FAIL(0.368) | **PASS** — arm path not needed on this frame |

### Key finding

The script specifies different overlay elements per frame:
- **f060 (FFC):** front knee triangle + bowling arm path → ALL PASS
- **f072 (release):** hip-shoulder separation + spine line → ALL PASS (spine derives from hip/shoulder landmarks which are >0.999)

Arm path is only drawn on the FFC frame, not the release frame. So Bumrah f072's right arm path failure (0.368) has **zero impact** on the planned treatment.

### Hero side-by-side validation

| Overlay element | Bumrah f060 | Steyn f036 | Both pass? |
|----------------|-------------|------------|-----------|
| Hip line | min 0.999 | min 1.000 | **Yes** |
| Shoulder line | min 0.991 | min 1.000 | **Yes** |
| Front knee (best leg) | L: min 0.681 | L: min 0.960 | **Yes** |
| Arm path (bowling arm) | L: min 0.996 | R: min 1.000 | **Yes** |

All four overlay elements pass on both bowlers at the hero side-by-side phase. Full overlay treatment is viable.

Note: Bumrah is right-arm bowler but in side-on view facing left, his bowling arm maps to LEFT landmarks (11→13→15). Steyn bowling right-to-left maps to RIGHT landmarks (12→14→16). Both pass.

---

## Step 2.3: Arm path data

Confirmed: landmarks 13 (L elbow), 14 (R elbow), 15 (L wrist), 16 (R wrist) are already extracted by `pose_extractor.py` as part of PRIMARY_JOINTS. The data exists in the landmarks array.

**No new extraction code needed.** Only drawing code in the renderer.

---

## Step 2.4: Overlay renderer fit-gap

Confirmed from code review (already documented in execution plan v3). Summary:

- Must add `mode="comparison"` to skip pills/legend
- Must add front knee triangle drawing
- Must add arm path line drawing
- Must add spine line drawing
- Must add pulse/glow function (visual only — timing in composer)
- Must change colour palette to muted tones

Estimate unchanged: ~80-120 lines.

---

## Step 2.5: Video composer fit-gap

Confirmed from code review (already documented in execution plan v3). Summary:

- Current `compose_video()` is X-Factor explainer — wrong template entirely
- Need new `compose_frame_battle()` function
- Need: dissolve transitions, Ken Burns, side-by-side composition, text rendering, colour grading, pulse timing

Estimate unchanged: ~200-300 lines new function.

---

## Phase 2 Decision

**All gates pass. Proceed to Phase 3 — Tooling Adaptation.**

No blockers. No fallback paths triggered. Full overlay treatment is viable on all hero frames.
