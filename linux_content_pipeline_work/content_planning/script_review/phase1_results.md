# Phase 1 Results — Clip Selection and Phase Match

## Step 1.1: Steyn Clip Selection

### All clips evaluated

| Clip | Resolution | Angle | Bowler scale | Delivery phases | Verdict |
|------|-----------|-------|-------------|----------------|---------|
| `steyn_side_on_3sec.mp4` | 640x360 | Side-on | Small but clear | Full stride through follow-through | **Selected** |
| `steyn_broadcast_3sec.mp4` | 640x360 | Behind stumps | Tiny, obscured by batsman | Partially visible | Rejected — wrong angle |
| `steyn_sa_vs_eng_broadcast_5sec.mp4` | 640x360 | Behind stumps (wide) | Small, end-on | Visible but end-on | Rejected — wrong angle |

### Decision

**Use `steyn_side_on_3sec.mp4`.**

The broadcast clips are both shot from behind the stumps. You cannot read hip-shoulder separation, front knee angle, or arm path from end-on angles. The nets clip is the only side-on view in the repo.

All three clips are 640x360 — no resolution advantage from broadcast footage.

The quality gap with Bumrah (indoor, closer, sharper) remains. Colour grading in Phase 4 must work harder to unify them visually.

---

## Step 1.2: Phase Matching

Extracted fine frames (every 6 frames) from both clips for precise phase identification.

### Bumrah delivery phases

| Frame | Phase |
|-------|-------|
| f036 | Late gather, approaching crease |
| f042 | Load-up, ball hand coming back |
| f048 | Weight transfer, stride lengthening |
| f054 | Front foot reaching, bowling arm starting over |
| f060 | **Front foot planted, bowling arm at peak, body rotating** |
| f066 | Release / early follow-through, arm over |
| f072 | Full follow-through |

### Steyn delivery phases

| Frame | Phase |
|-------|-------|
| f000-f012 | Run-up, approaching crease |
| f024 | High arm gather, bowling arm going up |
| f030 | Front foot reaching, arm at top |
| f036 | **Front foot planted, arm starting to come over** |
| f042 | Arm coming through, releasing |
| f048 | Follow-through, body bending forward |
| f060+ | Post-delivery |

### Phase matches confirmed

| Delivery phase | Bumrah frame | Steyn frame | Confidence |
|---------------|-------------|-------------|------------|
| Front foot contact | **f060** | **f036** | High — both show front foot firmly planted, bowling arm active |
| Release point | **f066** | **f042** | High — both show arm coming through, body rotating |
| Gather | f036 | f024 | Medium — both in gather phase, different points in the gather |

### Hero side-by-side pair

**Bumrah f060 vs Steyn f036** — front foot contact phase.

Reasons:
- Clearest visual contrast in body shape
- Both bowlers have front foot planted and are fully committed to the delivery
- All key skeleton regions (hips, shoulders, front knee, bowling arm) should be visible
- This phase shows the maximum difference in action shape

### Frame selection table (final)

| Beat | Bumrah frame | Steyn frame | Phase |
|------|-------------|-------------|-------|
| Beat 1 (hook) | f072 | — | follow-through (most unusual-looking) |
| Beat 2 (unusual) | f036, f060, f072 | — | gather, FFC, follow-through |
| Beat 3 (Steyn solo) | — | f024 (gather), f042 (release) | gather, release |
| Beat 3 (side-by-side) | **f060** | **f036** | front foot contact |

---

## Phase 1 Status

**Complete. Proceed to Phase 2 — Tool Fit Validation.**
