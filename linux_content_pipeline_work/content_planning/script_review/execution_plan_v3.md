# Execution Plan v3 — Bumrah vs Steyn: Different Engines, Same Job

Revised after Codex review of v2. Four fixes: landmark validation expanded, spine line gap closed, colour grading reordered before overlays, side-by-side dry run required.

---

## Phase 1 — Clip Selection and Phase Match

### Step 1.1: Evaluate Steyn clip options

Three Steyn clips available in `resources/samples/`:

| Clip | Type | Notes |
|------|------|-------|
| `steyn_side_on_3sec.mp4` | Nets (Newlands) | Current source. Lower quality, wider angle, bowler small in frame. |
| `steyn_broadcast_3sec.mp4` | Broadcast | Likely higher resolution. Must check angle and delivery phase visibility. |
| `steyn_sa_vs_eng_broadcast_5sec.mp4` | Broadcast (5s) | Longer clip, more frames to choose from. Must check if side-on. |

**Actions:**
1. Extract frames from all three clips at every 12-15 frames.
2. Compare: resolution, side-on angle quality, delivery phase visibility, bowler scale in frame.
3. Select the best clip for the side-by-side.

**Decision gate:**
- If a broadcast clip is clearly better → use it (but must verify pose extraction works on it in Phase 2).
- If all clips are roughly equal → stick with `steyn_side_on_3sec.mp4` since pose data path is already validated for nets clips.
- If no clip has a clean side-on view → flag and stop. Cannot produce a premium side-by-side.

### Step 1.2: Manual phase matching

**Actions:**
1. Lay out all extracted frames for Bumrah and selected Steyn clip.
2. Identify front foot contact frame for each bowler (preferred phase for hero side-by-side).
3. Identify release point frame for each bowler.
4. Select: one hero side-by-side pair, Steyn gather frame, Steyn release frame.

**Output:** Frame selection table:

| Beat | Bumrah frame | Steyn frame | Phase |
|------|-------------|-------------|-------|
| Beat 1 (hook) | release frame | — | release |
| Beat 2 (unusual) | gather, FFC, release | — | sequence |
| Beat 3 (Steyn solo) | — | gather, release | sequence |
| Beat 3 (side-by-side) | FFC or release | matched FFC or release | must match |

---

## Phase 2 — Tool Fit Validation

Before any code changes, verify what works and what doesn't.

### Step 2.1: Can extract_angles.py process the selected Steyn clip?

**Current state:** `extract_angles.py` (lines 15-17) hard-codes paths to `bumrah_side_on_3sec.mp4` and `steyn_side_on_3sec.mp4`. It cannot accept an arbitrary clip path.

**Test:**
1. If selected Steyn clip is `steyn_side_on_3sec.mp4` → no change needed, it already works.
2. If selected clip is a broadcast clip → `extract_angles.py` must be modified to accept clip paths as arguments before proceeding.

**Required fix (if broadcast clip selected):**
- Add CLI argument parsing to `extract_angles.py` so it accepts arbitrary clip paths.
- Small change: ~10 lines. Replace hard-coded BUMRAH/STEYN constants with argparse inputs.

### Step 2.2: Does pose extraction produce usable landmarks on the hero frames?

The overlay spec requires four distinct overlay elements. Each depends on specific landmarks. ALL must pass on the hero frames for the full overlay treatment to work.

**Full landmark validation checklist per hero frame:**

| Overlay element | Required landmarks | Indices | Min confidence |
|----------------|-------------------|---------|---------------|
| Hip line | L hip, R hip | 23, 24 | > 0.5 |
| Shoulder line | L shoulder, R shoulder | 11, 12 | > 0.5 |
| Front knee triangle | Hip, knee, ankle (front leg) | 23/24, 25/26, 27/28 | > 0.4 |
| Arm path | Shoulder, elbow, wrist (bowling arm) | 11/12, 13/14, 15/16 | > 0.4 |
| Spine line (release frame only) | Mid-shoulder, mid-hip (derived from 11+12, 23+24) | 11, 12, 23, 24 | > 0.5 |

Note: Spine line is drawn as a line from the midpoint of the two shoulders to the midpoint of the two hips. It depends on the same four joints as the hip/shoulder lines — no additional landmarks needed, but all four must be high-confidence for the line to be meaningful.

