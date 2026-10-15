#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
APP_PATH="$PROJECT_ROOT/dist/AudioFormatKeeper.app"
CONTENTS_PATH="$APP_PATH/Contents"

cd "$PROJECT_ROOT"
"$PROJECT_ROOT/Scripts/generate-icon.sh" >/dev/null
swift build -c release
BIN_PATH="$(swift build -c release --show-bin-path)"

rm -rf "$APP_PATH"
mkdir -p "$CONTENTS_PATH/MacOS" "$CONTENTS_PATH/Resources"
cp "$BIN_PATH/AudioFormatKeeper" "$CONTENTS_PATH/MacOS/AudioFormatKeeper"
cp "$PROJECT_ROOT/Support/Info.plist" "$CONTENTS_PATH/Info.plist"
cp "$PROJECT_ROOT/Assets/AppIcon.icns" "$CONTENTS_PATH/Resources/AppIcon.icns"
cp -R "$PROJECT_ROOT/AppSources/Resources/en.lproj" "$CONTENTS_PATH/Resources/"
cp -R "$PROJECT_ROOT/AppSources/Resources/ja.lproj" "$CONTENTS_PATH/Resources/"

plutil -lint "$CONTENTS_PATH/Info.plist"
codesign --force --sign - --timestamp=none "$APP_PATH"

echo "$APP_PATH"
