# Pipeline v1 Implementation Reviews

## Reviewers
- Linux Agent (Claude Opus) — architecture/spec review
- Codex Agent 1 — end-to-end issue scan
- Codex Agent 2 — strict spec-compliance review

## Spec reviewed: `dev_spec.md`
## Implementation reviewed: `content/pipeline_v1/pipeline.py` (1845 lines)

---

## MUST FIX (6 issues — pipeline is unreliable without these)

### 1. Stage 2: No degraded fallback for SAM 2 failure
**Severity:** Critical
**File:** `pipeline.py:486`
**Finding:** SAM 2 is imported and initialized unconditionally. If SAM 2, MPS, or checkpoint is unavailable, the entire pipeline hard-fails. No synthetic full-frame mask fallback exists even though the spec requires it for single-person clips.
**Flagged by:** Both Codex agents + Linux agent
**Fix:** Wrap SAM 2 in try/except. If SAM 2 fails AND `scene_report.people_count == 1`, emit all-white (255) masks for every frame, set `isolation_mode = "passthrough_full_frame"`, mark stage as `degraded`. Otherwise fail.

### 2. Stage 2: Validation failures don't retry, silently degrade
**Severity:** Critical
**File:** `pipeline.py:645-673`
**Finding:** When Stage 2 mask quality checks fail (coverage < 90%, centroid drift, area jumps), the stage marks itself `degraded` and returns. The spec requires retry with the next bowler_center_point from Stage 1 before accepting degraded status. Bad masks from a shared stage flow into all downstream stages.
**Flagged by:** Codex Agent 2
**Fix:** On validation failure, retry with next `bowler_center_points[i]` from scene_report (up to 3 retries). Only degrade if all retries fail.

### 3. Stage 4: Degraded pose data flows to analysis unchecked
**Severity:** High
**File:** `pipeline.py:864-875`
**Finding:** When pose quality gates fail (detection_rate < 0.80, torso inconsistency, landmark teleporting), Stage 4 marks itself `degraded` and continues. Measurement branches (speed_gradient, xfactor) should hard-fail on unreliable pose data, not produce garbage analysis.
**Flagged by:** Both Codex agents
**Fix:** If detection_rate < 0.80, fail all measurement-type branches. Non-measurement branches (kinogram/visual-only) may continue degraded.

### 4. Stage 5: No validation, all branches emit "success"
**Severity:** High
**File:** `pipeline.py:963-1047`
**Finding:** Stage 5 computes peaks and ratios but performs zero validation. Every branch is emitted as `success` even when analysis may be empty (no motion detected), ratios are implausible (> 5.0 or < 0.3), or peaks fall outside the delivery window.
**Flagged by:** Codex Agent 2
**Fix:** Add assertions per the spec:
- All velocities > 0 within delivery window
- All ratios between 0.5 and 5.0
- All peak times within delivery window
- Mark branch `degraded` if checks fail, `failed` if critically wrong

### 5. Stage 5.5: All checks downgraded to "warn", never triggers rerun
**Severity:** High
**File:** `pipeline.py:1091`
**Finding:** Every failed sanity check is mapped to `"warn"` with `"rerun_required": False`. This removes the failure semantics the spec established. Bowling arm mismatch, centroid drift, and release posture failures should be hard failures that trigger Stage 2 rerun.
**Flagged by:** Codex Agent 2
**Fix:** Centroid continuity failure and release posture failure → `result: "fail"`, `rerun_required: True`. Bowling arm mismatch → `result: "fail"`. Body size continuity and delivery window → `result: "warn"`.

### 6. eval() in Stage 8
**Severity:** Medium (security)
**File:** `pipeline.py:1644`
**Finding:** `eval()` used to parse ffprobe `r_frame_rate` output (e.g., "30/1"). Unnecessary code execution primitive.
**Flagged by:** Both Codex agents
**Fix:** Replace with:
```python
num, den = r_frame_rate.split("/")
fps = float(num) / float(den)
```

---

## SHOULD FIX (3 issues — spec compliance, not blockers)

### 7. Stage 1: Silent model cascade
**Severity:** Medium-high
**File:** `pipeline.py:40, 324-327`
**Finding:** Code tries `gemini-3-pro-preview` first, silently falls back to `gemini-2.5-pro` then `gemini-2.5-flash`. The spec says use Pro with fail-fast philosophy. Silent downgrade undermines the "best model first" principle.
**Flagged by:** Both Codex agents
**Fix:** Log `WARNING` on every downgrade. Record `model_actually_used` in scene_report. Consider making cascade opt-in via CLI flag `--allow-model-fallback`.

### 8. Stage 7: Hardcoded to speed_gradient renderer
**Severity:** Medium
**File:** `pipeline.py:1345-1498`
**Finding:** Stage 7 renders "SPEED GRADIENT" regardless of branch technique_id or render_template_id. If multiple techniques are routed, they all render identically. The branch loop changes metadata only, not rendering behavior.
**Flagged by:** Both Codex agents
**Fix:** Acceptable for first pass (only speed_gradient in registry). Add `TODO: dispatch to technique-specific renderer based on render_template_id`. When second technique is added, this becomes a real fix.

### 9. Stage 6: Globally disabled
**Severity:** Medium
**File:** `pipeline.py:1185, 1731`
**Finding:** Stage 6 always skips. `allow_stage6: False` is hardcoded in run manifest. The spec defines it as optional but implementable.
**Flagged by:** Codex Agent 2
**Fix:** Acceptable for first pass. Add `--allow-stage6` CLI flag. Implement the Gemini Pro validation call when enabled.

---

## ACCEPTABLE FOR FIRST PASS (no fix needed now)

### 10. Single technique in registry
Only `speed_gradient` in `technique_plugins.json`. Correct — spec says minimum bootstrap is one technique.

### 11. Stages 3, 7.5 skipped
These are conditional by design (upscale only if <480p, RIFE only for ultra-slo-mo). Skipping is correct behavior.

### 12. Multi-technique branch scaffolding structural but untested
Branch plans, branch directories, and branch manifests exist. Not proven with 2+ techniques but the structure is there for when the second technique is added.

### 13. Stage 5.5 centroid check is sampled, not continuous
Checks Stage 1 points against Stage 2 centroids at sampled prompt times only, not a continuous interpolated track. Acceptable approximation for first pass.

### 14. Stage 2 metrics fields for synthetic masks always present
`synthetic_mask_fill_value: 255` and `single_person_gate_passed: False` written even when synthetic masks weren't used. Cosmetic — doesn't affect behavior.

---

## SUMMARY

| Category | Count | Action |
|----------|-------|--------|
| Must fix | 6 | Fix before running on real clips |
| Should fix | 3 | Fix before claiming spec-complete |
| Acceptable | 5 | Ship as-is, improve later |

**Overall verdict:** The pipeline backbone is solid — 1845 lines, all 12 stages implemented, manifests consistent, SAM 2 + MediaPipe + Gemini integrated. The 6 must-fix issues are about validation and fallback, not architecture. Once fixed, this is a real pipeline.
