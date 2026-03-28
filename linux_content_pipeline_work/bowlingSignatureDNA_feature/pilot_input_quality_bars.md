# Pilot Input Quality Bars

## Purpose

This note defines the required camera angles, clip quality bars, and parameter coverage rules for the single-bowler Bowling Signature DNA pilot.

The pilot goal is not to prove full automation. The pilot goal is to prove:

1. which views are required to set a high-confidence bowling signature,
2. which parameters can be filled from each view,
3. which parameters remain low-confidence or unset without extra views,
4. what minimum input quality is required before a bowler clip is accepted into the DNA store.

## Core conclusion

One clip from one angle is not enough to set the full parameter set with high confidence.

For seam-bowling archetype classification, the minimum useful view set is:

1. side-on release-side view,
2. front-on or near front-on batter-end view,
3. optional elevated or broadcast diagonal support view.

If only one view is available, the system can still create a partial signature, but it must be flagged as partial and must not claim full parameter coverage.

## Why angle coverage matters

The parameter taxonomy spans:

1. run-up and approach line,
2. gather and bound shape,
3. alignment at back foot contact,
4. alignment and block mechanics at front foot contact,
5. release slot and arm path,
6. follow-through and recovery direction.

No single 2D camera angle exposes all of these reliably. Different views expose different parameter families. The pilot must therefore define:

1. primary views for high-confidence annotation,
2. secondary views for disambiguation,
3. unsupported parameters that should remain unset when the view is inadequate.

## Required angle set

### A. Primary side-on view

Best for:

1. run-up rhythm,
2. gather compactness,
3. bound height and length,
4. front leg technique,
5. trunk flexion and side bend,
6. release timing after front foot contact,
7. release height band,
8. follow-through carry and compactness.

Preferred characteristics:

1. camera roughly perpendicular to bowling direction,
2. full body visible from at least final 6-8 steps through follow-through,
3. minimal zoom changes,
4. release moment unobstructed.

### B. Front-on or near front-on view

Best for:

1. approach line straightness,
2. lateral approach angle,
3. gather alignment,
4. pelvis and shoulder alignment,
5. head position relative to base of support,
6. front foot alignment,
7. release corridor,
8. arm slot family,
9. fall-away direction.

Preferred characteristics:

1. camera centered on the stumps or close to that line,
2. full body visible from bound through early follow-through,
3. no severe telephoto distortion,
4. front foot landing not blocked by batter or umpire.

### C. Diagonal broadcast or elevated support view

Useful for:

1. resolving uncertain alignment calls,
2. checking overall action family,
3. validating run-up geometry,
4. checking finish direction and body carry,
5. supporting descriptive free-text summary.

This view is supportive, not sufficient by itself.

## Coverage by parameter family

### High-confidence with side-on only

Likely annotatable:

1. `run_up_rhythm_family`
2. `acceleration_profile`
3. `gather_compactness`
4. `gather_height_band`
5. `bound_type`
6. `bound_height_band`
7. `bound_length_band`
8. `knee_lift_pattern`
9. `front_knee_family`
10. `front_knee_extension_pattern`
11. `trunk_flexion_band_at_ffc`
12. `trunk_side_bend_band_at_ffc`
13. `release_height_normalized_band`
14. `release_timing_after_ffc_band`
15. `stride_to_release_tempo`
16. `bowling_arm_finish_family`
17. `momentum_carry_family`
18. `finish_compactness_band`

### High-confidence with front-on only

Likely annotatable:

1. `approach_line_straightness`
2. `lateral_approach_angle_band`
3. `gather_alignment_family`
4. `head_alignment_pre_bound`
5. `pelvis_alignment_at_bfc`
6. `shoulder_alignment_at_bfc`
7. `front_foot_alignment_family`
8. `chest_orientation_at_ffc`
9. `release_slot_family`
10. `release_lateral_offset_band`
11. `release_corridor_family`
12. `follow_through_direction_family`
13. `fallaway_family`

### Needs both side-on and front-on for confidence

These should not be set at high confidence from one view alone:

1. `overall_action_family`
2. `arm_path_family`
3. `bowling_arm_verticality_at_ffc`
4. `hips_shoulders_separation_band`
5. `shoulder_counter_rotation_band`
6. `head_position_relative_to_front_foot`
7. `block_strength_family`
8. `balance_over_front_leg_family`
9. `chest_orientation_at_release`
10. `shoulder_alignment_at_release`
11. `whip_vs_hit_family`
12. `uniqueness_score_band`
13. `repeatability_score_band`

### Low-confidence or unsupported from ordinary broadcast views

These should be marked low-confidence, proxy-only, or unset unless very good footage exists:

1. `seam_presentation_proxy_family`
2. `wrist_position_family`
3. `elbow_extension_pattern`
4. exact `back_foot_landing_angle_band`
5. exact `stride_length_normalized_band`
6. exact `release_lateral_offset_band`
7. fine-grained `shoulder_coil_band`
8. exact `early_separation_band`

## Minimum viable view package

For a bowler to enter the pilot DNA store as a high-confidence reference archetype, require:

1. at least one side-on clip,
2. at least one front-on or near front-on clip,
3. each clip includes final approach, gather, bound, release, and follow-through,
4. each clip is at least about 3 seconds around the release sequence,
5. at least one clip shows full body continuously with no cropping at release.

If only one high-quality angle exists, the bowler may enter as:

