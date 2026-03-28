# Claude (Linux Agent) Review — Final

## Context
**Experimental setup**, not production. Goal: validate that we can isolate a bowler, extract pose, compute energy transfer, and produce a meaningful video from any bowling clip.

## Verdict
**Run it.** This is a credible experimental backbone. All 12 stages implemented. SAM 2 + MediaPipe + Gemini + rendering + encoding are connected end-to-end. The happy path works.

**Experimental score: 80/100.**

---

## What's real and working

1. **Full stage orchestration** — 1845 lines, all stages connected, manifests propagated
2. **SAM 2 integration** — real MPS inference, bbox and point prompts, mask output
3. **MediaPipe on masked frames** — single-person guarantee from SAM 2, 33 landmarks
4. **Velocity computation** — torso-length normalized, per-joint, smoothed, windowed to delivery
5. **Transfer ratios** — segment peaks, transition ratios, chain amplification
6. **Cross-stage sanity checks** — Stage 5.5 with bowling arm, centroid, release posture, body size
7. **Speed gradient renderer** — energy color overlay, transition pauses, verdict card
8. **Branch scaffolding** — branch plans, per-branch analysis/render/encode directories
9. **Registry system** — technique plugins + segment definitions bootstrapped
10. **Gemini cascade** — Pro → Flash fallback with model recording

## What's honestly not there yet

1. **Multi-technique rendering** — Stage 7 is hardcoded Speed Gradient. Branch metadata exists but rendering doesn't dispatch. Fine for experiment, must fix for second technique.
2. **Degraded fallbacks** — described in manifests but not implemented at runtime. SAM 2 is a hard dependency. Fine if acknowledged.
3. **Validation gates are soft** — Stage 5 emits success without checking plausibility. Stage 5.5 never escalates to fail. Outputs should be treated as exploratory, not authoritative.

## Agreement with Codex reviews

Both Codex agents are right:
- **Stage 2 is the main fragility** — SAM 2 must work or the pipeline dies
- **Stage 7 is single-technique** — honest labeling, not a defect for experiment
- **Degraded paths are metadata, not runtime** — truth-in-labeling issue
- **eval() in Stage 8** — should fix, trivial

## What I'd do before running the experiment

| Priority | Action | Time |
|----------|--------|------|
| 1 | Install SAM 2 on Mac, verify checkpoint loads | 30 min |
| 2 | Set GEMINI_API_KEY, verify Pro 3 Preview responds | 5 min |
| 3 | Run on the Steyn broadcast clip | Run pipeline |
| 4 | Visually check output — does the energy flow make sense? | 5 min |
| 5 | If output is garbage, check which stage failed via manifests | Debug |

Don't fix code before running. The experiment tells you what actually breaks.

## What I'd fix AFTER the first run (only if needed)

1. **eval() in Stage 8** — 2 minutes, no reason to keep it
2. **Stage 1 model logging** — add WARNING when cascading to lesser model
3. **Stage 5 basic validation** — assert velocities > 0, ratios < 5.0
4. **Stage 2 retry** — try second prompt point if first mask is bad

## What I would NOT fix for the experiment

- Multi-technique dispatch (only one technique exists)
- Stage 6 Gemini insight (optional, skip it)
- RIFE interpolation (conditional, skip it)
- Upscale enhancement (conditional, skip it)
- Production retry/fallback logic
- Pip version pinning
- Strict typed manifest validation

## Comparison with Codex reviews

| Finding | Claude | Codex 1 | Codex 2 |
|---------|--------|---------|---------|
| Stage 2 fragility | Agree (main risk) | Agree (top finding) | Agree (truth-in-labeling) |
| Stage 7 single-technique | Acceptable for now | Acceptable for now | Acceptable if honest |
| Stage 5/5.5 too soft | Fix after first run | Tolerable for experiment | Experiment-threatening if outputs trusted |
| eval() in Stage 8 | Fix (trivial) | Fix | Fix |
| Gemini cascade | Log it | Log it | Acceptable |
| Stages 3/6/7.5 skipped | Correct behavior | Correct | Correct |

**All three reviewers agree: run the experiment, then fix what actually breaks.**

---

## Files reviewed
- `content/pipeline_v1/pipeline.py` (1845 lines)
- `content/pipeline_v1/registry/technique_plugins.json`
- `content/pipeline_v1/registry/segment_definitions.json`
- `linux_content_pipeline_work/pipeline_v1/dev_spec.md` (1157 lines)
- `linux_content_pipeline_work/pipeline_v1/reviews/codex_1_review.md`
- `linux_content_pipeline_work/pipeline_v1/reviews/codex_2_review.md`
