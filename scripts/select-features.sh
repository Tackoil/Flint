#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$project_dir/scripts/feature-flags.sh"

selected_flags=$(sed -n 's/^[[:space:]]*FLINT_FEATURES[[:space:]]*=[[:space:]]*//p' "$project_dir/Config/Features.xcconfig" | tr '[:space:]' ' ')

is_selected() {
    case " $selected_flags " in
        *" $1 "*) return 0 ;;
        *) return 1 ;;
    esac
}

show_menu() {
    printf '\nChoose features (application launching is always included):\n' >&2
    index=0
    for name in $(flint_feature_names); do
        index=$((index + 1))
        mark=' '
        if is_selected "$(flint_feature_flags "$name")"; then mark=x; fi
        printf '  %s [%s] %s\n' "$index" "$mark" "$name" >&2
    done
    printf 'Number: toggle | a: all | n: none | Enter: build | q: cancel\n> ' >&2
}

toggle_feature() {
    name=$(flint_feature_names | cut -d ' ' -f "$1")
    flag=$(flint_feature_flags "$name")
    if is_selected "$flag"; then
        selected_flags=$(printf '%s\n' "$selected_flags" | sed "s/$flag//")
    else
        selected_flags="$selected_flags $flag"
    fi
}

print_selection() {
    selection=''
    for name in $(flint_feature_names); do
        if is_selected "$(flint_feature_flags "$name")"; then
            selection="${selection}${selection:+,}$name"
        fi
    done
    printf '%s\n' "${selection:-none}"
}

while true; do
    show_menu
    if ! IFS= read -r choice; then
        printf '\nInput ended; build cancelled.\n' >&2
        exit 1
    fi
    case "$choice" in
        '')
            selection=$(print_selection)
            printf '\nBuilding with features: %s\n' "$selection" >&2
            printf '%s\n' "$selection"
            exit 0 ;;
        a|all) selected_flags=$(flint_feature_flags all) ;;
        n|none) selected_flags='' ;;
        q|quit) printf 'Build cancelled.\n' >&2; exit 130 ;;
        [1-9]) toggle_feature "$choice" ;;
        *) printf 'Choose a number from 1 to 9, a, n, Enter, or q.\n' >&2 ;;
    esac
done
