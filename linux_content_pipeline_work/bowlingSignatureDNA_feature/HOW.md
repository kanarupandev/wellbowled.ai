# HOW

## Research Basis

This design direction is based on cricket fast bowling biomechanics literature, especially around:
- action classifications such as side-on / front-on / semi-open / mixed
- back foot contact and front foot contact mechanics
- shoulder counter-rotation
- hip-shoulder separation
- front leg technique families
- proximal-to-distal sequencing
- release-speed related technique characteristics

Representative primary sources include:
- Bartlett et al. 1996 review of fast bowling biomechanics
- Ranson et al. 2008 lower trunk motion and action classification
- Senington et al. 2018 on shoulder counter-rotation and hip-shoulder separation
- Schaefer et al. 2020 on action-type comparison
- Felton et al. 2020 and 2023 on front foot contact optimization
- Ferdinands et al. 2026 on front leg mechanics
- Thiagarajan et al. 2011 on segmental kinetic energy sequencing

## Design Principle

The pilot should be a **hybrid structured retrieval system**, not a pure black-box vector database.

Recommended order:
1. structured ontology
2. chunked bowler records
3. weighted param matching
4. optional vector/embedding layer later

Reason:
- more explainable
- better for percentages
- easier to debug
- more coach-friendly
- easier to keep cricket logic intact

## Phase Flow

Recommended seam-bowling phase flow:

### Phase 1 — Run-Up / Approach
Purpose:
- capture rhythm, acceleration, line, posture, and tempo

### Phase 2 — Gather / Load
Purpose:
- capture compactness, alignment, coil, and pre-delivery organization

### Phase 3 — Bound / Pre-Back-Foot-Contact
Purpose:
- capture transition style, aerial shape, and directional intent

### Phase 4 — Back Foot Contact
Purpose:
- capture lower-body alignment, trunk orientation, early separation, and setup quality

### Phase 5 — Front Foot Contact / Delivery Block
Purpose:
- capture front-leg type, hip-shoulder separation, front-arm behavior, and block mechanics

### Phase 6 — Release
Purpose:
- capture release slot, release height, arm path family, head/trunk/release organization

### Phase 7 — Follow-Through / Recovery
Purpose:
- capture deceleration style, direction, carry, and finish pattern

## 100-Parameter Design Logic

The full taxonomy can be around 100 parameters.
That is feasible as a design target.

However, they should not all carry equal weight.
Create three groups:

### Group A — Primary retrieval parameters
Used directly and strongly in matching.

### Group B — Secondary retrieval parameters
Used when available, but with lower weights.

### Group C — Metadata/context parameters
Used for filtering, display, and reporting, but not to dominate archetype matching.

## Suggested Parameter Families

Below is a practical 100-parameter style taxonomy outline.
This is a taxonomy definition, not yet an implementation requirement.

### A. Identity and Context (10)
1. bowling_arm
2. bowling_family
3. bowling_style_label
4. height_band
5. body_type_band
6. stock_speed_band
7. peak_speed_band
8. era_band
9. dominant_format_band
10. career_tier_band

### B. Run-Up / Approach (15)
11. run_up_length_band
12. run_up_rhythm_family
13. acceleration_profile
14. approach_line_straightness
15. lateral_approach_angle_band
16. pre_gather_torso_posture
17. head_stability_approach
18. arm_carry_family
19. cadence_density_band
20. final_steps_intensity_band
21. final_step_length_pattern
22. tempo_consistency
23. approach_symmetry
24. center_of_mass_rise_fall_pattern
25. visual_aggression_band

### C. Gather / Load (15)
26. gather_compactness
27. gather_height_band
28. gather_alignment_family
29. shoulder_coil_band
30. pelvis_orientation_pre_bound
31. front_arm_preload_family
32. bowling_arm_preload_family
33. trunk_rotation_preload
34. wrist_set_visibility
35. load_pause_presence
36. load_pause_duration_band
37. center_of_mass_drop_band
38. head_alignment_pre_bound
39. gather_width_family
40. non_bowling_side_balance_family

