# Production Notes — v0.0.3

## Clip Quality

### Bumrah (MI Nets, MI TV watermark)

- Indoor nets, decent side-on angle.
- MI TV watermark top-right — must be cropped or accepted.
- Background people visible — SAM 2 isolation planned but not yet done.
- Best frames: f060 (front foot contact), f072 (release).

### Steyn (SA Nets, outdoor Newlands)

- Wider angle, bowler is smaller in frame.
- Lower visual resolution than the Bumrah clip.
- Resolution and framing mismatch is the biggest production risk for the side-by-side.
- Scaling Steyn up to match Bumrah's size will amplify the quality gap.
- Consider sourcing a better Steyn clip before full render — highest-leverage improvement available.

## Phase Matching — Must Verify Before Render

Bumrah frame numbers (f000–f072) and Steyn frame numbers (f000–f075) do NOT correspond to the same delivery phase.

From visual review:
- Bumrah f060: appears around front foot contact.
- Steyn f060: appears at or just past release — slightly later.
- Steyn f045 or f030 may be a better front-foot-contact match for Bumrah f060.

Action required: manually compare delivery phases across both frame sets before selecting the hero side-by-side pair.

## Frame Selection for Script Beats

| Beat | Bumrah frame | Steyn frame | Status |
|------|-------------|-------------|--------|
| Beat 1 (hook) | f072 (release) | — | Confirmed |
| Beat 2 (unusual) | f036, f060, f072 | — | Confirmed |
| Beat 3 (Steyn solo) | — | TBC gather + TBC release | Needs phase verification |
| Beat 3 (side-by-side) | TBC | TBC | Needs phase verification |

## Open Decisions

1. **Music/sound:** Royalty-free minimal beat recommended. Not yet sourced.
2. **SAM 2 isolation:** Not yet done. Script works without it. Dark vignette partially mitigates background noise.
3. **Skeleton overlay:** Depends on `extract_angles.py` running successfully. Status unknown.
4. **Steyn clip quality:** If the current clip cannot hold up in side-by-side at matched scale, the premium feel is at risk. This is the single biggest production blocker.
