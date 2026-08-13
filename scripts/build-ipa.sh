#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/output"
mkdir -p "$OUT"

if [[ "$(uname)" != "Darwin" ]]; then
  echo "IPA-Builds brauchen macOS + Xcode."
  exit 1
fi

TEAM="${DEVELOPMENT_TEAM:-}"
ARCHIVE="$OUT/NOCORunning.xcarchive"
IPA_DIR="$OUT/ipa"

xcodebuild \
  -project "$ROOT/ios/NOCORunning.xcodeproj" \
  -scheme NOCORunning \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  archive \
  ${TEAM:+DEVELOPMENT_TEAM=$TEAM}

if [[ -n "${TEAM}" ]]; then
  cat > "$OUT/exportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>development</string>
  <key>signingStyle</key>
  <string>automatic</string>
  <key>teamID</key>
  <string>${TEAM}</string>
</dict>
</plist>
EOF
  xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$IPA_DIR" -exportOptionsPlist "$OUT/exportOptions.plist"
  open "$OUT"
else
  echo "Archive liegt unter $ARCHIVE"
  echo "Setze DEVELOPMENT_TEAM für den IPA-Export, danach: open $OUT"
  open "$OUT"
fi
