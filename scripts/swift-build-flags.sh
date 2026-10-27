# Sourced with zsh by make-app.sh and check-build-flags.sh; does not run SwiftPM.
# Parse shell-style quoting without evaluating substitutions or executing shell code.
flags_string="${SWIFT_BUILD_FLAGS:-}"
# Keep these as separate stages: quoting the nested expansion creates one empty
# argument when the input has no words. An empty token array must stay empty.
# Treat unquoted newlines as whitespace in the flag list as well.
build_flags=(${(Z:n:)flags_string})
build_flags=("${(@Q)build_flags}")
