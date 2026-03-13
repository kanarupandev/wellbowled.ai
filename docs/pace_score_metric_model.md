# Pace Score Metric Model (Canonical)

**Date**: 2026-03-05  
**Repo**: `/Users/kanarupan/workspace/wellbowled.ai`  
**Status**: Active source-of-truth for pace/speed product language and scoring behavior

---

## 1. Product Positioning

The app does **not** claim radar-grade absolute speed measurement.

The app does claim:
1. strong relative pace tracking for improvement
2. clear bucket-level speed context
3. trend visibility over time.

---

## 2. User-Facing Metrics (Final)

## 2.1 Primary: Pace Score

Show a single numeric score:
`Pace Score: 0..100`

Definition:
1. composite relative pace signal from bowling mechanics
2. anchored to user baseline/target, not radar physics
3. interpretable per delivery and per session trend.

UI copy:
- `Pace Score 74/100`
- `Relative pace from your action mechanics (not radar speed).`

## 2.2 Secondary: Rough Speed Bucket

Show a coarse bucket only:
1. `<95 km/h`
2. `95-110 km/h`
3. `110-125 km/h`
4. `125-140 km/h`
5. `140+ km/h`

Label must include roughness:
- `Rough Speed Bucket: 110-125 km/h`

## 2.3 Optional Secondary: Estimated Speed (calibrated only)

Show estimated km/h only when personal calibration quality is sufficient.

Gate:
1. enough calibration samples
2. stable calibration error band
3. confidence at or above configured threshold.

UI example:
- `Estimated Speed: 118 km/h (confidence: medium)`

If gate is not met:
- hide estimated km/h
- keep Pace Score + Rough Speed Bucket only.

## 2.4 Main Outcome: Trend

Trend is the key value:
1. compare session-to-session or week-to-week
2. compare within same rough-speed bucket where possible
3. show percent delta.

UI example:
- `Trend: +3.8% Pace Score vs last week`

---

## 3. Scoring Model (Implementation Contract)

## 3.1 Inputs

For each delivery, build a `paceSignal` from:
1. release wrist angular velocity proxy (`wristOmega`)
2. run-up rhythm quality signal
3. optional stability/quality modifiers from phase consistency.

## 3.2 Bucket-Target Normalization

Per bucket, maintain a personal target signal:
1. rolling high percentile from recent valid deliveries in that bucket
2. update target asynchronously as more deliveries are observed.

Recommended default:
`bucketTargetSignal = p90(last 30 valid deliveries in bucket)`

## 3.3 Pace Score Formula

`PaceScore = clamp(100 * paceSignal / bucketTargetSignal, 0, 100)`

Notes:
1. deterministic clamp and rounding rules are required
2. compare only against same-bucket target to avoid misleading cross-effort scoring.

## 3.4 Confidence Rules

Confidence applies to estimated km/h, not Pace Score visibility.

Confidence factors:
1. calibration sample count
2. residual spread/error
3. signal quality for current delivery.

Confidence levels:
1. low
2. medium
3. high

---

## 4. Copy Rules (Strict)

Allowed:
1. `Pace Score`
2. `Rough Speed Bucket`
3. `Estimated Speed` (only when calibrated, with confidence)
4. `Trend`.

Disallowed:
1. `exact speed`
2. `radar accurate`
3. `DRS-grade speed`.

---

## 5. Release Acceptance Criteria

1. Every delivery shows `Pace Score` and `Rough Speed Bucket`.
2. Estimated km/h is hidden when calibration gate is not met.
3. Estimated km/h always shows confidence when visible.
4. Trend is shown as percent delta over a defined baseline window.
5. No UI copy claims precise/radar-grade speed.

---

## 6. Relationship to Existing Docs

This document supersedes older ambiguous wording in:
1. `architecture_decision.md` speed sections
2. any place that implies precise live speed.

For implementation details, pair this with:
1. `live_delivery_deep_analysis_requirements.md`
2. `project_dev_deploy_guide.md`
3. `dev_process.md`.
