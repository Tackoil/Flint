#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
appearance_check_dir=$(mktemp -d "${TMPDIR:-/tmp}/flint-appearance.XXXXXX")
trap 'rm -rf "$appearance_check_dir"' EXIT

xcrun swiftc -swift-version 5 -parse-as-library -D FLINT_APPEARANCE_CHECKS \
    -module-cache-path "${CLANG_MODULE_CACHE_PATH:-$appearance_check_dir/module-cache}" \
    "$project_dir/Flint/Appearance.swift" \
    "$project_dir/Flint/SettingsKeyboardView.swift" \
    "$project_dir/Flint/SettingsActions.swift" \
    "$project_dir/Flint/SettingsActionsPopover.swift" \
    "$project_dir/Flint/SettingsActionsPresentation.swift" \
    "$project_dir/Flint/SettingsPopoverTransition.swift" \
    "$project_dir/Flint/SettingsKeyboardEvents.swift" \
    "$project_dir/Flint/SettingsArrowNavigation.swift" \
    "$project_dir/Flint/KeyboardHint.swift" \
    "$project_dir/Flint/LauncherHeaderFooter.swift" \
    "$project_dir/Flint/LauncherDialog.swift" \
    "$project_dir/Flint/ApplicationRow.swift" \
    "$project_dir/Flint/ApplicationsViewController.swift" \
    "$project_dir/Flint/LauncherWindowController.swift" \
    "$project_dir/Flint/CalculatorResultView.swift" \
    "$project_dir/Flint/ColorResultView.swift" \
    "$project_dir/Flint/NumberBaseResultView.swift" \
    "$project_dir/Flint/TranslationResultView.swift" \
    "$project_dir/Flint/QRCodeResultView.swift" \
    "$project_dir/Flint/TranslationSettingsView.swift" \
    "$project_dir/Flint/ShortcutRecorder.swift" \
    "$project_dir/Flint/LauncherHotKey.swift" \
    "$project_dir/Flint/QuickLinkSettingsView.swift" \
    "$project_dir/Flint/ScriptCommandView.swift" \
    "$project_dir/Flint/ScriptSettingsView.swift" \
    "$project_dir/Flint/QuickLinkOpening.swift" \
    "$project_dir/Flint/SettingsViewController.swift" \
    "$project_dir"/Sources/FlintCore/*.swift \
    "$project_dir/Tests/FlintAppearanceChecks/CalculatorChecks.swift" \
    "$project_dir/Tests/FlintAppearanceChecks/AppearanceCheckWindows.swift" \
    "$project_dir/Tests/FlintAppearanceChecks/ColorChecks.swift" \
    "$project_dir/Tests/FlintAppearanceChecks/NumberBaseChecks.swift" \
    "$project_dir/Tests/FlintAppearanceChecks/RoundingChecks.swift" \
    "$project_dir/Tests/FlintAppearanceChecks/LauncherDialogChecks.swift" \
    "$project_dir/Tests/FlintAppearanceChecks/TranslationChecks.swift" \
    "$project_dir/Tests/FlintAppearanceChecks/QRCodeChecks.swift" \
    "$project_dir/Tests/FlintAppearanceChecks/QuickLinkChecks.swift" \
    "$project_dir/Tests/FlintAppearanceChecks/ScriptChecks.swift" \
    "$project_dir/Tests/FlintAppearanceChecks/SettingsKeyboardChecks.swift" \
    "$project_dir/Tests/FlintAppearanceChecks/main.swift" \
    -o "$appearance_check_dir/check"
"$appearance_check_dir/check"
