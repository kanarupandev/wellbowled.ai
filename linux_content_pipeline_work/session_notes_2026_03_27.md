# Session Notes — 2026-03-27

## What was accomplished today

### X-Factor Pipeline (morning)
- Built run_v100.py — standalone X-Factor analysis pipeline
- 14 iterations of improvement
- Steyn: 47° ELITE, Bumrah: 41° ELITE — validated
- Comparison video (side-by-side) built
- Verdict card: full scale (Untrained → Amateur → Good → Elite → Peak)
- Background person issue identified as #1 blocker

### Speed Gradient Pipeline (afternoon)
- Researched energy transfer (Ferdinands 2011 real data)
- Built energy flow visualization with color-coded skeleton
- Transfer ratios computed (real measurement, not fake)
- 20-run consistency test: 60/60 identical (deterministic)
- Visual not yet good enough — needs lava/fluid flow feel

### Pipeline Architecture (afternoon)
- 10-stage pipeline designed and reviewed by 3 agents
- Dev spec: 1157 lines, formal manifests, validation gates
- Gemini 3 Pro Preview as brain, MediaPipe as instrument
- SAM 2 Large for bowler isolation
- All stages independently optimizable

### SAM 2 Bowler Isolation (evening) — BREAKTHROUGH
- Built web UI (bowler_selector/app.py) for manual click prompting
- SAM 2 tiny: FAILED (only skin, lost tracking)
- SAM 2 large + 42 manual clicks: **SUCCEEDED**
- Full body isolation: head, arms, torso, legs, shoes
- Dark clothing captured, background kid removed
- Isolated video generated, fullscreen version working
- X-Factor on isolated video: 32.5° — no background person ever annotated

## Key findings

1. **SAM 2 large + multiple clicks = clean isolation.** One bbox or one point fails. Many clicks on the body succeeds.
2. **The isolation solves ALL downstream problems.** MediaPipe on isolated video = perfect single-person detection.
3. **CPU is viable but slow.** 33 min for 111 frames. Mac MPS = 3-5 min. GPU = under 1 min.
4. **Gemini's pixel coordinates are approximate** but good enough for SAM 2 if enough points are given.
5. **The pipeline architecture is sound.** Isolate → Pose → Analyze → Render.

## What to do tomorrow

### Priority 1: Automate SAM 2 prompting
- Ask Gemini Pro 3 for 10-15 body landmarks on best frame
- Feed those as SAM 2 point prompts automatically
- Test if Gemini's approximate coordinates produce clean masks

### Priority 2: Run full pipeline end-to-end
- Isolated video → MediaPipe → Velocity analysis → Speed Gradient render
- Use the isolated_final.mp4 as input
- Produce an actual upload-quality speed gradient video

### Priority 3: Test on broadcast clip
- Use the Steyn SA vs ENG broadcast clip
- SAM 2 isolate Steyn from umpire/batsman/fielders
- Prove it works on the content we'll actually produce

## Files created
- `content/pipeline_v1_linux/stage0.py` — Stage 0: input validation
- `content/pipeline_v1_linux/stage1.py` — Stage 1: Gemini scene understanding
- `content/pipeline_v1_linux/stage2.py` — Stage 2: SAM 2 isolation (automated)
- `content/pipeline_v1_linux/bowler_selector/app.py` — Web UI for manual SAM 2 prompting
- `content/pipeline_v1_linux/bowler_selector/output/` — Isolated bowler outputs
- `linux_content_pipeline_work/pipeline_v1/dev_spec.md` — 1157-line pipeline spec
- `linux_content_pipeline_work/pipeline_v1/reviews/` — 3 agent reviews

## Clips
- `resources/samples/3_sec_1_delivery_nets.mp4` — test clip (nets, 3.7s)
- `resources/samples/steyn_sa_vs_eng_broadcast_5sec.mp4` — broadcast test clip
- `content/pipeline_v1_linux/bowler_selector/output/isolated_final.mp4` — isolated bowler