**Actions:**
1. Run `extract_angles.py` on the Bumrah clip. Check ALL landmark groups above on the hero frames (gather, FFC, release).
2. Run on the selected Steyn clip. Same check.
3. For each hero frame, verify every landmark group in the table above meets its minimum confidence.
4. Record which overlay elements pass and which fail per frame.

**Decision gate:**
- All landmark groups pass on all hero frames → proceed to Phase 3 with full overlay treatment.
- Some groups fail → options:
  - Try alternative frames from the same clip where confidence is higher.
  - Try alternative Steyn clip.
  - Simplify overlay to only the elements that pass (e.g. if arm path fails, draw hip/shoulder/knee only).
- Both bowlers fail on core groups (hip + shoulder) → re-extract at finer frame interval, or choose different hero frames.

### Step 2.3: What arm path data is available?

**Current state:** Neither `extract_angles.py` nor `xfactor_compute.py` compute arm path data (shoulder-elbow-wrist angle or line). The script's overlay spec calls for arm path highlighting.

**Raw data available:** `pose_extractor.py` already extracts landmarks 13 (L elbow), 14 (R elbow), 15 (L wrist), 16 (R wrist) as part of PRIMARY_JOINTS. The data IS there in the landmarks array — it just isn't computed into an angle or drawn.

**Required work:**
- No new extraction needed. The shoulder-elbow-wrist coordinates are already in the landmark output.
- The overlay renderer needs to draw the arm path line from the existing landmarks.
- Estimate: ~15 lines of drawing code in the renderer.

### Step 2.4: Overlay renderer fit-gap

**Current state of `overlay_renderer.py`:**

| Feature | Current behaviour | Script requirement |
|---------|------------------|-------------------|
| Hip line | Drawn (pink, extended) | Keep — change colour to amber/orange at ~70% sat |
| Shoulder line | Drawn (cyan, extended) | Keep — change colour to muted cyan at ~70% sat |
| Numeric angle pill | Always rendered (lines 138-165) | REMOVE — no numbers on screen |
| Phase label pill | Always rendered (lines 167-185) | REMOVE — no labels on screen |
| Legend bar | Always rendered via `render_legend()` (lines 189-207) | REMOVE — no legend |
| Front knee triangle | Not drawn | ADD — hip-knee-ankle triangle in green |
| Arm path line | Not drawn | ADD — shoulder-elbow-wrist line in white |
| Attention pulse/glow | Not implemented | ADD — single brief glow on most-different lines |

**Required changes to `overlay_renderer.py`:**

1. Add a `mode` parameter to `render_frame_overlay()`:
   - `mode="xfactor"` → current behaviour (for existing pipeline)
   - `mode="comparison"` → new behaviour for this asset (no pills, no legend, muted colours)
2. Add front knee triangle drawing (hip-knee-ankle).
3. Add arm path line drawing (shoulder-elbow-wrist).
4. Add muted colour palette option (~70% saturation).
5. Add pulse/glow effect function for the side-by-side attention mark.

**Estimate:** Medium change. ~80-120 lines of new/modified code. Existing xfactor pipeline is not broken.

### Step 2.5: Video composer fit-gap

**Current state of `video_composer.py`:**

The current `compose_video()` function is built for a single-bowler X-Factor explainer:
- Cold open with "WATCH THIS DELIVERY" badge (line 75-92)
- Slow-mo replay with overlays (line 296-319)
- Freeze at peak with "PEAK X-FACTOR" card (line 95-138)
- Verdict card with rating and reference bar (line 141-236)

**None of this matches the approved script.** The script needs:
- Hook freeze frame with custom text overlay
- Dissolving frame sequence with staggered text
- Side-by-side composition (two bowlers in one frame)
- Real-time replay with no overlay
- Clean close card with brand

**Required: a new composition function**, not modifications to the existing one.

**New function needed:** `compose_frame_battle()` in `video_composer.py`

Responsibilities:
1. Beat 1: Single frame + zoom + vignette + text overlay
2. Beat 2: Frame sequence with dissolve transitions + skeleton overlay + staggered text
3. Beat 3: Steyn solo frames + side-by-side card with overlays + text
4. Beat 4: Real-time clip playback + text on dark background
5. Beat 5: Fade to dark + logo card

