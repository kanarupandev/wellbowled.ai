# Final Research Closeout

Date: 2026-02-26
Status: COMPLETE (for currently available artifacts)

## Final verdicts
1. Delivery detection:
   - Config E is the best current option for non-montage clips.
   - Report both strict (`<=0.2s`) and operational (clip-specific) metrics; do not present mixed-threshold score as a single strict claim.
2. Montage clips remain unsolved:
   - Current E run is unstable in both count and timing on rapid-cut broadcast montage.
3. Speed estimation:
   - Gemini outputs are suitable for pace-band coaching language, not precise speed reporting.
   - YOLO COCO baseline is not viable in current setup.
   - MediaPipe wrist velocity is a useful release proxy, not calibrated km/h.
4. Documentation quality:
   - Several claims are correct directionally but overstate certainty or are stale relative to repo state.

## Independent analysis additions (new)
From raw `result_[A,C,E]_*.json` recomputation:
- Aggregate stability/cost profile:
  - A: lowest latency/cost, good count stability, weaker real-video timing.
  - C: brittle outside smoke test; strongest instability on broadcast.
  - E: highest quality on non-montage timing, highest latency/token cost.
- Aggregate stats:
  - A: `count_mae=0.000`, `ts_var=0.044`, `lat=4.49s`, `tok=2674.8`
  - C: `count_mae=0.200`, `ts_var=0.454`, `lat=5.07s`, `tok=2680.6`
  - E: `count_mae=0.133`, `ts_var=0.374`, `lat=13.39s`, `tok=3997.4`

## Research questions closure table
- Q1 Multi-delivery montage: UNRESOLVED (known failure mode; needs two-pass experiment)
- Q2 Pro vs Flash for expert analysis: UNRESOLVED (no direct head-to-head artifact)
- Q3 Bowling type classification: RESOLVED (coarse classification reliable enough for bands)
- Q4 Multi-pass detection: UNRESOLVED but PRIORITIZED (best next experiment)
- Q5 Live multimodal feasibility: PARTIALLY RESOLVED (polling fallback measured; native-audio path still hypothesis without direct metrics)
- Q6 Resource landscape: PARTIALLY RESOLVED (inventory exists; freshness drift noted)
- Q7 240fps + fine-tuned YOLO: UNRESOLVED (design hypothesis only)
- Q8 Wrist velocity regression: UNRESOLVED (no calibration dataset/labels)

## Decision package (ready to feed Claude)
1. Keep Config E as default for post-session non-montage clips.
2. Update all summary docs to dual-metric reporting (strict + operational).
3. Rephrase Live-audio claims as hypothesis unless direct experiment logs are added.
4. Run next sprint on two-pass montage detection with per-pass telemetry.
5. Maintain claim-to-source mapping before publishing any new headline metric.

## Deliverables index
- `00_index/SCOPE_AND_CLOSEOUT_NOTE.md`
- `00_index/TASK_TRACKER.md`
- `00_index/SESSION_PROGRESS.md`
- `03_recommendations/claude_work_review_2026-02-26.md`
- `03_recommendations/research_continuation_2026-02-26.md`
- `03_recommendations/final_research_closeout_2026-02-26.md`
- `04_sources/results_claim_manifest.md`
