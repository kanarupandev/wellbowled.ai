# iOS Sync Incident Guardrails

Date: 2026-03-16  
Scope: `wellbowled.ai` source -> Xcode mirror (`/Users/kanarupan/workspace/xcodeProj/wellBowled`)

## What Broke

1. **Unsafe root-level sync command removed Xcode/CocoaPods scaffolding**
   - A root-targeted `rsync --delete` against `xcodeProj/wellBowled/` deleted project/tooling files not present in source-only `wellbowled.ai/ios/wellBowled/`.
   - Missing artifacts included:
     - `Podfile`
     - `Pods/Target Support Files/...`
     - `wellBowled.xcworkspace`
     - `.git` in the mirror folder

2. **Build then failed with CocoaPods/Xcode config errors**
   - `Unable to open base configuration reference file ... Pods-wellBowled.debug.xcconfig`
   - `Framework 'MediaPipeTasksCommon' not found`

3. **After Pods restoration, project-level plist duplication surfaced**
   - `Multiple commands produce ... wellBowled.app/Info.plist`
   - Cause: `wellBowled/Info.plist` treated as both resource copy and processed Info.plist.

4. **Device deployment instability occurred independently**
   - Repeated `CoreDeviceService` initialization timeouts caused install/launch flakiness.
   - This was an environment/tooling issue, not source-code logic.

## Root Cause

- The source iOS folder (`wellbowled.ai/ios/wellBowled`) is **not a full Xcode project root**.
- Syncing it into the mirror root with `--delete` is destructive for Xcode/CocoaPods metadata.

## Non-Negotiable Rules

1. **Never run `rsync --delete` from source iOS folder into the mirror root**:
   - Bad target: `/Users/kanarupan/workspace/xcodeProj/wellBowled/`

2. **Only sync app source files into app subfolder**:
   - Safe target: `/Users/kanarupan/workspace/xcodeProj/wellBowled/wellBowled/`

3. **Only sync tests into test subfolder**:
   - Safe target: `/Users/kanarupan/workspace/xcodeProj/wellBowled/wellBowledTests/`

4. **Preserve these project-level assets in mirror root at all times**:
   - `wellBowled.xcodeproj/`
   - `wellBowled.xcworkspace/`
   - `Podfile`
   - `Podfile.lock`
   - `Pods/`
   - `.git`

## Safe Sync Commands (Approved)

```bash
# App sources only
rsync -a --delete --exclude '.claude/' --exclude 'Tests/' \
  /Users/kanarupan/workspace/wellbowled.ai/ios/wellBowled/ \
  /Users/kanarupan/workspace/xcodeProj/wellBowled/wellBowled/

# Tests only
rsync -a --delete \
  /Users/kanarupan/workspace/wellbowled.ai/ios/wellBowled/Tests/ \
  /Users/kanarupan/workspace/xcodeProj/wellBowled/wellBowledTests/
```

## Recovery Playbook (If Mirror Breaks Again)

1. Recreate Podfile in mirror root (if missing).
2. Run `pod install` in mirror root to regenerate:
   - `Pods/`
   - `Target Support Files`
   - `wellBowled.xcworkspace`
3. Build using workspace, not project:

```bash
xcodebuild -workspace wellBowled.xcworkspace -scheme wellBowled \
  -destination 'generic/platform=iOS' -configuration Debug clean build
```

## Verification Checklist

Before build:
- [ ] `wellBowled.xcworkspace` exists in mirror root
- [ ] `Pods/Target Support Files/Pods-wellBowled/Pods-wellBowled.debug.xcconfig` exists
- [ ] `Podfile` and `Podfile.lock` exist
- [ ] source hashes match for app/tests sync targets

After build:
- [ ] No `MediaPipeTasksCommon` framework-linker error
- [ ] No missing xcconfig reference errors

## Notes

- This incident was a process/sync-scope failure, not a model/business-logic regression.
- Keep `wellbowled.ai` as source-of-truth for app code, and treat `xcodeProj/wellBowled` as a fragile deployment mirror with strict sync boundaries.