Additional capabilities needed:
- Text rendering with clean fade-in (not the current pill style)
- Dissolve transition between frames
- Ken Burns effect (subtle zoom/pan drift)
- Side-by-side frame composition with divider
- Colour grading pass (desaturate, lift blacks, vignette)

**Estimate:** Large change. New function ~200-300 lines. Existing `compose_video()` is not touched.

---

## Phase 3 — Tooling Adaptation

Execute the code changes identified in Phase 2. Strictly in this order:

### Step 3.1: Generalize extract_angles.py (if needed)

- Add argparse for clip path inputs.
- Keep the current hard-coded paths as defaults so existing usage still works.

### Step 3.2: Adapt overlay_renderer.py

1. Add `mode="comparison"` parameter to `render_frame_overlay()`.
2. In comparison mode:
   - Draw hip line in muted amber (not hot pink).
   - Draw shoulder line in muted cyan.
   - Draw front knee triangle (hip-knee-ankle) in muted green.
   - Draw arm path (shoulder-elbow-wrist) in white.
   - Draw spine line (mid-shoulder to mid-hip) in muted warm grey — release frame only.
   - Skip numeric pill, phase pill, and legend.
3. Add `render_pulse_glow()` function — responsible for the VISUAL STYLE of the attention mark only (glow colour, radius, opacity, which skeleton lines to emphasise). This function renders a single frame with the glow applied. It does NOT control timing or animation.

### Step 3.3: Build compose_frame_battle() in video_composer.py

New composition function for the Frame Battle format. Sub-functions needed:

1. `_make_hook_card()` — single frame + vignette + zoom + text
2. `_make_dissolve_sequence()` — N frames dissolving with staggered text
3. `_make_side_by_side_card()` — two frames side by side with divider + overlays
4. `_make_text_card()` — text on dark background (for Beat 4 payoff and Beat 5 close)
5. `_apply_ken_burns()` — subtle zoom/pan drift on stills
6. `_apply_colour_grade()` — desaturate, lift blacks, vignette (unifies source clips)
7. `_apply_pulse_timing()` — controls WHEN and HOW LONG the pulse/glow appears during the side-by-side hold. Calls `render_pulse_glow()` from the renderer for the visual, but owns the timing: fade-in duration, hold duration, fade-out, and which output frames get the glow applied. One pulse only, not repeating.
8. `compose_frame_battle()` — orchestrates all beats into the final video

**Pulse/glow responsibility split:**
- `overlay_renderer.py` → `render_pulse_glow()` owns the **look**: which lines glow, what colour, what radius, what opacity for a single frame.
- `video_composer.py` → `_apply_pulse_timing()` owns the **behaviour**: when the glow starts, how many frames it spans, fade-in/out curve. It calls the renderer per-frame with an opacity parameter to create the animation.

Typography:
- One sans-serif font (LiberationSans already available in the font loader).
- Clean fade-in for text, no bounce/typewriter.
- Lower third or centred positioning.
- Generous line spacing.

Encoding:
- Reuse existing `_reencode_for_youtube()` for H.264 + AAC output.

### Step 3.4: Validate with a dry run

Before rendering the real asset:
1. Run the modified `extract_angles.py` on both clips. Confirm output.
2. Render a single test overlay frame in comparison mode. Confirm no pills, no legend, correct colours.
3. **Render one actual matched side-by-side comparison card** using the real hero frames from both bowlers with full overlay treatment on both sides. This is the true validation artifact — a single good overlay frame on one bowler is NOT sufficient. The side-by-side must show both bowlers with all four overlay elements (hip line, shoulder line, knee triangle, arm path) rendering cleanly at matched scale.
4. Compose a 10-second stub video using placeholder frames. Confirm dissolves, text, Ken Burns, and encoding all work.

**Decision gate:**
- All four checks pass (especially the matched side-by-side card) → proceed to Phase 4.
- Side-by-side card fails on one bowler → check which landmark groups are low-confidence and either pick a different frame, different clip, or simplify overlay for that bowler.
- Any other check fails → fix before proceeding. Do not start the full render with broken tooling.

---

## Phase 4 — Asset Render

### Step 4.1: Run pose extraction on both hero clips

