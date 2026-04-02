# Bumrah vs Steyn — Video Script v0.0.1

## Meta

- **Title:** Why Bumrah Feels Wrong... But Still Works
- **Format:** Frame Battle (side-by-side comparison)
- **Duration:** 35-40 seconds
- **Aspect:** 9:16 (portrait, Shorts/Reels)
- **Narration:** Text-on-screen only (no voiceover in v1)
- **Date:** 2026-04-03

---

## Script

### BEAT 1 — Hook (0:00–0:03)

**Visual:** Bumrah at release (f072), freeze frame, slight zoom-in. Dark vignette edges.

**Text on screen:**

```
This doesn't look right.
```

**Notes:** The frame must land immediately. Bumrah f072 is the strongest single frame — arm at an unusual angle, body shape looks unorthodox. The viewer should feel the strangeness before anything is explained.

---

### BEAT 2 — Show the unusual (0:03–0:10)

**Visual:** Bumrah delivery sequence in slow-mo. Three key frames dissolve through in order:

1. **f036** — gather stride, compact run-up
2. **f060** — front foot contact, arm just starting to come over
3. **f072** — release point, full extension

Each frame holds ~2 seconds. Subtle skeleton overlay fades in on f060 and f072 (shoulder line, hip line, front knee angle).

**Text on screen (staggered):**

```
Short run-up.
Stiff front arm.
Almost no wind-up.
```

**Notes:** Keep the overlays minimal. Two lines max visible at once. The skeleton is there to guide the eye, not to lecture. Do not label angle values yet.

---

### BEAT 3 — The contrast (0:10–0:20)

**Visual:** Hard cut to Steyn. Same slow-mo treatment, but shorter — two frames only:

1. **f000** — classic high-arm gather
2. **f060** — textbook release, full side-on rotation

Then the side-by-side: Bumrah f060 (left) | Steyn f060 (right), matched at front foot contact phase. Hold for 3-4 seconds. Skeleton overlay on both, showing the shape difference.

**Text on screen:**

```
Now look at Steyn.

Same moment. Different shape.
```

**Notes:** The side-by-side is the centrepiece of the video. Both frames must be at the same delivery phase or it doesn't work. Front foot contact is the clearest phase to match. Scale both bowlers to similar height in frame.

---

### BEAT 4 — The reframe (0:20–0:32)

**Visual:** Second side-by-side. Bumrah f072 (left) | Steyn f075 (right) — both at release/follow-through. Hold for 3 seconds.

Then: brief return to full Bumrah delivery clip in real-time speed (1-2 seconds). Let the viewer see the full action once at speed after seeing it broken down.

**Text on screen (staggered):**

```
Two completely different actions.

Both devastating at 145+ km/h.

There is no single correct way to bowl fast.
```

**Notes:** This is the payload. The reframe must land cleanly: different is not broken. Do NOT add specific speed stats or wicket counts — that would be overclaiming precision we don't have from nets footage. "145+ km/h" is a defensible general claim for both bowlers. If even that feels like overclaiming from nets clips, soften to "Both elite. Both effective."

---

### BEAT 5 — Close (0:32–0:38)

**Visual:** Fade to dark / minimal background. Logo card.

**Text on screen:**

```
Different is not broken.

wellBowled.ai
```

**Notes:** Clean close. No call-to-action clutter in v1. The brand line IS the takeaway.

---

## Production Review Notes

### What works

1. **Strong hook frame.** Bumrah f072 is genuinely unusual-looking and should stop a scroll.
2. **Clear emotional arc.** "This looks wrong" → "Now compare" → "Different is not broken" follows the planned arc exactly.
3. **One idea.** The script never wanders from the single takeaway.
4. **Minimal text.** Never more than two lines on screen at once.

### Clip quality concerns

1. **Bumrah clip (MI Nets, MI TV watermark):**
   - Indoor nets, decent side-on angle.
   - MI TV watermark top-right — must be cropped or accepted.
   - Background people visible — SAM 2 isolation is planned but not yet done.
   - f060 and f072 are strong frames.

2. **Steyn clip (SA Nets, outdoor Newlands):**
   - Wider angle, bowler is smaller in frame.
   - Lower visual resolution than the Bumrah clip.
   - The resolution and framing mismatch between the two clips is the biggest production risk. When placed side-by-side, the difference in image quality and scale could undermine the "premium feel" goal.
   - f060 is the best Steyn frame but he's still notably smaller and softer than Bumrah in his frames.

3. **Side-by-side scaling risk:**
   - Bumrah is shot closer, indoor, sharper.
   - Steyn is shot wider, outdoor, softer.
   - Scaling Steyn up to match Bumrah's size will amplify the resolution gap.
   - This is the single biggest issue for the v1 video.

### Phase matching concern

The Bumrah clip has 8 frames (f000, f012, f024, f036, f048, f060, f072) and Steyn has 6 frames (f000, f015, f030, f045, f060, f075). The frame numbering does NOT mean these are at the same delivery phase. Phase matching must be done manually by identifying equivalent moments in the delivery stride (e.g., front foot contact, release point), not by frame number. The script above assumes f060 = front foot contact for both, but this needs to be verified against the actual frames.

From visual review:
- **Bumrah f060:** Appears to be around front foot contact — front leg planting, bowling arm coming over. This is a usable phase.
- **Steyn f060:** Appears to be at or just past release — arm over, follow-through starting. This is slightly later in the sequence than Bumrah f060.

**Recommendation:** Bumrah f060 may match better with Steyn f045 or f030 for front foot contact. This needs to be verified by viewing Steyn f045.

### What the script avoids (per planning docs)

- No biomechanics lecture — angles are shown visually, not numerically
- No prescription — does not tell the viewer to copy anyone
- No legality/chucking discussion
- No overclaiming — no specific stats, no "scientifically proven"
- No excessive on-screen metrics

### Open decisions for v1

1. **Voiceover or text-only?** Script is written text-only. VO version could be stronger but adds manual effort. Recommend text-only for v1 to stay within the 1-hour budget.
2. **Music/sound?** Not addressed. A bass-heavy, minimal beat would help. Needs to be royalty-free.
3. **SAM 2 isolation:** Not yet done. Script works without it but the background people (especially in the Bumrah nets clip) are distracting. If isolation is skipped, the dark vignette in Beat 1 partially mitigates this.
4. **Skeleton overlay source:** The `extract_angles.py` script exists but it's unclear if it has been run successfully on these clips. The skeleton overlay in the video depends on this working.
5. **Steyn clip replacement:** Given the quality gap, consider whether a better Steyn clip exists before investing time in the full render pipeline.
