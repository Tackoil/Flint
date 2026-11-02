#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$project_dir/scripts/feature-flags.sh"

case "${1:-}" in
    --help|-h)
        echo 'Usage: sh scripts/build.sh [--features all|none|calculator,qr,...] [xcodebuild options]'
        echo 'Features: calculator, timestamps, colors, number-bases, qr, translation, quick-links, scripts, system-actions'
        echo 'Defaults to Config/Features.xcconfig. Additional options are passed to xcodebuild.'
        exit 0 ;;
    --features)
        if [ "$#" -lt 2 ]; then echo '--features requires a feature list.' >&2; exit 2; fi
        flags=$(flint_feature_flags "$2")
        shift 2
        set -- "FLINT_FEATURES=$flags" "$@" ;;
esac

has_configuration=0
has_build_dir=0
for argument do
    case "$argument" in
        -configuration) has_configuration=1 ;;
        -derivedDataPath) has_build_dir=1 ;;
    esac
done
if [ "$has_configuration" -eq 0 ]; then set -- -configuration Debug "$@"; fi
if [ "$has_build_dir" -eq 0 ]; then set -- -derivedDataPath "$project_dir/build" "$@"; fi

exec xcodebuild -project "$project_dir/Flint.xcodeproj" -scheme Flint "$@" build
