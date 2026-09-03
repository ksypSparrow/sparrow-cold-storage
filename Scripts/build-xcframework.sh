#!/bin/bash
# Builds ColdStorage.xcframework, with GRDB compiled inside it.
#
# ⚠️ Two things make this work, and both are easy to undo by accident:
#
#   1. The products are `type: .dynamic`. A static product gives you an
#      object file and no framework to package.
#   2. `internal import GRDB` keeps GRDB out of the public .swiftinterface.
#      With a plain `import`, consumers need the GRDB module at compile time
#      and the whole point — one package row, no GRDB — is lost.
#
# SwiftPM builds the framework without a Modules directory, so the .swiftmodule
# is copied in by hand before packaging. That step is not optional; without it
# the xcframework cannot be imported.
set -euo pipefail

NAME="${1:-ColdStorage}"
OUT="${OUT:-$PWD/build}"
DD="$OUT/dd"

rm -rf "$OUT/$NAME.xcframework"
ARGS=()

# ⚠️ macOS is not optional. `swift test` runs on the host, so an xcframework
# with only iOS slices makes the consuming package untestable from source — and
# this package declares .macOS support, which a Mac app relies on.
for dest in "generic/platform=iOS Simulator:Release-iphonesimulator" \
            "generic/platform=iOS:Release-iphoneos" \
            "generic/platform=macOS:Release" ; do
    destination="${dest%%:*}"
    config="${dest##*:}"

    xcodebuild build -scheme "$NAME" -destination "$destination" \
        -derivedDataPath "$DD" -configuration Release \
        BUILD_LIBRARY_FOR_DISTRIBUTION=YES SKIP_INSTALL=NO > /dev/null

    products="$DD/Build/Products/$config"
    framework="$products/PackageFrameworks/$NAME.framework"
    mkdir -p "$framework/Modules"
    cp -R "$products/$NAME.swiftmodule" "$framework/Modules/"

    # GRDB ships a privacy manifest in its own resource bundle. Statically
    # linking GRDB brings its code but not its resources, and Apple requires a
    # third-party SDK's PrivacyInfo.xcprivacy to travel with it.
    for bundle in "$products"/*.bundle; do
        [ -e "$bundle" ] && cp -R "$bundle" "$framework/"
    done
    ARGS+=(-framework "$framework")
done

xcodebuild -create-xcframework "${ARGS[@]}" -output "$OUT/$NAME.xcframework"

cd "$OUT"
rm -f "$NAME.xcframework.zip"
zip -qry "$NAME.xcframework.zip" "$NAME.xcframework"
echo "$OUT/$NAME.xcframework.zip"
swift package compute-checksum "$NAME.xcframework.zip" 2>/dev/null \
    || (cd - > /dev/null && swift package compute-checksum "$OUT/$NAME.xcframework.zip")
