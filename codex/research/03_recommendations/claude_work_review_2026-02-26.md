# Claude Work Review (Read-Only Audit)

Date: 2026-02-26
Scope: Reviewed files across `/Users/kanarupan/workspace/wellbowled.ai`; wrote notes only under `codex/`.

## Executive take
Strong experimentation and good raw artifacts, but several docs overstate certainty or drift from current repo reality. Biggest issue is inconsistent evaluation criteria (mixed 0.2s/0.3s thresholds), which can mislead product decisions.

## Priority corrections for Claude

### P0 — Metric framing inconsistency in Phase 2 summary
- Evidence:
  - `experiments/delivery_detection/phase2_configs.md` labels Config E as `6/7 PASS` while using mixed thresholds (0.2s for broadcast, 0.3s for nets).
  - Lines: Winner/table sections around `6/7 PASS` and per-row thresholds.
- Why this matters:
  - `6/7` sounds like a single uniform metric, but it is not directly comparable to a strict `<0.2s` target.
- Correction:
  - Report two metrics explicitly:
    1. `Pass @0.2s` (strict)
    2. `Pass @video-specific threshold` (operational)
  - Keep `6/7` only if labeled as mixed-threshold operational score.

### P0 — Live API claim is partially speculative in architecture doc
- Evidence:
  - `docs/architecture_decision.md` says native audio path is tested and frames it as settled: "Audio is the way forward... Tested Feb 2026".
  - `experiments/live_speed/results.md` and `research/README.md` indicate actual tested workaround used polling with `generateContent` and explicitly says next step is native-audio experiment.
- Why this matters:
  - Current wording reads like end-to-end native-audio live streaming has already been validated.
- Correction:
  - Change wording to: "promising direction / hypothesis" unless there is a dedicated native-audio experiment log with measured detection metrics.

### P1 — Onboarding doc is stale relative to repo + findings
- Evidence:
  - `docs/session_onboarding.md` states engine is "Gemini 3 Flash (Multimodal Live API)".
  - Same file lists `backend/`, `ios/`, `prompts/` directories that are not present in this repo snapshot.
- Why this matters:
  - New contributors will immediately get incorrect architecture and repo map.
- Correction:
  - Update to current structure (`docs/`, `experiments/`, `research/`, etc.) and clarify live mode status as experimental.

### P1 — Versioned result sets are mixed without canonical source labeling
- Evidence:
  - Multiple overlapping result families exist (`result_*.json`, `result_A/C/E_*.json`, `001_results.json`, `002_results.json`, etc.) with different prompts/runs/modes.
- Why this matters:
  - Easy to cherry-pick or accidentally compare non-equivalent runs.
- Correction:
  - Add one canonical "results manifest" file mapping which JSON set backs each claim in docs.
  - Mark older runs as archived/baseline to prevent accidental reuse.

### P1 — "TRAINING-DATA" sections are useful but need stronger quarantine
- Evidence:
  - `docs/prompting_techniques.md` already marks TRAINING-DATA, but those sections are interleaved with verified claims.
- Why this matters:
  - Readers may treat speculative values (sampling, precision, windows) as production facts.
- Correction:
  - Split into two sections: `Verified from repo experiments` vs `External assumptions to verify`.
  - Add "Do not use for product decisions until validated" banner on assumptions section.

### P2 — Date freshness drift in resource inventory
- Evidence:
  - `research/cricket_resources.md` says last updated `2025-02-25`, while docs elsewhere are framed around Feb 2026 work.
- Why this matters:
  - Signals potential staleness for external datasets/models.
- Correction:
  - Re-verify top-priority links and refresh "last verified" date.

## Data-backed checks I ran

From `experiments/delivery_detection/result_{A,C,E}_*.json`:
- Config E improves real-video accuracy versus A/C in this dataset.
- Reported `6/7` for Config E is valid only under mixed thresholds (0.2 and 0.3 depending on clip).
- On strict `<=0.2s`, Config E is lower than 6/7.

From `experiments/live_speed/result_live_detection.json`:
- Polling fallback captured 2/4 deliveries with 1 phantom, matching the write-up.

From `experiments/live_speed/result_speed_gemini.json`:
- Per-delivery means cluster around mid/high 90s kph; classification consistency is reasonable for coarse coaching bands.

## Suggested concise message to feed Claude

"Your experiment depth is strong, but docs need calibration: (1) split strict vs mixed-threshold accuracy in Phase 2 (don’t present 6/7 as single-metric truth), (2) downgrade native-audio Live API wording from validated conclusion to hypothesis unless you add direct experiment evidence, (3) fix stale onboarding repo map/engine statement, and (4) add a canonical results manifest so each claim traces to one JSON family."
