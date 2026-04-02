# Production Notes — v0.0.2

## Clip Quality

### Bumrah (MI Nets, MI TV watermark)

- Indoor nets, decent side-on angle.
- MI TV watermark top-right — must be cropped or accepted.
- Background people visible — SAM 2 isolation planned but not yet done.
- f060 and f072 are the strongest frames.

### Steyn (SA Nets, outdoor Newlands)

- Wider angle, bowler is smaller in frame.
- Lower visual resolution than the Bumrah clip.
- Resolution and framing mismatch is the biggest production risk for the side-by-side.
- Scaling Steyn up to match Bumrah's size will amplify the quality gap.

## Phase Matching — Must Verify

Bumrah frame numbers (f000–f072) and Steyn frame numbers (f000–f075) do NOT correspond to the same delivery phase.

From visual review of extracted frames:
- Bumrah f060 appears to be around front foot contact.
- Steyn f060 appears to be at or just past release — slightly later in the sequence.
- Steyn f045 or f030 may be a better front-foot-contact match for Bumrah f060.

**Action required:** manually compare delivery phases across both sets of frames before selecting the hero side-by-side pair.

## Open Decisions

1. **Music/sound:** Not addressed. Royalty-free minimal beat recommended.
2. **SAM 2 isolation:** Not yet done. Script works without it, but background people in the Bumrah clip are distracting. Dark vignette partially mitigates.
3. **Skeleton overlay:** Depends on `extract_angles.py` running successfully on both clips. Status unknown.
4. **Steyn clip replacement:** Given the quality gap, consider sourcing a better Steyn clip before investing in full render. This is the highest-leverage improvement available.
