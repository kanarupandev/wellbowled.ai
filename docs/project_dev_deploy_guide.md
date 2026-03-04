# wellBowled Project Dev + Deployment Guide

This document is project-specific.
Generic rules stay in [dev_process.md](/Users/kanarupan/workspace/wellbowled.ai/docs/dev_process.md).

## 1) Purpose

Define the concrete workflow for this project:
- implement iOS app features in this repo
- ship a demo-ready iPhone build for hackathon judging
- keep claims separated as `VALIDATED` vs `UNVERIFIED`

## 1A) Autonomous Execution Contract

1. Never ask the user how to execute the dev process.
2. Process source of truth is these docs:
- [dev_process.md](/Users/kanarupan/workspace/wellbowled.ai/docs/dev_process.md)
- [project_dev_deploy_guide.md](/Users/kanarupan/workspace/wellbowled.ai/docs/project_dev_deploy_guide.md)
- [codex_guide.md](/Users/kanarupan/workspace/wellbowled.ai/docs/codex_guide.md)
3. Resolve process gaps by checking repo state and tooling first (`git log`, `rg`, `xcodebuild`, `xcrun devicectl`).
4. Escalate only hard blockers:
- missing product decision
- missing permissions/credentials/device access
- unresolved conflict between canonical docs after attempted reconciliation
5. Any escalation must include: commands attempted, concrete errors, and next best options.

## 2) Source Of Truth

1. Product/use-case:
[session_onboarding.md](/Users/kanarupan/workspace/wellbowled.ai/docs/session_onboarding.md)
2. Architecture and status:
[architecture_decision.md](/Users/kanarupan/workspace/wellbowled.ai/docs/architecture_decision.md)
3. Handover and runbook:
[codex_guide.md](/Users/kanarupan/workspace/wellbowled.ai/docs/codex_guide.md)
4. Code map:
[SITEMAP.md](/Users/kanarupan/workspace/wellbowled.ai/docs/SITEMAP.md)

## 3) Repos And Ownership

1. Only repo for active development:
`/Users/kanarupan/workspace/wellbowled.ai`
2. iOS source-of-truth code:
`/Users/kanarupan/workspace/wellbowled.ai/ios/wellBowled/`
3. Xcode build copy (disposable, never edit directly):
`/Users/kanarupan/workspace/xcodeProj/wellBowled/wellBowled/`
4. Obsolete repo (do not use):
`/Users/kanarupan/workspace/dont_use_obsolete_wellBowled/`

## 4) Project-Specific Development Flow

Mapped to [dev_process.md](/Users/kanarupan/workspace/wellbowled.ai/docs/dev_process.md):

1. Understand
- lock the slice (for now: Live Challenge flow first)
- restate unknowns explicitly
- do not ask process-level questions; derive from the runbook and execute

2. Research
- read latest commits touching changed files
- confirm current behavior in source, not memory

3. Experiment
- run real commands / device checks for integration claims
- record exact command + result

4. Verify
- label each behavior `VALIDATED` or `UNVERIFIED`
- do not treat local interaction as accuracy proof

5. Plan
- smallest vertical slice that can be demoed:
`start mode -> announce challenge -> detect ball -> evaluate -> show score`

6. Test-first + implement
- tests in `ios/wellBowled/Tests/`
- app code in `ios/wellBowled/`
- one behavior change per commit

7. Verify again
- simulator compile/tests
- physical-device build/install
- short manual run through the demo path

8. Document
- sync affected docs in same workstream
- remove contradictions immediately

## 5) Coding Constraints (This Project)

1. No production backend/infrastructure scope for hackathon build.
2. Speed output must remain exploratory pace bands unless radar-calibrated.
3. Live API is conversational; do not claim proactive monitoring behavior.
4. Challenge interaction can be `VALIDATED` while challenge accuracy remains `UNVERIFIED` until measured end-to-end.

## 6) Commit Rules (Multi-Agent)

1. Codex commits use `codex:` prefix.
2. Keep commits scoped and incremental.
3. Do not mix unrelated docs cleanup with behavior changes.
4. Re-read files recently touched by another agent before editing.

## 7) Hackathon Deployment Steps

Deployment here means demo-ready iPhone app delivery.
In this project, deploy specifically means: build, reinstall/update app on target iPhone, then validate launch.

1. Pre-deploy checklist
- challenge flow runs end-to-end on device
- test suite green for touched areas
- docs synced and contradiction-free

2. Build prep
- sync `wellbowled.ai/ios/wellBowled` into `xcodeProj/wellBowled/wellBowled`
- keep tests in `wellBowledTests` target

3. Build + reinstall
- build from `xcodeProj/wellBowled` for target device
- reinstall via `xcrun devicectl device install app --device <UDID> <app_path>`

4. Device validation run
- run one full session:
`record -> detect/count -> live conversation -> end -> post-session challenge score`
- capture evidence (timestamps, screenshots, short recording)

5. Demo package
- freeze branch + commit hash
- prepare 4-minute runbook:
3-minute live segment + 1-minute results segment

6. Fallback
- if venue network degrades, switch to fallback path in
[architecture_decision.md](/Users/kanarupan/workspace/wellbowled.ai/docs/architecture_decision.md)

## 7A) Regression Guardrail (Camera Preview API Incident)

Incident class (must not repeat):
- shared component API changed (`CameraPreview(session:)` -> `CameraPreview(previewLayer:)`) but one call site was missed, causing compile/test/install delay.

Mandatory prevention checklist before install:
1. Call-site sweep for changed symbols:
- `rg -n "CameraPreview\\(" /Users/kanarupan/workspace/wellbowled.ai/ios/wellBowled`
2. Verify no stale initializer remains:
- no `CameraPreview(session:` usage allowed.
3. Full simulator tests pass:
- `xcodebuild ... test` must return `** TEST SUCCEEDED **`.
4. Device build + reinstall + launch:
- only after step 3 is green.
5. If step 1-4 fails:
- stop install attempts, fix source-of-truth, resync, rerun.

## 8) Quick Command Reference

```bash
git -C /Users/kanarupan/workspace/wellbowled.ai log --oneline -15

xcrun devicectl list devices

cd /Users/kanarupan/workspace/xcodeProj/wellBowled && \
xcodebuild -workspace wellBowled.xcworkspace \
  -scheme wellBowled \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" test

cd /Users/kanarupan/workspace/xcodeProj/wellBowled && \
xcodebuild -workspace wellBowled.xcworkspace \
  -scheme wellBowled \
  -destination "platform=iOS,id=E40F593B-ABB6-514A-873F-48CD7C4F98F3" \
  -configuration Debug clean build

APP_PATH=$(find /Users/kanarupan/Library/Developer/Xcode/DerivedData/wellBowled-* \
  -path '*/Build/Products/Debug-iphoneos/wellBowled.app' -type d | grep -v 'Index.noindex' | sort | tail -n 1) && \
xcrun devicectl device install app --device E40F593B-ABB6-514A-873F-48CD7C4F98F3 "$APP_PATH"

xcrun devicectl device process launch --device E40F593B-ABB6-514A-873F-48CD7C4F98F3 kanarupan.wellBowled
```

If launch is denied with locked-device error, unlock iPhone and rerun the launch command.
