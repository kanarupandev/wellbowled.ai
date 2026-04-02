# Bowling DNA Vector Store Design

## Status

Design plan only.
No implementation in this document.

## Purpose

Design a bowling-signature vector store for:
- identifying a user's nearest bowler match
- using partially observed parameters from a user video
- returning similarity percentages
- supporting both consumer-style outputs and coach-facing reports

Current intention:
- start with a pilot of top 10 prominent bowlers
- focus on seam bowling first
- use reliable public sources
- separate signature features from career/profile metadata

## Core Design Principle

**Do not mix “bowling identity signature” and “career achievements” into one undifferentiated matching vector.**

Reason:
- a user video reveals action/style information
- it does not reliably reveal career outcomes such as total wickets, ICC ranking, or highest historical speed
- those fields are useful for profile display and context, but should not dominate nearest-bowler retrieval

So the design should use two layers:

### Layer 1: Signature Retrieval Layer
Used for actual nearest-bowler matching.
Contains:
- observable or inferable action/style parameters
- phase-wise categorical and ordinal features
- selected normalized quantitative features from video

### Layer 2: Profile Metadata Layer
Used for:
- presentation
- filtering
- storytelling
- coach-facing context

Contains:
- height
- dominant formats
- career wickets
- rankings
- best figures
- stock speed range
- highest recorded speed
- IPL teams, era, country, etc.

These fields should not drive the primary retrieval score unless explicitly modeled as a low-weight secondary prior.

## Pilot Scope

Pilot only for 10 bowlers.
Recommendation: choose bowlers with strong public recognition and clearly differentiated signatures.

## Recommended Pilot Bowlers

1. Jasprit Bumrah
2. Mitchell Starc
3. Pat Cummins
4. Kagiso Rabada
5. Josh Hazlewood
6. Jofra Archer
7. Shaheen Shah Afridi
8. Mohammed Shami
9. Dale Steyn
10. Lasith Malinga

Why this set:
- global recognition
- strong variation in action types
- mix of right-arm and left-arm pace
- includes both textbook and highly unusual signatures
- useful for content and coaching

## Data Model Overview

Each bowler should be represented as a structured bundle, not a single flat blob.

Recommended object families:
- `bowler_identity`
- `signature_profile`
- `career_profile`
- `reference_clip_index`
- `source_provenance`

## Chunking Strategy

Each bowler should be stored as multiple chunks/documents.
This is better than one huge document.

### Chunk 1: Canonical Identity Chunk
Purpose:
- stable metadata
- filters
- label/display data

Fields:
- bowler_id
- display_name
- country
- bowling_family = seam
- bowling_arm
- role
- batting_style
- bowling_style
- active_or_retired
- primary_era
- height_cm
- dominant_formats
- source_refs

### Chunk 2: Signature Profile Chunk
Purpose:
- primary retrieval unit
- phase-wise categorical signature
- observable action identity

Fields:
- bowler_id
- signature_version
- phase_descriptors
- categorical_params
- ordinal_params
- quantitative_normalized_params
- reliability_scores
- source_refs

This is the main vectorizable or hybrid-matchable chunk.

### Chunk 3: Career Profile Chunk
Purpose:
- contextual metadata
- profile enrichment
- coach/report output

Fields:
- bowler_id
- international_wickets_by_format
- IPL wickets
- bowling_averages_by_format
- economy_by_format
- best figures by format
- current_or_peak_rankings
- stock_speed_range_kph
- highest_recorded_speed_kph
- awards_or_notable_achievements
- source_refs

### Chunk 4: Reference Clip Index Chunk
Purpose:
- production support
- explainability
- future grounding for visual comparisons

Fields:
- bowler_id
- clip_id
- source_type
- source_url
- clip_context
- format
- camera_angle
- delivery_quality_score
- visibility_score
- phase_coverage
- usage_notes

### Chunk 5: Provenance Chunk
Purpose:
- auditability
- data quality tracking

Fields:
- bowler_id
- source_catalog
- collection_date
- last_verified_date
- field_level_source_map
- reliability_tier_map
- unresolved_fields

## Parameter Taxonomy

The long-term taxonomy can exceed 100 parameters.
That is acceptable as a target design.

However, for the pilot, retrieval should likely rely on a smaller high-signal subset.

Recommended structure:
- full taxonomy defined now
- pilot retrieval subset defined separately

## Parameter Families

### A. Static Profile Parameters
These are useful metadata fields.
Not all should be used in primary retrieval.

Examples:
- height_cm
- body_type_stocky_slender_enum
- dominant_formats
- age_band
- era_band
- bowling_arm
- bowling_style_label
- stock_speed_band
- peak_speed_band
- highest_recorded_speed_kph
- total_international_wickets
- IPL_wickets
- ICC_peak_ranking

### B. Run-Up / Approach Parameters
Examples:
- run_up_length_short_medium_long
- run_up_rhythm_smooth_staccato_accelerating
- acceleration_profile_flat_building_late_surge
- lateral_approach_angle
- pre_gather_posture_upright_forward_leaning
- arm_carry_style
- head_stability_in_approach
- foot cadence density
- final_step_intensity
- approach symmetry

