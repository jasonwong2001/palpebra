#!/bin/zsh
# Exercises the bundler's shared parser without running SwiftPM or touching app data.
set -euo pipefail
cd "$(dirname "$0")/.."

check_flags() {
    local case_name="$1"
    shift
    local -a expected=("$@")
    local -a build_flags
    local flags_string
    source scripts/swift-build-flags.sh

    if (( ${#build_flags[@]} != ${#expected[@]} )); then
        print -u2 -- "FAIL: $case_name: expected ${#expected[@]} arguments, got ${#build_flags[@]}."
        exit 1
    fi
    local index
    for (( index = 1; index <= ${#expected[@]}; index++ )); do
        if [[ "${build_flags[$index]}" != "${expected[$index]}" ]]; then
            print -u2 -- "FAIL: $case_name: argument $index: expected '${expected[$index]}', got '${build_flags[$index]}'."
            exit 1
        fi
    done
    print -- "PASS: $case_name"
}

unset SWIFT_BUILD_FLAGS
check_flags unset

SWIFT_BUILD_FLAGS=''
check_flags empty

SWIFT_BUILD_FLAGS='--disable-sandbox'
check_flags 'one flag' --disable-sandbox

SWIFT_BUILD_FLAGS='--disable-sandbox --verbose'
check_flags 'two flags' --disable-sandbox --verbose

SWIFT_BUILD_FLAGS='"--scratch-path=build with spaces"'
check_flags 'quoted flag containing a space' '--scratch-path=build with spaces'

SWIFT_BUILD_FLAGS='--disable-sandbox --scratch-path "build with spaces"'
check_flags 'multiple flags with a quoted value' --disable-sandbox --scratch-path 'build with spaces'

SWIFT_BUILD_FLAGS=$' \t\n '
check_flags 'whitespace only'

SWIFT_BUILD_FLAGS='--scratch-path ""'
check_flags 'explicit quoted empty value' --scratch-path ''
