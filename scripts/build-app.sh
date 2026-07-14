#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
APP="$ROOT/dist/Stay Put.app"
CONTENTS="$APP/Contents"

cd "$ROOT"
swift build -c release --product Stayput

rm -rf "$APP" "$ROOT/dist/Stayput.app"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp ".build/release/Stayput" "$CONTENTS/MacOS/Stayput"
cp "Resources/AppIcon.icns" "$CONTENTS/Resources/AppIcon.icns" 2>/dev/null || true

plutil -create xml1 "$CONTENTS/Info.plist"
plutil -insert CFBundleName -string "Stay Put" "$CONTENTS/Info.plist"
plutil -insert CFBundleDisplayName -string "Stay Put" "$CONTENTS/Info.plist"
plutil -insert CFBundleIdentifier -string com.anirudh.stayput "$CONTENTS/Info.plist"
plutil -insert CFBundleExecutable -string Stayput "$CONTENTS/Info.plist"
plutil -insert CFBundlePackageType -string APPL "$CONTENTS/Info.plist"
plutil -insert CFBundleShortVersionString -string 1.1 "$CONTENTS/Info.plist"
plutil -insert CFBundleVersion -string 2 "$CONTENTS/Info.plist"
plutil -insert NSHumanReadableCopyright -string "Copyright © 2026 Anirudh Coontoor" "$CONTENTS/Info.plist"
plutil -insert LSMinimumSystemVersion -string 14.0 "$CONTENTS/Info.plist"
plutil -insert NSPrincipalClass -string NSApplication "$CONTENTS/Info.plist"
if [[ -f "$CONTENTS/Resources/AppIcon.icns" ]]; then
  plutil -insert CFBundleIconFile -string AppIcon "$CONTENTS/Info.plist"
fi

SIGN_IDENTITY="${CODE_SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Apple Development:[^"]*\)"/\1/p' | head -1)}"
codesign --force --deep --sign "${SIGN_IDENTITY:--}" "$APP"
echo "$APP"
