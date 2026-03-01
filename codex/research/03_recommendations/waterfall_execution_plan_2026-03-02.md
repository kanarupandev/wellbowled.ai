# Waterfall Execution Plan (Build-on-Current)

Date: 2026-03-02  
Scope path: `/Users/kanarupan/workspace/wellbowled.ai` only

## Objective
Win hackathon by hardening the current Gemini Live experimentation stack and converting it into a reliable demo/submission pipeline.

## Phase Gates

### P1: Reproducible Live Runner
- Restore missing config-driven `interactive_2min` runner artifacts currently referenced by result files.
- Add unit tests for JSON output contract parsing/validation.
- Exit gate: mock run + tests pass.

### P2: Live Reliability Harness
- Add reconnect/session-resumption checks + deterministic logs.
- Ensure no hidden constants (centralize tunables in config).
- Exit gate: repeatable run behavior across at least 3 local runs.

### P3: Demo Narrative Pack
- Tight 3-minute demo blueprint linked to actual outputs from P1/P2.
- Submission scorecard updated with measurable proof points.
- Exit gate: one-pass demo script with fallback branch.

### P4: Final Submission Sweep
- Validate all claims -> source manifest.
- Freeze docs to minimal handoff set.
- Exit gate: final readiness checklist complete.

## Immediate Atomic Task (P1.1)
Status: Completed

Implemented missing `run_interactive_2min.py` + `session_2min_config.json` + `session_2min_mock_config.json` + tests, based on current `experiments/live_audio` outputs.

## Next Atomic Task (P2.1)
Add reliability harness for live mode:
- bounded reconnect/retry policy
- deterministic event schema
- explicit session resumption handle trace in results
