#!/bin/zsh
# Builds an offline, ad-hoc signed app with hardened runtime. Release is universal;
# CONFIG=debug builds the host architecture and retains the isolated development hooks.
set -euo pipefail
cd "$(dirname "$0")/.."

fail() {
    print -u2 -- "make-app: $*"
    exit 1
}

config="${CONFIG:-release}"
case "$config" in
    debug|release) ;;
    *) fail "CONFIG must be debug or release (got '$config')." ;;
esac

[[ -f VERSION ]] || fail "VERSION is missing."
version="$(< VERSION)"
[[ "$version" =~ '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$' ]] \
    || fail "VERSION must contain a numeric major.minor.patch version."

build_number="${BUILD_NUMBER:-${GITHUB_RUN_NUMBER:-}}"
if [[ -z "$build_number" ]]; then
    build_number="$(git rev-list --count HEAD)" \
        || fail "Cannot read git history; set BUILD_NUMBER when building a source archive."
fi
[[ "$build_number" =~ '^[1-9][0-9]*$' ]] || fail "The build number must be a positive integer."

[[ -f Resources/Info.plist && -f Resources/AppIcon.icns ]] \
    || fail "Bundle resources are missing; restore Resources/ or run swift scripts/make-icon.swift."

source scripts/swift-build-flags.sh
binaries=()
if [[ "$config" == release ]]; then
    # Separate builds work with Command Line Tools; a multi-arch SwiftPM build needs Xcode.
    for architecture in arm64 x86_64; do
        swift build "${build_flags[@]}" -c release --arch "$architecture"
        binaries+=("$(swift build "${build_flags[@]}" -c release --arch "$architecture" --show-bin-path)/Palpebra")
    done
else
    swift build "${build_flags[@]}" -c debug
    binaries+=("$(swift build "${build_flags[@]}" -c debug --show-bin-path)/Palpebra")
fi

# Assemble and verify in a staging directory before replacing the last successful bundle.
mkdir -p build
staging="$(mktemp -d build/.app-XXXXXX)"
trap 'rm -rf "$staging"' EXIT
trap 'exit 1' HUP INT TERM
app="$staging/Palpebra.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
if [[ "$config" == release ]]; then
    lipo -create "${binaries[@]}" -output "$app/Contents/MacOS/Palpebra"
    lipo "$app/Contents/MacOS/Palpebra" -verify_arch x86_64 arm64
else
    cp "${binaries[1]}" "$app/Contents/MacOS/Palpebra"
fi

cp Resources/Info.plist "$app/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string "$version" "$app/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$build_number" "$app/Contents/Info.plist"
plutil -lint "$app/Contents/Info.plist"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"

codesign --force --options runtime --sign - "$app"
codesign --verify --strict --verbose=2 "$app"
rm -rf build/Palpebra.app
mv "$app" build/Palpebra.app
print -- "Built build/Palpebra.app ($config, version $version, build $build_number)"
