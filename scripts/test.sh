#!/bin/zsh
# Runs the test suite. With only the Command Line Tools installed, `swift test`
# cannot find the Testing module by itself, so point it at the bundled framework.
set -euo pipefail
cd "$(dirname "$0")/.."

extra=()
developer_dir="$(xcode-select -p 2>/dev/null || true)"
if [[ "$developer_dir" == *CommandLineTools* ]]; then
    frameworks="$developer_dir/Library/Developer/Frameworks"
    extra+=(-Xswiftc -F -Xswiftc "$frameworks" -Xlinker -rpath -Xlinker "$frameworks")
    # Newer releases (Swift 6.3) load Swift Testing's interop library from a separate directory.
    interop="$developer_dir/Library/Developer/usr/lib"
    if [[ -f "$interop/lib_TestingInterop.dylib" ]]; then
        extra+=(-Xlinker -rpath -Xlinker "$interop")
    fi
    # Some CLT releases ship the Foundation overlay declaration but omit its module.
    if [[ -f "$frameworks/Testing.framework/Modules/Testing.swiftcrossimport/Foundation.swiftoverlay" \
        && ! -d "$frameworks/_Testing_Foundation.framework/Modules" ]]; then
        extra+=(-Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays)
    fi
fi
swift test "${extra[@]}" "$@"