### D. Bound / Pre-BFC (12)
41. bound_type
42. bound_height_band
43. bound_length_band
44. bound_direction_family
45. airborne_time_band
46. knee_lift_pattern
47. torso_shape_in_bound
48. front_arm_shape_in_bound
49. bowling_arm_path_in_bound
50. hip_rotation_into_bound
51. head_path_during_bound
52. delivery_stride_entry_family

### E. Back Foot Contact (12)
53. back_foot_alignment_family
54. back_foot_landing_angle_band
55. pelvis_alignment_at_bfc
56. shoulder_alignment_at_bfc
57. trunk_tilt_at_bfc
58. trunk_rotation_at_bfc
59. head_position_at_bfc
60. rear_leg_flexion_band
61. front_knee_height_band
62. front_arm_position_at_bfc
63. bowling_elbow_height_at_bfc
64. early_separation_band

### F. Front Foot Contact / Delivery Block (16)
65. front_foot_alignment_family
66. stride_length_normalized_band
67. front_knee_family
68. front_knee_initial_flexion_band
69. front_knee_extension_pattern
70. front_leg_technique_family
71. trunk_flexion_band_at_ffc
72. trunk_side_bend_band_at_ffc
73. head_position_relative_to_front_foot
74. hips_shoulders_separation_band
75. shoulder_counter_rotation_band
76. front_arm_pull_family
77. bowling_arm_verticality_at_ffc
78. chest_orientation_at_ffc
79. block_strength_family
80. balance_over_front_leg_family

### G. Release (14)
81. release_slot_family
82. release_height_normalized_band
83. release_lateral_offset_band
84. arm_path_family
85. elbow_extension_pattern
86. wrist_position_family
87. seam_presentation_proxy_family
88. head_position_at_release
89. shoulder_alignment_at_release
90. chest_orientation_at_release
91. release_timing_after_ffc_band
92. stride_to_release_tempo
93. non_bowling_arm_terminal_family
94. release_corridor_family

### H. Follow-Through / Recovery (10)
95. follow_through_direction_family
96. fallaway_family
97. momentum_carry_family
98. recovery_balance_family
99. bowling_arm_finish_family
100. trunk_finish_family
101. rear_leg_recovery_family
102. deceleration_style_family
103. head_stability_post_release
104. finish_compactness_band

### I. Higher-Order Archetype Parameters (optional overlay family)
These can either sit on top of the above or replace some identity/context fields in the 100-count target.
Examples:
- overall_action_family
- sling_score_band
- smoothness_score_band
- violence_score_band
- textbookness_score_band
- uniqueness_score_band
- whip_vs_hit_family
- repeatability_score_band

## Recommended Pilot Retrieval Subset

Do not use all 100 parameters in the pilot matching engine.

Recommended pilot retrieval subset:
- 20 to 30 strongest observable parameters
- primarily Groups B to H
- only a few contextual priors such as bowling arm and height band

This is enough to prove archetype matching without creating unnecessary noise.

## Data Chunk Design

Each pilot bowler should be stored in several chunks.

### 1. Identity chunk
Used for:
- label
- filtering
- high-level display

### 2. Signature profile chunk
Used for:
- retrieval
- weighted similarity
- explanation

### 3. Career metadata chunk
Used for:
- context
- coach report enrichment
- profile display

### 4. Reference clip chunk
Used for:
- annotation provenance
- future visual grounding

### 5. Provenance chunk
Used for:
- field-level source traceability
- confidence
- unresolved values

## Matching Design

### Step 1 — User parameter extraction
From the user clip, extract as many reliable parameters as possible.

Important:
- not all fields will be observable in every clip
- the system should not force low-confidence values

### Step 2 — Hard filtering
Filter by:
- bowling_family = seam
- bowling_arm
- optionally a coarse action-family gate if confidence is high

