#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$project_dir/scripts/feature-flags.sh"

if [ "$#" -eq 0 ]; then set -- --interactive; fi

case "${1:-}" in
    --help|-h)
        echo 'Usage: sh scripts/build.sh [--interactive | --features all|none|calculator,qr,...] [xcodebuild options]'
        echo 'With no arguments, toggle features by number and press Enter to build.'
        echo 'Use --interactive to open the picker with additional build options.'
        printf 'Features: %s\n' "$(flint_feature_names)"
        echo 'The picker starts from Config/Features.xcconfig; builds with only Xcode options use it directly.'
        echo 'Additional options are passed to xcodebuild.'
        exit 0 ;;
    --interactive|-i)
        features=$(sh "$project_dir/scripts/select-features.sh")
        flags=$(flint_feature_flags "$features")
        shift
        set -- "FLINT_FEATURES=$flags" "$@" ;;
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
