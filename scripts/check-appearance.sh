#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
appearance_check_dir=$(mktemp -d "${TMPDIR:-/tmp}/flint-appearance.XXXXXX")
trap 'rm -rf "$appearance_check_dir"' EXIT

xcrun swiftc -swift-version 5 -parse-as-library \
    -module-cache-path "${CLANG_MODULE_CACHE_PATH:-$appearance_check_dir/module-cache}" \
    "$project_dir/Flint/Appearance.swift" \
    "$project_dir/Flint/KeyboardHint.swift" \
    "$project_dir/Flint/LauncherHeaderFooter.swift" \
    "$project_dir/Flint/LauncherDialog.swift" \
    "$project_dir/Flint/ApplicationRow.swift" \
    "$project_dir/Flint/ApplicationsViewController.swift" \
    "$project_dir/Flint/LauncherWindowController.swift" \
    "$project_dir/Flint/CalculatorResultView.swift" \
    "$project_dir"/Sources/FlintCore/*.swift \
    "$project_dir/Tests/FlintAppearanceChecks/CalculatorChecks.swift" \
    "$project_dir/Tests/FlintAppearanceChecks/LauncherDialogChecks.swift" \
    "$project_dir/Tests/FlintAppearanceChecks/main.swift" \
    -o "$appearance_check_dir/check"
"$appearance_check_dir/check"