1. partial signature only,
2. lower-confidence archetype record,
3. not yet cluster-defining.

## Clip construction rule for the pilot

Per angle, create a 3-second analysis clip with:

1. 1.2-1.5 seconds before back foot contact,
2. release phase centered,
3. 1.0-1.5 seconds after release for follow-through.

The pilot should prefer 3-5 clips per bowler:

1. one clean side-on stock ball,
2. one clean front-on stock ball,
3. one diagonal support clip,
4. optional second side-on from another match,
5. optional second front-on from another match.

The purpose is not volume. The purpose is confidence and repeatability across conditions.

## Quality bars

### Accept

1. bowler visible head to toe through release,
2. release frame unobstructed,
3. frame rate sufficient to inspect delivery stride and release timing,
4. camera shake limited,
5. no aggressive replay graphics covering body,
6. enough brightness and contrast to see limb positions.

### Borderline

1. partial occlusion for a small portion of the action,
2. mild zoom movement,
3. moderate compression,
4. one limb briefly unclear but action family still obvious.

Borderline clips may support the free-text description but should not drive hard parameter calls where ambiguity remains.

### Reject

1. bowler cropped at release,
2. front foot or bowling arm hidden at the key moment,
3. replay text or graphics block the body,
4. heavy motion blur prevents phase identification,
5. camera angle too far behind or too far off-axis to infer key alignments,
6. clip too short to include approach into follow-through.

## Annotation confidence policy

Every parameter should carry:

1. value,
2. confidence score,
3. source angle,
4. evidence clip id,
5. annotation notes.

If a view does not support a parameter well, the annotator should:

1. leave it unset,
2. or set a coarse category only,
3. and reduce confidence explicitly.

The pilot must avoid false precision.

## Recommended confidence bands

1. High: clear multi-view evidence or one excellent unambiguous view
2. Medium: usable evidence but some ambiguity remains
3. Low: weak signal, descriptive only, not suitable for hard matching
4. Unset: not observable from the available footage

## Pilot standard for full-parameter claim

The pilot should only claim `full_signature_profile` when:

1. side-on and front-on coverage both exist,
2. at least 70 percent of primary retrieval parameters are high or medium confidence,
3. at least 2 independent clips support the overall action family,
4. no core release or front-foot parameters are inferred from a weak angle alone.

Otherwise the record should be labeled:

1. `partial_signature`,
2. `provisional_archetype`,
3. or `reference_only`.

## Canonical record quality rule

A bowler should not be treated as canonically profiled from one clip alone, even if that clip is excellent.

For a high-trust DNA store:

1. the first record may start from one clip set,
2. later clips from additional matches and angles should be used to confirm or revise the profile,
3. each revised record should preserve provenance,
4. disagreement across clips should be recorded rather than hidden,
5. stable parameters should become high-confidence only after repeated visual confirmation.

The database should favor slower, richer, cross-checked records over rapid low-trust ingestion.

## Recommended first-bowler process

For bowler 1:

1. collect 3-5 clips across the required views,
2. create angle-indexed 3-second cutdowns,
3. annotate each clip separately,
4. merge into one canonical bowler JSON,
5. tag each parameter with confidence and source angle,
6. write a detailed free-text action description,
7. record which parameters were impossible to set cleanly,
8. use the result to revise the input-quality bars before scaling to bowler 2.

## Practical pilot verdict

The single-bowler pilot is primarily a data-requirement exercise.

Success means:

1. identifying the minimum angle package for confident archetype setting,
2. identifying which parameters survive ordinary broadcast footage,
3. identifying which parameters must become coarse categories,
4. defining the acceptance standard for future bowler ingestion.

That is the correct quality-bar objective for pilot bowler 1.

## Scaling model after process refinement

Once the ingestion and annotation process is stable, the database may grow quickly in raw record count. However, growth speed must be separated from confidence level.

### What can scale quickly

Within a short period, the system can likely ingest many provisional bowler records containing:

1. bowler identity and metadata,
2. clip inventory and source provenance,
3. partial parameter fills,
4. coarse archetype labels,
5. detailed free-text action descriptions,
6. provisional retrieval support.

This means the database may plausibly reach hundreds or even thousands of provisional records quickly once the pipeline is standardized.

### What cannot scale at the same speed

High-trust canonical archetype records require slower work:

1. multi-angle confirmation,
2. multi-clip cross-checking,
3. confidence-tagged parameter setting,
4. revision when new evidence appears,
5. stable archetype confirmation across conditions.

These records should not be mass-ingested carelessly.

### Recommended tier model

The DNA store should scale in quality tiers.

#### Tier 1: Canonical reference

Requirements:

1. multi-angle support,
2. multi-clip support,
3. high-confidence core parameters,
4. suitable to act as an archetype anchor,
5. suitable to define or validate clusters.

#### Tier 2: Strong provisional

Requirements:

1. decent clip coverage,
2. partial cross-checking,
3. usable for retrieval,
4. not yet final reference truth.

#### Tier 3: Indexed candidate

Requirements:

1. identity and metadata present,
2. some footage linked,
3. rough or partial parameter fill,
4. descriptive summary present,
5. useful for search expansion, not for gold-standard anchor use.

### Practical scaling rule

Fast growth is acceptable only if the tier is explicit.

The system should therefore allow:

1. rapid expansion of indexed candidates,
2. slower promotion into strong provisional records,
3. even slower promotion into canonical reference records.

This preserves both growth and database trustworthiness.