### Step 3 — Weighted hybrid scoring
Score the user against pilot bowlers using:
- categorical exact or family-level matches
- ordinal distance matches
- normalized quantitative distance matches
- parameter confidence weights
- source reliability weights
- missingness handling

### Step 4 — Return nearest archetypes
Return:
- top 3 matches
- similarity percentages
- confidence percentage
- strongest matching parameters
- strongest differentiators
- archetype label

### Step 5 — Enrich output with metadata
After matching, attach:
- height
- stock speed band
- highest speed
- wickets
- rankings
- reference clips

These should explain the match, not dominate it.

## Source Strategy

### Tier A — Primary sources
Use first whenever possible:
- ICC player profiles
- ESPNcricinfo player profiles and Statsguru
- official IPL / board / franchise profile pages

### Tier B — Strong secondary sources
Use when Tier A is incomplete:
- Cricbuzz profiles
- major reputable cricket publishers with cited stat context

### Tier C — Fallback only
Use sparingly and mark low confidence:
- Wikipedia / Wikidata for difficult biography fields such as height
- isolated media references for highest recorded speed where primary sources are absent

## Research-Derived Design Notes

Based on the literature, the pilot should explicitly account for:
- action types such as side-on, front-on, semi-open, mixed
- shoulder counter-rotation as a meaningful classification/injury-related variable
- hip-shoulder separation as a useful but imperfect representative metric
- front leg technique families such as flexor, flexor-extender, extender, constant brace
- front foot contact as a critical performance phase
- proximal-to-distal sequencing as a core organizing concept

These are not just coaching ideas.
They are grounded in published biomechanics work.

## 1000-Cluster Vision

Long-term target:
- around 1000 archetype clusters

Interpretation:
- some clusters will represent broader families with multiple bowlers
- some clusters may be highly specific and effectively unique

That is acceptable.
The system should not force uniform cluster size.

The purpose of clustering is:
- action-family organization
- retrieval acceleration
- archetype discovery
- content and coaching explainability

## Final How Statement

Build the Bowling Signature DNA feature as a phased, parameterized, hybrid-retrieval system in which:
- bowlers are represented through structured action signatures
- user clips are partially parameterized
- nearest archetypes are retrieved through weighted matching
- percentages are returned with explanation and confidence
- metadata enriches the result without overpowering the action signature

## Research References

Primary/technical references used in this design direction:

- Bartlett RM, Stockill NP, Elliott BC, Burnett AF. The biomechanics of fast bowling in men's cricket. J Sports Sci. 1996. https://pubmed.ncbi.nlm.nih.gov/8941911/
- Ranson C et al. The relationship between bowling action classification and three-dimensional lower trunk motion in fast bowlers in cricket. J Sports Sci. 2008. https://pubmed.ncbi.nlm.nih.gov/17926175/
- Senington B et al. Are shoulder counter rotation and hip shoulder separation angle representative metrics of three-dimensional spinal kinematics in cricket fast bowling? J Sports Sci. 2018. https://pubmed.ncbi.nlm.nih.gov/29235939/
- Schaefer A et al. A biomechanical comparison of conventional classifications of bowling action-types in junior fast bowlers. J Sports Sci. 2020. https://pubmed.ncbi.nlm.nih.gov/32281483/
- Felton PJ et al. Optimising the front foot contact phase of the cricket fast bowling action. J Sports Sci. 2020. https://pubmed.ncbi.nlm.nih.gov/32475221/
- Felton PJ et al. Optimal initial position and technique for the front foot contact phase of cricket fast bowling. J Biomech. 2023. https://pubmed.ncbi.nlm.nih.gov/37579606/
- Ferdinands RED et al. The Joint Mechanical Function and Control of the Front Leg During Cricket Fast Bowling: A 3D Motion Analysis Study. Sensors. 2026. https://www.mdpi.com/1424-8220/26/3/902
- Thiagarajan G et al. Analysis of segmental kinetic energy in cricket bowling. Procedia Engineering. 2011. https://www.sciencedirect.com/science/article/pii/S1877705811009945
