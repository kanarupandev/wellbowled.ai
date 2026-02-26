# Research Continuation Memo

Date: 2026-02-26
Purpose: Continue research from existing results with new quantitative synthesis and clear next-sprint experiment design.

## 1) Fresh quantitative synthesis (from raw JSON)

### Delivery detection (A/C/E) summary

| Config | Strict pass @0.2s | Operational pass @0.3s | Mean abs error trend | Bias trend |
|---|---|---|---|---|
| A | Strong on simple clips, weak on long nets | Better at 0.3s but still inconsistent | Moderate | Mixed (early on broadcast, late on nets) |
| C | Smoke-test-only success | Fails on broadcast; fragile overall | Worst | Strong early bias on broadcast |
| E | Best overall in current dataset | Highest operational pass among tested configs | Best on non-montage clips | Slight late bias overall |

Important: the common headline `6/7 PASS` for Config E is not a strict single-threshold claim; it combines clip-specific thresholds.

### Montage failure signature (Config E, bumrah)
- Count instability across runs: detected 5, 8, and 6 vs GT 7.
- Latency/tokens instability: one run had very high thought tokens (8107) and 50.42s latency; others were much lower (~13s).
- Interpretation: rapid cuts + replay-like context likely trigger unstable reasoning paths and inconsistent counting.

### Speed estimation stability (Gemini 3 Pro runs)
- Per-clip mean speeds: 98.6, 96.4, 98.2, 98.2 kph.
- Cross-delivery spread: ~2.2 kph for same bowler/session.
- Per-run spread within a clip remains wider (roughly low-90s to 105).
- Practical framing: reliable pace banding for coaching context, not precise ball-speed measurement.

## 2) New insight not explicitly captured in current upstream docs
1. There are two different failure regimes:
   - Regime A: long nets clips (timing drift) where E mostly recovers.
   - Regime B: montage clips (count instability + variable reasoning depth), where E remains unreliable.
2. Config C brittleness is directional, not random: strong early bias on broadcast clips suggests metadata/schema constraints can anchor to wrong temporal semantics.
3. For product metrics, strict and operational scores should always be published together to prevent accidental overclaiming.

## 3) Recommended next research sprint (Q1 + Q4)

### Hypothesis
A two-pass detector will improve montage robustness by separating counting from precise localization.

### Proposed method
1. Pass 1 (coarse): detect candidate delivery windows with generous tolerance and replay filtering.
2. Pass 2 (refine): run per-window timestamp refinement on 1-2s subclips.
3. Aggregation: deduplicate near-duplicate timestamps and enforce plausible inter-delivery spacing.

### Success criteria
- Montage clip (`bumrah`) count closer to GT 7 with lower run-to-run variance.
- Strict metric gain vs current E baseline on montage.
- Latency remains acceptable for post-session (not live).

### Instrumentation requirements
- Persist per-pass raw outputs (candidate windows, refined timestamps, dropped duplicates).
- Track per-pass token/latency to quantify cost of robustness.
- Emit both strict and operational pass scores in results table.

## 4) Concrete handoff message
"Continuation complete: metrics were recomputed from raw JSON and documented with strict-vs-operational separation. Config E remains best overall, but montage behavior is still unstable due to count variance and reasoning spikes. Next sprint should run a two-pass montage-focused experiment (coarse count + local refine) with per-pass telemetry and dual-metric reporting."
