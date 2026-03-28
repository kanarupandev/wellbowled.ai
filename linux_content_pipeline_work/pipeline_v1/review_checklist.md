# Pipeline Dev Spec — Review Checklist

## A. ARCHITECTURE

- [ ] A1. Single canonical stage order — no contradictions between docs
- [ ] A2. Every stage has exactly one input contract and one output contract
- [ ] A3. No stage depends on an output not defined by a prior stage
- [ ] A4. Stages are independently re-runnable (can re-run Stage 5 without re-running 0-4)
- [ ] A5. Shared manifest schema is defined once, used by all stages
- [ ] A6. Technique selection resolved before expensive compute (isolation, pose)
- [ ] A7. RIFE is render-only — never feeds into analysis/pose extraction
- [ ] A8. Single point of failure (Stage 1) has documented fallback/correction path

## B. CONTRACTS & SCHEMAS

- [ ] B1. Canonical timebase defined (source_seconds) — no ambiguity
- [ ] B2. Coordinate system defined (normalized 0-1) — no ambiguity
- [ ] B3. Frame index derivation formula specified
- [ ] B4. Source clip hash propagated through all stages (integrity chain)
- [ ] B5. Every JSON output has a complete schema (not just field names, but types and constraints)
- [ ] B6. Mask format specified: dimensions, bit depth, naming convention
- [ ] B7. Poses format: landmark count, index mapping, visibility threshold
- [ ] B8. Analysis format: exact segment definitions with joint IDs per bowling arm
- [ ] B9. Stage version field in manifest (allows detecting stale cached outputs)
- [ ] B10. Confidence fields on outputs that involve estimation (Gemini, MediaPipe visibility)

## C. VALIDATION GATES

- [ ] C1. Every stage has explicit pass/fail assertions (not just prose)
- [ ] C2. Stage 0: file integrity, duration, fps, resolution bounds checked
- [ ] C3. Stage 1: timestamp ordering, quality threshold, confidence threshold
- [ ] C4. Stage 1: fallback for API failure (manual input)
- [ ] C5. Stage 2: mask coverage ≥ 90%
- [ ] C6. Stage 2: centroid continuity (catches person-jumping)
- [ ] C7. Stage 2: area continuity (catches sudden mask changes)
- [ ] C8. Stage 2: consecutive empty frames limit
- [ ] C9. Stage 2: fallback if gate fails (retry with different prompt point)
- [ ] C10. Stage 4: detection rate ≥ 80%
- [ ] C11. Stage 4: determinism verified (two runs identical)
- [ ] C12. Stage 4: torso length continuity (catches person-switching)
- [ ] C13. Stage 4: no landmark teleporting (max frame-to-frame jump)
- [ ] C14. Stage 5: all ratios within plausible range (0.5-5.0)
- [ ] C15. Stage 5: all peaks within analysis window
- [ ] C16. Stage 5: all velocities > 0 in delivery window
- [ ] C17. Stage 8: ffprobe verification (codec, resolution, fps, bitrate, duration)

## D. CROSS-STAGE SANITY

- [ ] D1. Bowling arm from Stage 1 matches dominant arm activity in Stage 5
- [ ] D2. Stage 2 mask centroids align with Stage 1 bowler_center_points
- [ ] D3. Stage 5 peak wrist time is within ±0.5s of Stage 1 release timestamp
- [ ] D4. Stage 4 torso_length mean is consistent with expected bowler height (if known)
- [ ] D5. Stage 6 (if used) confirms isolation and analysis validity

## E. FAILURE RECOVERY

- [ ] E1. Stage 1 failure → manual input path defined
- [ ] E2. Stage 2 failure → retry with different prompt point
- [ ] E3. Stage 2 unavailable → skip isolation for single-person clips
- [ ] E4. Stage 3 artifacts → skip enhancement, use original
- [ ] E5. Stage 4 low detection → clip declared unusable (not silent corruption)
- [ ] E6. Stage 5 implausible ratios → flagged in output, not hard fail
- [ ] E7. Stage 6 rejects analysis → re-examine Stage 2, possible re-run
- [ ] E8. No stage silently produces garbage — every failure is either caught or flagged

## F. IMPLEMENTATION READINESS

- [ ] F1. All tools specified with exact versions/model names
- [ ] F2. All dependencies listed (pip packages, system tools)
- [ ] F3. Environment variables defined
- [ ] F4. CLI interface specified with flags
- [ ] F5. Directory structure defined with exact file paths/naming
- [ ] F6. Pseudocode or real code provided for non-trivial logic
- [ ] F7. Gemini prompt templates included verbatim
- [ ] F8. SAM 2 initialization code included
- [ ] F9. MediaPipe masked-frame detection approach specified
- [ ] F10. FFmpeg command specified verbatim
- [ ] F11. An implementer can write code from this doc without asking questions

## G. ACCURACY & HONESTY

- [ ] G1. Claims about camera-angle independence are qualified (not overstated)
- [ ] G2. Velocity units clearly defined (torso-lengths/s, not m/s)
- [ ] G3. Transfer ratios defined as measured (not compared to mismatched baselines)
- [ ] G4. Confidence notes populated based on camera angle
- [ ] G5. No fake numbers or made-up baselines
- [ ] G6. Limitations explicitly stated (depth motion lost, 2D projection)

## H. COMPLETENESS

- [ ] H1. All 10 stages defined (0, 1, 1.5, 2, 3, 4, 5, 6, 7, 7.5, 8)
- [ ] H2. Technique-specific rendering approach defined (at least for speed_gradient)
- [ ] H3. Multi-technique support: shared stages (0-5) → branch at Stage 7
- [ ] H4. Caching: which outputs are reusable across technique runs
- [ ] H5. Logging: what gets logged at each stage for debugging
- [ ] H6. Execution order is unambiguous (no circular dependencies)

## SCORING

| Grade | Pass Rate | Action |
|-------|-----------|--------|
| READY | 60/60+ (100%) | Implement |
| CLOSE | 54-59 (90%+) | Fix gaps, then implement |
| NEEDS WORK | <54 (<90%) | Major revision needed |