### C. Gather / Load Parameters
Examples:
- gather_compactness
- gather_height
- gather_alignment_side_on_semi_open_open
- bowling_arm_pre_load_position
- front_arm_pre_load_position
- shoulder_coil_degree_band
- trunk_rotation_pre_load
- center_of_mass_drop
- load_pause_presence
- wrist_set_visibility

### D. Bound / Pre-BFC Parameters
Examples:
- bound_type_low_medium_high
- bound_length
- bound_direction_straight_lateral_closed_open
- airborne_time_band
- knee_lift_pattern
- torso_shape_in_bound
- head_path_during_bound
- hip_rotation_into_bound
- front_arm_shape_in_bound
- bowling_arm_path_in_bound

### E. Back Foot Contact Parameters
Examples:
- back_foot_landing_angle
- back_foot_alignment
- hips_at_bfc
- shoulders_at_bfc
- trunk_tilt_at_bfc
- head_alignment_at_bfc
- rear_leg_flexion_band
- front_knee_height_at_bfc
- front_arm_position_at_bfc
- bowling_elbow_height_at_bfc

### F. Front Foot Contact Parameters
Examples:
- front_foot_stride_length_normalized
- front_foot_alignment_closed_neutral_open
- front_knee_brace_pattern
- trunk_flexion_at_ffc
- trunk_side_bend_at_ffc
- hips_shoulders_separation_band
- head_position_relative_to_front_foot
- release_corridor_alignment
- front_arm_pull_pattern
- bowling_arm_verticality_at_ffc

### G. Release Parameters
Examples:
- release_height_normalized
- release_point_lateral_offset
- release_slot_high_3q_sling_round
- wrist_position_at_release
- seam_presentation_proxy
- head_position_at_release
- shoulder_alignment_at_release
- chest_orientation_at_release
- bowling_elbow_extension_pattern
- non_bowling_arm_terminal_position
- release_timing_after_ffc
- stride_to_release_tempo

### H. Follow-Through Parameters
Examples:
- follow_through_direction
- momentum_carry_straight_across
- recovery_balance
- bowling_arm_finish_pattern
- trunk_finish_pattern
- rear_leg_recovery_pattern
- deceleration_type
- head_stability_post_release
- off_side_vs_leg_side_fallaway
- finish_compactness

### I. Higher-Level Signature Parameters
Examples:
- overall_action_family
- release_family
- run_up_family
- whip_vs_hit_pattern
- seam_bowling_archetype
- deception_style
- repeatability_score
- violence_of_action_score
- smoothness_score
- slingshot_score
- textbookness_score
- uniqueness_score

## Retrieval Feature Classes

Not all parameters are equally useful.
Create three classes.

### Class A: Primary Match Features
Used directly for nearest-bowler retrieval.
Examples:
- bowling_arm
- release_slot
- run_up rhythm
- gather style
- front arm action
- hip-shoulder separation family
- front foot alignment
- release height normalized
- follow-through family
- overall action family

### Class B: Secondary Match Features
Used when available, but with lower weight.
Examples:
- stride length normalized
- height band
- stock speed band
- body type band
- release timing band

### Class C: Presentation-Only Features
Not used in core retrieval score.
Examples:
- total wickets
- IPL wickets
- ICC peak ranking
- awards
- highest recorded speed
- best bowling figures

## Matching Logic

The user idea is correct:
- extract a subset of parameters from the user video
- compare against the bowler pool
- retrieve nearest matches with percentages

Recommended matching design:

### Step 1: Hard filters
Before scoring, filter candidate pool by:
- bowling_family = seam
- bowling_arm
- optionally release_family or major action family if high-confidence

### Step 2: Weighted param match
Compute a similarity score over only the parameters available from the user video.

Score should use:
- parameter weight
- parameter reliability
- source confidence
- missingness handling

### Step 3: Percentage output
Return:
- top 3 nearest bowlers
- similarity percentage
- confidence percentage
- strongest matching parameters
- strongest differentiating parameters

### Step 4: Separate display context
Then enrich results with:
- height
- stock speed
- highest speed
- wickets
- notable achievements
- reference clips

These should explain the result, not determine it heavily.

## Suggested Similarity Formula

Conceptually:

`similarity = weighted_match_sum / weighted_available_sum`

Where:
- only user-observed fields are included in denominator
- categorical matches use exact or distance-based similarity
- ordinal fields use band proximity
- normalized quantitative fields use scaled distance
- fields with weak reliability are downweighted

Return:
- `match_percent`
- `confidence_percent`

Where `confidence_percent` depends on:
- number of available primary features
- visibility quality
- camera-angle suitability
- reliability of extracted parameters

## Why Career Stats Should Be Separate

Fields such as:
- height
- stock speed
- highest recorded speed
- wickets
- rankings
- awards

are valuable.
But they should mostly be:
- metadata
- display context
- optional low-weight prior fields

Reason:
A user may bowl with a Starc-like action without bowling 150+ kph.
If speed and wickets dominate matching, retrieval becomes aspirational-biographical instead of action-signature based.

## Reliable Source Strategy

Use source tiers.
Do not treat all fields equally.

