#!/bin/bash
# Pull latest codex/dev, sync, build, and install to iPhone
set -e

BRANCH="codex/dev"
REPO="/Users/kanarupan/workspace/wellbowled.ai"
XCODE="/Users/kanarupan/workspace/xcodeProj/wellBowled"
DEVICE="00008120-001230560204A01E"

cd "$REPO"
echo "==> Pulling $BRANCH..."
git checkout "$BRANCH" 2>/dev/null || true
git pull origin "$BRANCH" --rebase

echo "==> Syncing source to Xcode project..."
rm -rf "$XCODE/wellBowled/"*.swift
cp -R "$REPO/ios/wellBowled/" "$XCODE/wellBowled/"
rm -rf "$XCODE/wellBowled/Tests"

echo "==> Building for device..."
cd "$XCODE"
xcodebuild -workspace wellBowled.xcworkspace \
  -scheme wellBowled \
  -destination "platform=iOS,id=$DEVICE" \
  -configuration Debug build 2>&1 | tail -3

echo "==> Installing to device..."
xcrun devicectl device install app \
  --device "$DEVICE" \
  "$HOME/Library/Developer/Xcode/DerivedData/wellBowled-dovdfiwshrploseqggisupqoeikf/Build/Products/Debug-iphoneos/wellBowled.app" 2>&1 || true

echo "==> Launching app..."
xcrun devicectl device process launch \
  --device "$DEVICE" \
  "kanarupan.wellBowled" 2>&1 || true

echo "==> Done!"
