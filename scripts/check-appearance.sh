#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$project_dir/scripts/feature-flags.sh"
if [ "$#" -gt 0 ]; then
    if [ "$#" -ne 2 ] || [ "$1" != '--features' ]; then
        echo 'Usage: sh scripts/check-appearance.sh [--features all|none|calculator,qr,...]' >&2
        exit 2
    fi
    flags=$(flint_feature_flags "$2")
    set -- -D FLINT_CUSTOM_FEATURES
    for flag in $flags; do set -- "$@" -D "$flag"; done
    export FLINT_BUILD_FEATURE_CHECKS_ONLY=1
fi
appearance_check_dir=$(mktemp -d "${TMPDIR:-/tmp}/flint-appearance.XXXXXX")
trap 'rm -rf "$appearance_check_dir"' EXIT

# Compile UI and core sources in one test executable so internal AppKit APIs stay testable.
# Keep the application entry point and lifecycle out of the offscreen test process.
find "$project_dir/Flint" "$project_dir/Sources/FlintCore" "$project_dir/Tests/FlintAppearanceChecks" \
    -name '*.swift' ! -path "$project_dir/Flint/App/*" -print | LC_ALL=C sort > "$appearance_check_dir/sources"
while IFS= read -r source; do
    set -- "$@" "$source"
done < "$appearance_check_dir/sources"

xcrun swiftc -swift-version 5 -parse-as-library -D FLINT_APPEARANCE_CHECKS \
    -module-cache-path "${CLANG_MODULE_CACHE_PATH:-$appearance_check_dir/module-cache}" \
    "$@" -o "$appearance_check_dir/check"
"$appearance_check_dir/check"
