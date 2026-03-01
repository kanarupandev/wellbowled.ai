# wellBowled Project Dev + Deployment Guide

This document is project-specific.  
The generic process rules remain in [dev_process.md](/Users/kanarupan/workspace/wellbowled.ai/docs/dev_process.md).

## 1) Purpose

Translate the generic process into concrete execution steps for this project:
- multimodal cricket delivery detection experiments in this repo
- iOS app implementation in external repo (`wellBowled`)
- hackathon deployment as a demo-ready iPhone build (not production infra)

## 2) Current Source of Truth

- Product/use-case: [session_onboarding.md](/Users/kanarupan/workspace/wellbowled.ai/docs/session_onboarding.md)
- Architecture and validated vs hypothesis tags: [architecture_decision.md](/Users/kanarupan/workspace/wellbowled.ai/docs/architecture_decision.md)
- Research outcomes and open questions: [research/README.md](/Users/kanarupan/workspace/wellbowled.ai/research/README.md)
- Repository map and external iOS file status: [SITEMAP.md](/Users/kanarupan/workspace/wellbowled.ai/docs/SITEMAP.md)

## 3) Repos and Ownership

1. This repo (`wellbowled.ai`) holds:
- docs
- research
- experiments and raw validation artifacts

2. External iOS repo (`wellBowled`) holds:
- Swift app code
- XCTest coverage
- actual on-device integration implementation

Path reference from process doc: `/Users/kanarupan/workspace/wellBowled/ios/wellBowled/`.

## 4) Project-Specific Development Flow

Mapped to generic steps in [dev_process.md](/Users/kanarupan/workspace/wellbowled.ai/docs/dev_process.md):

1. Understand
- Confirm target slice: Tier 1 MVP loop first.
- Explicitly separate validated capability vs hypothesis in planning notes.

2. Research
- Use [research/README.md](/Users/kanarupan/workspace/wellbowled.ai/research/README.md) as index.
- Do not restate old conclusions without checking latest commit trail.

3. Experiment
- Run scripts in `experiments/` with config-driven settings.
- Record exact command, input clip, output artifact path, and pass/fail threshold.

4. Verify
- Update docs with `VALIDATED` or `HYPOTHESIS`.
- If conflicting claims exist, fix contradiction before next implementation task.

5. Plan
- Plan smallest vertical slice that improves Tier 1 MVP:
`detect -> local count TTS -> live conversation -> post-session clip analysis`.

6. Test-first + implement
- Add/extend unit tests in `experiments/test_parsers.py` (and new focused test files as needed).
- Keep constants in [experiments/shared_config.py](/Users/kanarupan/workspace/wellbowled.ai/experiments/shared_config.py), avoid hardcoded runtime literals.

7. Verify again
- Minimum check:
`python3 -m unittest discover -s experiments -p 'test_parsers.py' -v`
- Capture result in commit message body or follow-up doc sync when behavior changed.

8. Document
- Sync affected docs in same workstream.
- Add cross references, avoid orphan claims.

## 5) Coding Constraints (This Project)

1. No production infra additions for hackathon scope.
2. Speed outputs must be framed as exploratory/uncalibrated pace bands unless radar-calibrated evidence exists.
3. Live API behavior assumptions must match validated conversational-turn model behavior.
4. Any iOS status claim in this repo must be marked external/unverified unless backed by local code in this repo.

## 6) Commit Journal Rules (Multi-Agent)

1. Codex commits must use `codex:` prefix.
2. Keep commits incremental and scoped (one change theme per commit).
3. Do not mix unrelated doc cleanup with code behavior changes.
4. Before editing files touched by other agents, re-read latest commits and current file state.

## 7) Hackathon Deployment Steps (Project-Specific)

Definition here: deployment means demo-ready iPhone app delivery, not production backend rollout.

1. Pre-deploy checklist
- Tier 1 flow verified end-to-end on device (or explicitly marked partial).
- Test suite for experiment utilities green.
- Docs aligned: onboarding, architecture, research index.

2. iOS build prep (external repo)
- Open external `wellBowled` Xcode project.
- Configure API key flow via app settings/runtime prompt (no hardcoded secret).
- Ensure required assets/models are bundled if needed for on-device detection.

3. Device validation run
- Run one full session:
record -> detect/count -> live question/response -> end session -> clip analysis.
- Capture demo-safe evidence (timestamps, screenshots, short recording).

4. Demo package
- Freeze branch/commit used for demo.
- Prepare one-page runbook:
startup, permissions, happy path, fallback path if network degrades.
- Use pace bands (not precise kph) in UI copy and spoken/demo narrative.

5. Fallback mode for demo stability
- If Live API is unstable in venue conditions:
switch to fallback flow documented in [architecture_decision.md](/Users/kanarupan/workspace/wellbowled.ai/docs/architecture_decision.md) (Option C) and state it transparently.

## 8) Quick Command Reference

From this repo:

```bash
git log --oneline -15
python3 -m unittest discover -s experiments -p 'test_parsers.py' -v
```

Useful file anchors:
- [experiments/shared_config.py](/Users/kanarupan/workspace/wellbowled.ai/experiments/shared_config.py)
- [experiments/delivery_detection/detect.py](/Users/kanarupan/workspace/wellbowled.ai/experiments/delivery_detection/detect.py)
- [experiments/live_speed/simulate_live.py](/Users/kanarupan/workspace/wellbowled.ai/experiments/live_speed/simulate_live.py)
- [experiments/live_speed/speed_gemini.py](/Users/kanarupan/workspace/wellbowled.ai/experiments/live_speed/speed_gemini.py)

