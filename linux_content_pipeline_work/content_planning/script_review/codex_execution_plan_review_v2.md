# Codex Review — Execution Plan v2

## Verdict

This is a meaningful improvement over v1.

The plan now correctly separates:

- clip selection
- tool-fit validation
- tooling adaptation
- render
- QC

That was the main structural problem in v1, and it is now fixed.

## Findings

### 1. Step 2.2 does not validate all joints required by the planned overlays

The validation gate checks:

- both shoulder joints
- both hip joints
- front knee joints

But the planned comparison overlays also depend on:

- elbow and wrist for arm path
- spine/trunk landmarks if the release-frame spine line is kept

Relevant plan lines:

- [execution_plan_v2.md](/home/kanarupan/perSONAL/content_work_wellBowled/wellbowled.ai/linux_content_pipeline_work/content_planning/script_review/execution_plan_v2.md#L64)
- [execution_plan_v2.md](/home/kanarupan/perSONAL/content_work_wellBowled/wellbowled.ai/linux_content_pipeline_work/content_planning/script_review/execution_plan_v2.md#L69)
- [execution_plan_v2.md](/home/kanarupan/perSONAL/content_work_wellBowled/wellbowled.ai/linux_content_pipeline_work/content_planning/script_review/execution_plan_v2.md#L70)
- [execution_plan_v2.md](/home/kanarupan/perSONAL/content_work_wellBowled/wellbowled.ai/linux_content_pipeline_work/content_planning/script_review/execution_plan_v2.md#L222)
- [execution_plan_v2.md](/home/kanarupan/perSONAL/content_work_wellBowled/wellbowled.ai/linux_content_pipeline_work/content_planning/script_review/execution_plan_v2.md#L223)

Impact:

The plan could pass Phase 2 while still failing on the actual Beat 2 / Beat 3 overlays.

Required fix:

- expand Step 2.2 to validate all landmarks needed by the final overlay treatment
- explicitly include elbow/wrist confidence checks
- if the spine line remains in scope, define exactly which landmarks are required for it

### 2. The spine line appears in Phase 4, but is not actually specified in the adaptation work

This is not just an implementation gap. It is also a script-alignment issue.

The approved final script explicitly includes trunk position / spine line on the release frame:

- [apr_03_first_video_script_FINAL.md](/home/kanarupan/perSONAL/content_work_wellBowled/wellbowled.ai/linux_content_pipeline_work/content_planning/apr_03_first_video_script_FINAL.md#L44)
- [apr_03_first_video_script_FINAL.md](/home/kanarupan/perSONAL/content_work_wellBowled/wellbowled.ai/linux_content_pipeline_work/content_planning/apr_03_first_video_script_FINAL.md#L46)

Phase 4 correctly carries that into the render plan:

- Bumrah release frame uses hip line + shoulder line + spine line

But the adaptation plan in Step 3.2 only commits to:

- hip line
- shoulder line
- front knee triangle
- arm path

Relevant plan lines:

- [execution_plan_v2.md](/home/kanarupan/perSONAL/content_work_wellBowled/wellbowled.ai/linux_content_pipeline_work/content_planning/script_review/execution_plan_v2.md#L163)
- [execution_plan_v2.md](/home/kanarupan/perSONAL/content_work_wellBowled/wellbowled.ai/linux_content_pipeline_work/content_planning/script_review/execution_plan_v2.md#L169)
- [execution_plan_v2.md](/home/kanarupan/perSONAL/content_work_wellBowled/wellbowled.ai/linux_content_pipeline_work/content_planning/script_review/execution_plan_v2.md#L170)
- [execution_plan_v2.md](/home/kanarupan/perSONAL/content_work_wellBowled/wellbowled.ai/linux_content_pipeline_work/content_planning/script_review/execution_plan_v2.md#L223)

Impact:

There is still a spec gap between planned implementation and planned render output.

Required fix:

- either add spine-line implementation to Step 3.2
- or remove spine line from Step 4.2 if it is intentionally out of scope

### 3. Phase 4 orders colour grading after overlay rendering, which is risky

Current order:

1. render skeleton overlays
2. apply colour grading
3. compose final video

Relevant lines:

- [execution_plan_v2.md](/home/kanarupan/perSONAL/content_work_wellBowled/wellbowled.ai/linux_content_pipeline_work/content_planning/script_review/execution_plan_v2.md#L218)
- [execution_plan_v2.md](/home/kanarupan/perSONAL/content_work_wellBowled/wellbowled.ai/linux_content_pipeline_work/content_planning/script_review/execution_plan_v2.md#L227)
- [execution_plan_v2.md](/home/kanarupan/perSONAL/content_work_wellBowled/wellbowled.ai/linux_content_pipeline_work/content_planning/script_review/execution_plan_v2.md#L233)

Impact:

If grading happens after overlays are burned in, it can also alter the overlay colours and contrast, which weakens the “muted but intentional broadcast” look the script is aiming for.

Required fix:

- grade source frames first
- then render overlays onto graded frames
- then compose

Recommended order:

1. pose extraction
2. colour grade source frames
3. render overlays on graded frames
4. compose

### 4. The plan still slightly understates the validation needed for the side-by-side overlay treatment

The side-by-side is not just a generic “overlay passes / fails” checkpoint.

The approved script requires the same treatment on both bowlers for:

- hip line
- shoulder line
- front knee triangle
- bowling arm path

Relevant script lines:

- [apr_03_first_video_script_FINAL.md](/home/kanarupan/perSONAL/content_work_wellBowled/wellbowled.ai/linux_content_pipeline_work/content_planning/apr_03_first_video_script_FINAL.md#L69)
- [apr_03_first_video_script_FINAL.md](/home/kanarupan/perSONAL/content_work_wellBowled/wellbowled.ai/linux_content_pipeline_work/content_planning/apr_03_first_video_script_FINAL.md#L75)
- [apr_03_first_video_script_FINAL.md](/home/kanarupan/perSONAL/content_work_wellBowled/wellbowled.ai/linux_content_pipeline_work/content_planning/apr_03_first_video_script_FINAL.md#L76)
- [apr_03_first_video_script_FINAL.md](/home/kanarupan/perSONAL/content_work_wellBowled/wellbowled.ai/linux_content_pipeline_work/content_planning/apr_03_first_video_script_FINAL.md#L77)

Impact:

It is possible for a clip to be “usable” for pose extraction overall but still fail the specific side-by-side visual standard if one bowler loses elbow/wrist or knee clarity at the matched hero phase.

Required fix:

- in the dry run, make the side-by-side card the true validation artifact
- do not treat a single good overlay frame as sufficient
- require one actual matched comparison card before Phase 4 starts

### 5. The plan is strong enough now that the next risk is scope creep, not structure

This is not a defect, but it matters.

The plan is now detailed enough to execute. The next failure mode is adding more renderer/composer ambition during implementation than the approved script actually needs.

Watchouts:

- do not overbuild pulse/glow if a simple emphasis treatment works
- do not turn Beat 4 into a metric card
- do not let the composer become a generic framework before the asset is rendered once

## What Improved From v1

1. The tool-fit checkpoint is now explicit.
2. The extract-angle hardcoding issue is correctly addressed.
3. The composer mismatch is now described honestly as a new composition path.
4. Fallback paths are much better.
5. The dependency chain now reflects reality.

## Final Judgment

Approve with minor revisions.

This is close to execution-ready, but I would make these two edits before treating it as locked:

1. align Step 2.2 and Step 4.2 on the exact landmark set required
2. move colour grading ahead of overlay rendering

After that, the plan is ready to execute.
