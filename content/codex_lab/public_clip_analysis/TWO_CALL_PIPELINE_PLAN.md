# Two-Call Bowling Analysis Plan

## Scope

Input clip:

- `/Users/kanarupan/workspace/wellbowled.ai/resources/samples/3_sec_1_delivery_nets.mp4`

Goal:

- minimize manual shaping per video now
- cap Gemini usage at **2 calls per video**
- use Gemini to replace the highest-friction manual steps first
- keep the final rendering pipeline deterministic and auditable

## Design Principle

Gemini should decide **what to shape**, not just write nicer text.

That means:

- `Flash` handles fast structural decisions
- local CV + MediaPipe handles deterministic overlays
- `Pro` is optional and only used if a second pass materially improves the result

## Call Budget

### Call 1: Gemini Flash

Purpose:

- inspect a timestamped storyboard/contact-sheet derived from the clip
- return structured shaping hints in JSON

Expected output:

- estimated delivery phase times:
  - `load`
  - `release`
  - `freeze`
  - `finish`
- rough bowler ROI suggestion
- annotation priorities:
  - wrist trail
  - torso drive
  - front-side finish
- short technical insight

Why Flash:

- cheaper
- faster
- good enough for coarse structure

### Call 2: Gemini Pro

Purpose:

- optional refinement only after the Flash plan and local pose pass succeed
- generate tighter coaching language and better label hierarchy

Expected output:

- title
- primary insight
- release note
- finish note
- one takeaway line

Why Pro:

- only worth spending after the video structure is already correct
- avoids burning expensive calls on clips that still have pose or timing issues

## Local Deterministic Stages

1. Trim clip segment.
2. Extract timestamped frames for a storyboard.
3. Ask Gemini Flash for shaping hints.
4. Run MediaPipe pose locally.
5. Combine:
   - Flash timing hints
   - optional ROI hint
   - local pose detections
6. Render:
   - slow-motion sequence
   - color-coded overlays
   - freeze-frame analysis
   - end card
7. Only if needed, ask Gemini Pro to refine the copy.

## Human-in-the-Loop Fallback

If Flash fails or returns weak hints:

- keep local defaults
- allow the human to adjust:
  - ROI
  - phase timestamps
  - cue text

Target human time:

- 10-20 minutes per clip

## What this replaces

The first manual steps Gemini should replace are:

1. rough phase timing selection
2. rough crop/subject framing guidance
3. first-pass annotation selection

Not the first target:

- perfect prose
- final export polish

## Success Criteria

- no more than 2 Gemini calls per video
- one reproducible config per clip
- renderer still works without Gemini
- shaped export is visibly stronger than the raw clip
- manual work is reduced to review and small corrections
