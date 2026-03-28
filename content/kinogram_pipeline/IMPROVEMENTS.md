# Kinogram Pipeline — Mandatory Improvements (Pre-MVP)

> These must be fixed before any video is published. Current output is proof-of-concept only.

---

## 1. Bystander Detection

**Problem:** The segmentation mask picks up the bystander (red shirt kid) along with the bowler. MediaPipe's segmentation doesn't distinguish between people.

**Fix:**
- Use pose bounding box to create a spatial mask around the bowler's detected skeleton
- AND the segmentation mask with the pose-derived bounding box (with padding)
- Only keep pixels within ~1.5x the pose bounding box
- Reject any mask region disconnected from the bowler's torso centroid

---

## 2. Figures Too Stacked / Cramped

**Problem:** All 7 figures are composited at their actual video positions, causing heavy overlap in the center. Not intelligible — looks like a blur.

**Fix — Artificial Horizontal Separation:**
- Extract each figure as a tight crop (using masked bounding box)
- Place figures evenly spaced across the canvas width, NOT at their original x-positions
- Normalize vertical position so all figures share a common ground line (align feet)
- Each figure gets its own "column" — like a traditional sprint kinogram strip
- Optional: slight horizontal offset per phase so they fan out naturally

**Reference:** ALTIS sprint kinograms place each body position in its own vertical slice with equal spacing. That's the target aesthetic.

---

## 3. Playwright Review Loop

**Problem:** Current review is FFmpeg-only (extract static frames). No browser-based visual QA.

**Fix:**
- Create `viewer.html` with embedded `<video>` player + hero image panel
- Use Playwright to:
  1. Load the viewer in headless Chromium
  2. Screenshot at 5 keypoints (0%, 25%, 50%, 75%, 100%)
  3. Screenshot the hero image at full resolution
  4. Run automated visual checks:
     - Is the bowler visible in the center third? (pixel brightness check in center column)
     - Is the bystander visible? (check for unexpected bright regions outside bowler bbox)
     - Are all 7 phase labels rendered? (OCR or template match)
     - Is there sufficient contrast between adjacent figures?
  5. Output a pass/fail JSON report
  6. If fail → adjust parameters and re-render (up to 3 iterations)

---

## 4. Color Tinting Too Heavy

**Problem:** The 20% accent color tint makes the figures look unnatural. The bowler's actual appearance is lost.

**Fix:**
- Reduce tint to 5-8% — just enough to differentiate phases
- Use colored skeleton lines + colored outline glow as the primary color coding
- Keep the figure itself mostly true to the original video

---

## 5. Background Too Dark

**Problem:** Background is darkened to 25% — loses all context (pitch, crease, nets). Viewer can't orient where the action is happening.

**Fix:**
- Darken to 40-50% instead of 25%
- Keep the crease line visible as a grounding reference
- Add a subtle gradient at the bottom to separate figures from ground

---

## 6. Phase Label Accuracy

**Problem:** Phase labels are assigned by equal spacing, not by actual biomechanical phases. "BACK FOOT" label might not correspond to actual back foot contact.

**Fix:**
- Use Gemini Flash (or manual override) to identify actual phase timestamps
- Map key frame indices to real phases
- If Gemini unavailable, use pose heuristics:
  - Back foot contact: frame where both feet touch ground, back foot first
  - Front foot contact: frame where front foot plants
  - Release: frame where bowling arm is most vertical
  - Follow through: frame where bowling arm crosses body

---

## 7. Animation Pacing

**Problem:** Each figure fades in uniformly (0.5s fade + 0.3s hold). Feels mechanical.

**Fix:**
- Faster fade for run-up phases (0.3s) — less interesting
- Slower, more dramatic reveal for release phase (0.8s with slight zoom)
- Add a "flash" effect on the release frame
- Sound design consideration: a subtle "whoosh" per figure reveal

---

## Implementation Priority

| # | Fix | Impact | Effort |
|---|-----|--------|--------|
| 2 | Horizontal separation | Critical — makes it readable | Medium |
| 1 | Bystander removal | Critical — visual noise | Low |
| 4 | Reduce color tint | High — professional look | Trivial |
| 5 | Background brightness | High — context | Trivial |
| 6 | Phase accuracy | Medium — correctness | Medium |
| 3 | Playwright review loop | Medium — QA automation | Medium |
| 7 | Animation pacing | Low — polish | Low |

Fix #2 and #1 first. They transform the output from "tech demo" to "publishable."