1. Extract poses for Bumrah clip.
2. Extract poses for selected Steyn clip.
3. Compute X-Factor for both (for the overlay, even though we don't show numbers).
4. Save landmark data for the confirmed hero frames.

### Step 4.2: Apply colour grading to source frames

Grade source frames BEFORE overlays are rendered. If grading happens after overlays are burned in, it alters overlay colours and contrast, weakening the intentional broadcast look.

1. Run `_apply_colour_grade()` on all source footage frames (both bowlers).
2. Verify visual unity between the two source clips.
3. Check at 1080x1920 resolution on a dark background.

### Step 4.3: Render skeleton overlays on graded frames

Using the adapted `overlay_renderer.py` in `mode="comparison"`, render onto the already-graded frames:

1. Bumrah FFC frame — front knee triangle + arm path.
2. Bumrah release frame — hip line + shoulder line + spine line.
3. Steyn matched frames — same overlay treatment.
4. Side-by-side hero card — both overlays + pulse/glow attention mark.

### Step 4.4: Compose final video

Run `compose_frame_battle()` with:
- All graded + overlaid frames
- Script text for each beat
- Transition timings per the script

Output: draft MP4 at 1080x1920.

### Step 4.5: Sound

**v1 ships silent.** The current `_reencode_for_youtube()` helper always injects silent audio via `anullsrc` (video_composer.py line 377). This is correct for v1 — YouTube/Reels accept silent uploads without issues.

Adding real music requires an audio-aware encode path that replaces `anullsrc` with an actual audio input. That is out of scope for v1. If the silent version performs well, audio integration becomes a v1.1 task:
- Source royalty-free minimal bass beat.
- Align beat drops to hook (0:00), Steyn hard cut (0:10), real-time replay (0:22).
- Silence on close card.
- Update `_reencode_for_youtube()` or add a new encode function that accepts an audio file input.

---

## Phase 5 — QC

### Step 5.1: Phone screen review

Watch full video on a phone screen (actual viewing context).

Checklist:
- [ ] Hook stops a scroll in the first second
- [ ] Skeleton overlay highlights differences without overwhelming
- [ ] Side-by-side is legible at phone resolution
- [ ] Text lands within its beat window, readable at speed
- [ ] Colour grading unifies the two clips — no jarring quality shift
- [ ] Close card is brief, not an ad
- [ ] Total duration 35-40 seconds
- [ ] No artefacts, frame drops, or encoding issues

### Step 5.2: Fix or ship

- If all checks pass → final asset ready.
- If issues found → fix and re-render. Do not iterate more than twice at QC stage.

---

## Fallback Paths

### If Steyn clip quality is too low for premium side-by-side

Options (in order of preference):
1. Try broadcast clips (`steyn_broadcast_3sec.mp4`, `steyn_sa_vs_eng_broadcast_5sec.mp4`).
2. If broadcast clips aren't side-on → use the nets clip with heavy colour grading to mask the gap.
3. If nothing works → stop and source a new Steyn clip before proceeding.

### If pose extraction fails on hero frames

Options:
1. Try different frames from the same clip (different delivery phase).
2. Try a different clip for that bowler.
3. Simplify overlay to only high-confidence joints (drop low-confidence lines).
4. Last resort: hand-draw the overlay lines on the key frames (breaks automation, but delivers the asset).

### If the overlay renderer modifications break the existing pipeline

- The `mode` parameter protects the existing code path. If `mode="xfactor"` (default) behaviour changes → revert and isolate the comparison renderer into a separate function.

---

## Dependency Chain

```
Phase 1: Clip selection + phase match
  │
  ▼
Phase 2: Tool fit validation (read-only, no code changes)
  │
  ▼
Phase 3: Tooling adaptation (code changes)
  │  3.1 extract_angles.py (if needed)
  │  3.2 overlay_renderer.py
  │  3.3 video_composer.py (new compose_frame_battle)
  │  3.4 dry run validation
  │
  ▼
Phase 4: Asset render
  │  4.1 pose extraction
  │  4.2 colour grading (BEFORE overlays)
  │  4.3 skeleton overlays (on graded frames)
  │  4.4 compose video
  │  4.5 sound (optional)
  │
  ▼
Phase 5: QC
```

Phase 2 is a read-only checkpoint. No code changes until Phase 2 confirms what's needed.
Phase 3 is the engineering investment. One-time cost that pays off across the Frame Battle series.
Phase 4 is the actual asset production.
Phase 5 is the quality gate.
