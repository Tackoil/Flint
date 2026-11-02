#!/bin/sh
# Shared by the build and appearance-check entry points.
flint_feature_flags() {
    case "$1" in
        all) printf '%s\n' 'FLINT_CALCULATOR FLINT_TIMESTAMPS FLINT_COLORS FLINT_NUMBER_BASES FLINT_QR FLINT_TRANSLATION FLINT_QUICK_LINKS FLINT_SCRIPTS FLINT_SYSTEM_ACTIONS'; return ;;
        none) printf '\n'; return ;;
        '') echo 'Use all, none, or a comma-separated feature list.' >&2; return 2 ;;
    esac
    # Reject empty elements as well as unknown names before invoking a compiler.
    case "$1" in
        ,*|*,|*,,*) echo 'Feature lists cannot contain empty names.' >&2; return 2 ;;
    esac
    flint_remaining=$1
    flint_flags=
    while [ -n "$flint_remaining" ]; do
        flint_name=${flint_remaining%%,*}
        case "$flint_name" in
            calculator) flint_flag=FLINT_CALCULATOR ;;
            timestamps) flint_flag=FLINT_TIMESTAMPS ;;
            colors) flint_flag=FLINT_COLORS ;;
            number-bases) flint_flag=FLINT_NUMBER_BASES ;;
            qr) flint_flag=FLINT_QR ;;
            translation) flint_flag=FLINT_TRANSLATION ;;
            quick-links) flint_flag=FLINT_QUICK_LINKS ;;
            scripts) flint_flag=FLINT_SCRIPTS ;;
            system-actions) flint_flag=FLINT_SYSTEM_ACTIONS ;;
            *) printf 'Unknown Flint feature: %s\n' "$flint_name" >&2; return 2 ;;
        esac
        flint_flags="${flint_flags}${flint_flags:+ }$flint_flag"
        case "$flint_remaining" in
            *,*) flint_remaining=${flint_remaining#*,} ;;
            *) flint_remaining= ;;
        esac
    done
    printf '%s\n' "$flint_flags"
}