### Tier A — Primary / strong sources
Use first whenever available.

Recommended Tier A sources:
- ICC player profiles for role, batting style, bowling style, date of birth, team context
- ESPNcricinfo player profiles and Statsguru for wickets, averages, best figures, format-by-format career stats
- official IPL / franchise / national-board pages where specific official player details are published

Examples found during research:
- ICC player profile pages, e.g. Jasprit Bumrah profile
- ESPNcricinfo Statsguru/player profile pages
- IPL official articles for certain speed references

### Tier B — strong secondary sources
Use when Tier A does not provide the field.

Recommended Tier B sources:
- Cricbuzz profiles for quick structured career summaries and style info
- reputable official team or tournament pages
- major cricket publishers with cited stat context

### Tier C — fallback only
Use sparingly and mark explicitly.

Recommended Tier C sources:
- Wikipedia or Wikidata for height and other difficult-to-source biography fields
- media articles for isolated speed-gun facts when no better source exists

If Tier C is used:
- mark the field as lower confidence
- store the exact citation
- prefer later replacement by better source

## Sourceability By Field Type

### Easy to source reliably
- bowling arm
- bowling style label
- role
- country
- DOB
- format-by-format wickets
- bowling averages
- best figures
- rankings

### Medium difficulty
- height
- stock speed range
- highest recorded speed
- body type classification
- primary archetype label

### Hard / requires expert annotation
- run-up rhythm family
- gather compactness
- front arm pattern
- release family
- follow-through family
- uniqueness score
- smoothness score
- textbookness score

These hard fields should be expert-labeled from reference clips, not scraped from public profiles.

## Pilot Annotation Plan For Top 10 Bowlers

For each pilot bowler, collect:

### 1. Metadata package
From ICC / ESPNcricinfo / Cricbuzz / official sources:
- full name
- country
- bowling arm
- bowling style
- role
- DOB
- height if available
- current or peak rankings
- format-by-format wickets
- IPL wickets if applicable
- stock speed range if reliably available
- highest recorded speed if reliably available

### 2. Clip package
Create a small clip bank:
- 3 to 5 good reference clips per bowler
- preferably side-on or behind-the-arm angles
- clear delivery stride visibility
- one or more high-quality release moments

### 3. Manual signature annotation
Label phase-wise signature fields for each bowler.

### 4. Canonical signature profile
Collapse clip observations into a canonical bowler signature with confidence bands.

## Recommended Pilot Output Format

For each bowler, produce:
- one canonical identity chunk
- one signature profile chunk
- one career profile chunk
- one reference clip chunk
- one provenance chunk

This creates a manageable pilot dataset with strong explainability.

## Suggested Bowler Profile Example Fields

Example bowler object:
- `bowler_id`: `jasprit_bumrah`
- `signature_version`: `v1`
- `bowling_family`: `seam`
- `arm`: `right`
- `action_family`: `sling_fast_compact`
- `release_slot`: `low_3q_sling`
- `run_up_rhythm`: `short_accelerating`
- `front_arm_pattern`: `sharp_pull_compact`
- `follow_through_family`: `compact_across_body`
- `height_cm`: `178`
- `stock_speed_band`: `140_145`
- `highest_recorded_speed_kph`: `153`
- `test_wickets`: `...`
- `odi_wickets`: `...`
- `t20i_wickets`: `...`
- `ipl_wickets`: `...`

Important:
Only some of those belong in primary retrieval.

## MVP Recommendation

For the pilot, do not begin with 100 weighted parameters in live retrieval.

Recommended MVP retrieval set:
- 20 to 30 high-signal signature parameters
- plus 5 to 10 optional secondary priors
- with the full taxonomy documented for later expansion

This reduces noise and makes debugging easier.

## Final Recommendation

Build the pilot as a **hybrid param store**, not just a generic vector embedding store.

Meaning:
- structured fields first
- weighted matching second
- optional learned embedding later

Why:
- explainable
- coach-friendly
- easier to debug
- better for percentage outputs
- easier to enforce phase-wise cricket logic

## Pilot Deliverable Recommendation

For now, the design-phase deliverable should be:
1. top-10 pilot bowler list
2. field taxonomy with retrieval classes
3. chunk schema
4. source tiering rules
5. annotation template
6. scoring logic spec

No implementation yet.

## Sources Used For This Design Direction

- ICC player profile example: https://www.icc-cricket.com/tournaments/mens-t20-world-cup-2026/teams/4/players/63755/jasprit-bumrah
- ESPNcricinfo Statsguru/player profile example: https://stats.espncricinfo.com/ci/engine/player/625383.html?class=11;type=bowling
- Cricbuzz player profile example: https://www.cricbuzz.com/profiles/9311/jasprit-bumrah
- IPL official speed context example: https://www.ipl.com/cricket/print/news/top-5-fastest-deliveries-in-cricket-history-2025/

## Source Quality Note

These sources are suitable for design planning.
For production data collection:
- prefer ICC and ESPNcricinfo first
- use Cricbuzz as a strong secondary source
- use Wikipedia/Wikidata only as a fallback for hard biography fields such as height, with explicit low-confidence tagging
