# Expression of Interest — Research Papers

Papers ranked by relevance to the wellBowled.ai X-factor pipeline and future technique analysis videos.

## Successfully Downloaded

| # | Title | Authors | Year | Journal | File |
|---|-------|---------|------|---------|------|
| 1 | Fast Bowling in Cricket: A Biomechanical Review of Performance Technique and Injury Mechanisms | (systematic review) | 2026 | IJISRT | `reviews/ijisrt_2026_biomechanics_review.pdf` |
| 2 | Cricket Biomechanics Analysis of Skilled and Amateur Fast Bowling Techniques | Thiagarajan KA, Parikh T, Sayed A, Gnanavel MB, Arumugam S | 2015 | JPMER 49(4):173-181 | `biomechanics/thiagarajan_2015_skilled_vs_amateur.pdf` |

## Pending Downloads (need manual access)

### P1 — Front Leg 3D Motion Analysis (2026, HIGHEST PRIORITY)
- **Title:** The Joint Mechanical Function and Control of the Front Leg During Cricket Fast Bowling: A 3D Motion Analysis Study
- **Year:** 2026 (published Jan 29, 2026)
- **Journal:** Sensors (MDPI), 26(3), 902
- **URL:** https://www.mdpi.com/1424-8220/26/3/902
- **PMC:** https://pmc.ncbi.nlm.nih.gov/articles/PMC12899921/
- **DOI:** 10.3390/s26030902
- **Abstract:** Examined front leg mechanics in 18 junior fast bowlers using 14-camera 3D motion capture (200Hz) and force platforms. Found front leg motion dominated by eccentric control, not concentric quad extension. Knee angle at release reflects whole-body coordination. Run-up speed is strongest predictor of ball speed; knee angle at FFC has no significant influence.
- **Why:** Validates our front-knee-brace metric. Eccentric vs concentric distinction is key insight for coaching text.

### P2 — OpenCap Validation for Cricket Bowling (2025)
- **Title:** Exploring the accuracy of OpenCap for three-dimensional analysis of cricket bowling
- **Authors:** Abraham A, Feros SA, Fox AS
- **Year:** 2025
- **Journal:** Proc IMechE Part P: J Sports Eng and Technology
- **DOI:** 10.1177/17479541251348081
- **URL:** https://journals.sagepub.com/doi/10.1177/17479541251348081
- **Abstract:** Compared markerless pose estimation (OpenCap) against marker-based motion capture for bowling. Shoulder kinematics were least accurate. RMSE data provided for all joints.
- **Why:** Directly tells us what MediaPipe can and can't measure reliably. Sets accuracy expectations.

### P3 — CricTAL: Bowling Phase Localisation (ICCV 2025)
- **Title:** CricTAL: Introducing Temporal Activity Localisation using pose estimation to identify cricket bowling phases
- **Authors:** Moodley et al.
- **Year:** 2025
- **Venue:** ICCV 2025 Workshop (SAUAFG)
- **URL:** https://openaccess.thecvf.com/content/ICCV2025W/SAUAFG/papers/Moodley_CricTAL_Introducing_Temporal_Activity_Localisation_using_pose_estimation_to_identify_ICCVW_2025_paper.pdf
- **Abstract:** Temporal activity localisation for cricket bowling phases using pose estimation. Phase decomposition for Action Quality Assessment.
- **Why:** Exactly what our pipeline does — automates phase detection from pose. Could replace our heuristic phase detection.

### P4 — Smart Cricket Ball + Action Correction (2026)
- **Title:** Assessment and Measurement of Side-Effects of an Evidence-Based Intervention with an Advanced Smart Cricket Ball
- **Year:** 2026
- **Journal:** Sensors (MDPI), 26(1), 299
- **URL:** https://www.mdpi.com/1424-8220/26/1/299
- **DOI:** 10.3390/s26010299
- **Why:** Shows how sensor data complements video analysis for bowling action correction.

### P5 — Pose Estimation + ML for Cricket Performance (2023)
- **Title:** Enhancing Cricket Performance Analysis with Human Pose Estimation and Machine Learning
- **Year:** 2023
- **Journal:** Sensors (MDPI), 23(15), 6839
- **URL:** https://www.mdpi.com/1424-8220/23/15/6839
- **PMC:** https://pmc.ncbi.nlm.nih.gov/articles/PMC10422414/
- **Abstract:** Identifies 17 key biomechanical parameters from pose estimation. Uses ML clustering to distinguish skill levels. Annotated video feedback.
- **Why:** Their 17-parameter framework could inform which metrics our pipeline should measure beyond X-factor.

### P6 — Front Leg Kinematics with Wearable Sensors + ML (2022)
- **Title:** Analysis of Front Leg Kinematics of Cricket Bowler Using Wearable Sensors and Machine Learning
- **Year:** 2022
- **Journal:** IEEE Sensors Journal
- **DOI:** 10.1109/JSEN.2022.3207851
- **URL:** https://ieeexplore.ieee.org/document/9893539/
- **Why:** ML classification of front leg action types from sensor data. Reference for our front-knee-brace pipeline.

### P7 — ML Pose Estimation Bowling Optimization (2024)
- **Title:** Cricket Fast Bowling Optimization Using Machine Learning Pose Estimation Modeling
- **Year:** 2024
- **Journal:** Research Archive of Rising Scholars (preprint)
- **URL:** https://research-archive.org/index.php/rars/preprint/view/2861/version/3013
- **Why:** ML optimization of bowling technique from pose — similar approach to ours.

## Key Calibration Data from Downloaded Papers

From Thiagarajan et al. (2015) — directly applicable to our X-factor pipeline:

### Action Type Classification (at back foot contact)
| Action Type | Shoulder Segment Angle | Hip-Shoulder Separation | Shoulder Counter-Rotation |
|-------------|----------------------|------------------------|--------------------------|
| Side-on | <210° | <30° | <30° |
| Front-on | >240° | <30° | <30° |
| Semi-open | 210-240° | <30° | <30° |
| Mixed | any | ≥30° | ≥30° |

### Front Knee Classification
| Type | Description |
|------|------------|
| Flexor | Knee flexion ≥10° then <10° extension |
| Flexor-extender | Flexion AND extension both ≥10° |
| Extender | Knee flexion <10° then extension ≥10° |
| Constant brace | Both flexion and extension <10° |

### Key Finding
- Skilled bowlers showed faster ball release speed AND larger vGRF
- SCR, pelvis-shoulder separation, trunk lateral flexion, front knee angle showed NO significant difference between skilled/amateur
- **Implication for our pipeline:** vGRF (ground reaction force) differentiates skill more than the angles we're measuring. Speed estimation may be more valuable than angle overlay for content.
