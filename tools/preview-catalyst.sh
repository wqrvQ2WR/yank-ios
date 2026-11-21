#!/bin/bash
# Xcode 없이 맥(Catalyst)으로 UIKit 화면을 띄워 레이아웃을 점검한다. 코어 동작은 tools/test.sh 로 따로 본다.
#   ./tools/preview-catalyst.sh            앱 실행
set -e
cd "$(dirname "$0")/.."
SDKP=$(xcrun --sdk macosx --show-sdk-path)
APP=build/catalyst/Yank.app
rm -rf build/catalyst; mkdir -p $APP/Contents/MacOS $APP/Contents/Resources
swiftc -swift-version 5 -parse-as-library -O -target arm64-apple-ios17.0-macabi -sdk $SDKP \
  -Fsystem $SDKP/System/iOSSupport/System/Library/Frameworks -I $SDKP/System/iOSSupport/usr/include \
  Yank/*.swift Yank/Core/*.swift Yank/UI/*.swift -o $APP/Contents/MacOS/Yank
# xcstrings -> lproj/.strings (Xcode 없이 문구 확인용)
python3 - <<'PY'
import json, os
d = json.load(open("Yank/Resources/Localizable.xcstrings"))["strings"]
langs = {}
for k, v in d.items():
    for c, loc in v["localizations"].items():
        langs.setdefault(c, {})[k] = loc["stringUnit"]["value"]
for c, m in langs.items():
    p = f"build/catalyst/Yank.app/Contents/Resources/{c}.lproj"; os.makedirs(p, exist_ok=True)
    with open(p + "/Localizable.strings", "w") as f:
        for k, v in m.items(): f.write('"%s" = "%s";\n' % (k, v.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n')))
PY
cat > $APP/Contents/Info.plist <<'PL'
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Yank</string><key>CFBundleIdentifier</key><string>com.hayoonjae.yank.preview</string>
<key>CFBundleName</key><string>Yank</string><key>CFBundlePackageType</key><string>APPL</string><key>CFBundleShortVersionString</key><string>1.0.0</string>
<key>CFBundleDevelopmentRegion</key><string>en</string><key>NSPhotoLibraryAddUsageDescription</key><string>Save videos</string>
<key>NSAppTransportSecurity</key><dict><key>NSExceptionDomains</key><dict><key>ts.net</key><dict><key>NSIncludesSubdomains</key><true/><key>NSExceptionAllowsInsecureHTTPLoads</key><true/></dict></dict></dict>
<key>LSMinimumSystemVersion</key><string>14.0</string><key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PL
codesign --force --sign - $APP >/dev/null 2>&1 || true
open $APP
