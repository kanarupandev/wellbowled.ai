# Research Task Tracker

Last updated: 2026-03-02
Owner: Codex (research continuity lane)
Scope rule: Read from `/Users/kanarupan/workspace/wellbowled.ai`, write only to `/Users/kanarupan/workspace/wellbowled.ai/codex`.

## Active objective
Ship live feedback + challenge loop as production-ready as possible by today's deadline (2-hour push window), with live demo path prioritized over secondary features.

## Non-negotiable language rule
- Product positioning must use `expert buddy` terminology.
- Avoid `coach`, `coaching`, and similar labels in UI copy unless explicitly approved.

## Task board

| ID | Task | Status | Evidence/Output | Next action |
|---|---|---|---|---|
| T1 | Audit Claude work (code + docs + outcomes) | Done | `03_recommendations/claude_work_review_2026-02-26.md` | Apply corrections upstream |
| T2 | Normalize metrics framing (strict vs mixed threshold) | Done | `03_recommendations/research_continuation_2026-02-26.md` | Sync upstream summary docs |
| T3 | Independent recomputation from raw JSON | Done | `03_recommendations/final_research_closeout_2026-02-26.md` | Re-run when new experiments land |
| T4 | Speed consistency reassessment | Done | Continuation + closeout memos | Convert to product-safe output language |
| T5 | Define next executable sprint | Done | Continuation memo (two-pass montage spec) | Execute experiment in next build cycle |
| T6 | Claim-to-source governance | Done | `04_sources/results_claim_manifest.md` | Keep updated with every new claim |
| T7 | Scope note + final closeout package | Done | `00_index/SCOPE_AND_CLOSEOUT_NOTE.md`, closeout memo | Handoff to Claude/user |
| T8 | Deep Live API hackathon configuration research | Done | `03_recommendations/live_api_hackathon_config_2026-02-26.md` | Implement config in app session setup |
| T9 | UX-first flowchart + interaction model | Done | `03_recommendations/hackathon_flowchart_ux_2026-02-26.md` | Review and finalize UI wireframes |
| T10 | Waterfall execution roadmap (build-on-current) | Done | `03_recommendations/waterfall_execution_plan_2026-03-02.md` | Execute P1.1 runner restore |
| T11 | Restore missing interactive_2min runner + configs | Done | `experiments/live_audio/run_interactive_2min.py`, config + tests | Start P2 reliability harness |
| T12 | Live reliability harness (resumption/retry + deterministic logs) | In Progress | Waterfall plan P2 | Implement bounded retry + structured events |
| T13 | Live-first 4-minute demo plan (3:00 live/challenge + 1:00 secondary) | Done | `submission/2026_demo_blueprint_4min_live_first.md` | Use as recording script |
| T14 | Deadline directive capture (today, 2-hour production push) | Done | `00_index/SESSION_PROGRESS.md` | Execute implementation sprint in source repo |
| T15 | Terminology alignment: replace coaching language with expert-buddy language | Pending | This tracker note | Sweep UI strings and prompts at final polish pass |

## Completion statement
All research possible from current repo artifacts has been completed and documented. Remaining unknowns are explicitly marked as requiring new experiments/data.
