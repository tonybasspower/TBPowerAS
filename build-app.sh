#!/bin/bash
# Compila TBPower AS.app e tbpower-as-helper (come utente normale, NON con sudo).
# Richiede gli Strumenti a riga di comando di Xcode (Swift 5.5+, macOS 11+).
set -euo pipefail
cd "$(dirname "$0")"

# Compilazione diretta con swiftc, senza SwiftPM. Serve con alcune installazioni
# dei Command Line Tools (es. 14.3 su Ventura) in cui `swift build` si ferma con
# "xcrun: error: unable to lookup item 'PlatformPath'".
build_direct() {
  local out="build/swiftc" sdk
  sdk="$(xcrun --sdk macosx --show-sdk-path)"
  rm -rf "$out"; mkdir -p "$out/obj" "$out/CSMC"
  local flags=(-O -swift-version 5 -sdk "$sdk" -target arm64-apple-macos11.0 -I "$out/CSMC")
  clang -c -O2 -target arm64-apple-macos11.0 -isysroot "$sdk" \
    -I Sources/CSMC/include Sources/CSMC/smc.c -o "$out/obj/smc.o"
  clang -c -O2 -target arm64-apple-macos11.0 -isysroot "$sdk" \
    -I Sources/CSMC/include Sources/CSMC/charge.c -o "$out/obj/charge.o"
  printf 'module CSMC {\n  header "%s"\n  export *\n}\n' \
    "$PWD/Sources/CSMC/include/smc.h" > "$out/CSMC/module.modulemap"
  swiftc "${flags[@]}" -module-name TBPowerAS -parse-as-library Sources/TBPower/*.swift \
    "$out/obj/smc.o" "$out/obj/charge.o" -framework IOKit -framework CoreFoundation -framework Metal \
    -framework ServiceManagement -o "$out/TBPower"
  swiftc "${flags[@]}" -module-name tbpower_as_helper Sources/tbpower-as-helper/main.swift \
    "$out/obj/smc.o" "$out/obj/charge.o" -framework IOKit -framework CoreFoundation -o "$out/tbpower-as-helper"
  BIN="$PWD/$out"
}

# Deliberately arm64-only: never produce/install an Intel variant from this repo.
build_direct

APP="build/TBPower AS.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/TBPower" "$APP/Contents/MacOS/TBPowerAS"
cp Support/Info.plist "$APP/Contents/Info.plist"

# Icona app: AppIcon.icns (16..1024, @1x/@2x) dal master 1024 px.
ICONSET="build/AppIcon.iconset"
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
for sz in 16 32 128 256 512; do
  sips -z $sz $sz Support/Icon/AppIcon-1024.png --out "$ICONSET/icon_${sz}x${sz}.png" >/dev/null
  d=$((sz * 2))
  sips -z $d $d Support/Icon/AppIcon-1024.png --out "$ICONSET/icon_${sz}x${sz}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
/usr/libexec/PlistBuddy -c "Set :CFBundleIconFile AppIcon" "$APP/Contents/Info.plist" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP/Contents/Info.plist"
# Glifo della barra dei menu (template, 18 pt, @1x/@2x).
cp Support/Icon/MenuBarIcon.png Support/Icon/MenuBarIcon@2x.png Support/Icon/MenuBarChip.png Support/Icon/MenuBarChip@2x.png "$APP/Contents/Resources/"
cp "$BIN/tbpower-as-helper" build/tbpower-as-helper
# Firma ad-hoc (necessaria per SMAppService / avvio al login).
codesign --force --sign - "$APP"
codesign --force --sign - build/tbpower-as-helper

echo
echo "Fatto:"
echo "  $PWD/$APP"
echo "  $PWD/build/tbpower-as-helper"
echo 'Ora: sudo ./install-helper.sh 93 && open "/Applications/TBPower AS.app"'
