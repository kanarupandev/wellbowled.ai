# X-Factor v1.0.0 — Working Directory

## Structure
```
xfactor_v100/
├── site_map.md                 # This file
├── quality_gate.md             # → ../xfactor_v100_quality_gate.md (93 checks)
├── competitive_research.md     # Analysis of existing viral bowling analysis videos
├── design_spec.md              # Visual design spec for v1.0.0 output
├── iteration_log.md            # Every iteration: what changed, what passed, what failed
├── iterations/                 # Frame extracts from each pipeline run
│   ├── v001/                   # Current baseline
│   ├── v002/                   # After first fix round
│   └── ...
├── frames/                     # Working frames for review
└── output/                     # Final v1.0.0 output when all 93 checks pass
```

## Process
1. Research existing viral bowling content → identify what to beat
2. Design spec → define exact visual targets
3. Iterative improvement → run pipeline, extract frames, self-review against 93 checks, fix, repeat
4. Each iteration gets a commit with checklist delta
5. v1.0.0 declared ONLY when 93/93 pass
