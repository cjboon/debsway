#!/bin/bash
# Pick optional programs from a list and install them (lib/checklist.sh): arrow
# keys move (round the ends), Space or a click checks a box, the wheel scrolls,
# Enter or a click on Install installs.
# program is a script in extras/. install-base.sh asks right after you agree to
# the base install and installs what you picked once the base is done; you can
# run this again whenever you like. Nothing is checked to begin with.
# The list comes in three groups, from each extra's "# security:" line: most
# secure (walled off from your files or network, or it protects you), somewhat
# secure (everyday programs from signed sources, run as you) and least secure
# (easier, with less protection).
#   bash install-extras.sh               the list, then installs what you check
#   bash install-extras.sh --list        only print what is available
#   bash install-extras.sh --choose F    the list only; writes the names you checked to file F
#   bash install-extras.sh --install F   installs the names in file F (no list)
#   bash install-extras.sh --remove      a list of what is installed; removes what
#                                        you check (each extra's --remove), after asking
# ~/.config/debsway/preselect (one name a line, left by the install stick, e.g.
# make-install-iso.sh --simplesway) ticks those in the first list shown; it
# is then deleted, so later lists start empty again.
. "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
. "$DEBSWAY_DIR/lib/checklist.sh"

# The groups, most secure first: TIER<TAB>HEADING
TIERS=$'most\tMOST SECURE: walled off, or it protects you
some\tSOMEWHAT SECURE: everyday programs, run as you
least\tLEAST SECURE: easier, with less protection'
# tier_rank TIER: where its group comes (an extra without the line counts as some)
tier_rank() { case $1 in most) echo 1 ;; least) echo 3 ;; *) echo 2 ;; esac; }
# tier_heading TIER
tier_heading() { awk -F'\t' -v t="$1" '$1 == t { print $2 }' <<<"$TIERS"; }

# One line per extra: NAME<TAB>SUMMARY<TAB>installed(1|0)<TAB>TIER, in the
# groups' order, by name within each
mapfile -t EXTRAS < <(
    for f in "$DEBSWAY_DIR"/extras/*.sh; do
        name=$(basename -- "$f" .sh)
        summary=$(sed -n 's/^# summary: //p' "$f" | head -1)
        tier=$(sed -n 's/^# security: //p' "$f" | head -1)
        case $tier in most | some | least) ;; *) tier=some ;; esac
        installed=0
        if [ -n "$(script_found "$f")" ]; then installed=1; fi
        printf '%s\t%s\t%s\t%s\t%s\n' "$(tier_rank "$tier")" "$name" "${summary:-$name}" "$installed" "$tier"
    done | sort -t$'\t' -k1,1n -k2,2 | cut -f2-
)

if [ "${1:-}" = --list ]; then
    last=
    for line in "${EXTRAS[@]}"; do
        IFS=$'\t' read -r name summary installed tier <<<"$line"
        if [ "$tier" != "$last" ]; then
            printf '%s%s\n' "${last:+$'\n'}" "$(tier_heading "$tier")"
            last=$tier
        fi
        printf '  %-16s %s%s\n' "$name" "$summary" "$([ "$installed" = 1 ] && echo '  [installed]')"
    done
    exit 0
fi

mode=both file=
PRESELECT=$HOME/.config/debsway/preselect
# What the list says, and its buttons (--remove changes them)
TITLE="Optional extras" OK=Install CANCEL="No extras"
TEXT="Arrow keys or the wheel move; Space or a click checks a box.\n* = already installed (checking it runs it again, to repair or update).\nInstall puts the checked ones in; No extras finishes without any."
case "${1:-}" in
    --remove)
        mode=remove TITLE="Remove apps" OK=Remove CANCEL=Cancel
        TEXT="These are installed. Check the ones to remove (each keeps your own data, and says so).\nArrow keys or the wheel move; Space or a click checks a box."
        # Only what is installed
        mapfile -t EXTRAS < <(printf '%s\n' "${EXTRAS[@]}" | awk -F'\t' '$3 == 1')
        if [ ${#EXTRAS[@]} -eq 0 ]; then note "No extras are installed, so there is nothing to remove."; exit 0; fi ;;
    --choose) mode=choose file=${2:?"usage: install-extras.sh --choose FILE"} ;;
    --install) mode=install file=${2:?"usage: install-extras.sh --install FILE"} ;;
esac

chosen=()
if [ "$mode" != install ] && ! { : </dev/tty; } 2>/dev/null; then
    note "There is no terminal to ask on. Pick extras later with: bash install-extras.sh"
    [ "$mode" != choose ] || : >"$file"
    exit 0
fi


# checklist_items: the list's lines, three words each (TAG ITEM OFF), with a
# heading line before each group (~TIER: checking one does nothing)
checklist_items() {
    local line name summary installed tier last=''
    for line in "${EXTRAS[@]}"; do
        IFS=$'\t' read -r name summary installed tier <<<"$line"
        if [ "$tier" != "$last" ]; then
            ITEMS+=("~$tier" "== $(tier_heading "$tier") ==" OFF)
            last=$tier
        fi
        if [ "$installed" = 1 ] && [ "$mode" != remove ]; then summary="* $summary"; else summary="  $summary"; fi
        if [ "$mode" != remove ] && grep -qxF -- "$name" "$PRESELECT" 2>/dev/null; then
            ITEMS+=("$name" "$summary" ON)
        else
            ITEMS+=("$name" "$summary" OFF)
        fi
    done
}

# pick_with_list: the check boxes (lib/checklist.sh), into chosen
pick_with_list() {
    ITEMS=()
    checklist_items
    CL_TITLE=$TITLE CL_TEXT=$TEXT CL_OK=$OK CL_CANCEL=$CANCEL
    checklist || chosen=()
}

# Where the list can't be drawn (no terminal type): numbers typed at a prompt
pick_with_numbers() {
    local i=0 line name summary installed tier last='' reply n
    echo "$TITLE:"
    for line in "${EXTRAS[@]}"; do
        IFS=$'\t' read -r name summary installed tier <<<"$line"
        if [ "$tier" != "$last" ]; then
            printf '  %s\n' "$(tier_heading "$tier")"
            last=$tier
        fi
        i=$((i + 1))
        printf '  %2d) %-16s %s%s\n' "$i" "$name" "$summary" "$([ "$installed" = 1 ] && echo ' [installed]')"
    done
    tty_read reply "Numbers to $(tr '[:upper:]' '[:lower:]' <<<"$OK"), separated by spaces (Enter for none): "
    for n in $reply; do
        if [[ $n =~ ^[0-9]+$ ]] && [ "$n" -ge 1 ] && [ "$n" -le ${#EXTRAS[@]} ]; then
            chosen+=("${EXTRAS[n - 1]%%$'\t'*}")
        fi
    done
}

if [ "$mode" = install ]; then
    # the names were picked earlier (--choose): one per line
    mapfile -t chosen < <(grep . "$file" 2>/dev/null || true)
else
    say "$TITLE"
    if [ -n "${TERM:-}" ] && [ "$TERM" != dumb ]; then
        pick_with_list
    else
        pick_with_numbers
    fi
    # ticked once, by the stick: from now on the list starts empty
    [ "$mode" = remove ] || rm -f "$PRESELECT"
fi

if [ "$mode" = choose ]; then
    : >"$file"
    if [ ${#chosen[@]} -gt 0 ]; then printf '%s\n' "${chosen[@]}" >"$file"; fi
    if [ ${#chosen[@]} -eq 0 ]; then
        note "No extras chosen. Add some later with: debsway --apps"
    else
        note "To install after the base: ${chosen[*]}"
    fi
    exit 0
fi

if [ ${#chosen[@]} -eq 0 ]; then
    note "No extras chosen. Add some later with: debsway --apps"
    exit 0
fi

if [ "$mode" = remove ]; then
    # (a name not in the list is no extra that is installed: left alone)
    keep=()
    for name in "${chosen[@]}"; do
        printf '%s\n' "${EXTRAS[@]}" | cut -f1 | grep -qxF -- "$name" && keep+=("$name")
    done
    chosen=("${keep[@]}")
    [ ${#chosen[@]} -gt 0 ] || { note "Nothing removed."; exit 0; }
    if ! ask "Remove ${chosen[*]}? Each keeps your own data (it says where)." n; then
        note "Nothing removed."
        exit 0
    fi
    failed=()
    for name in "${chosen[@]}"; do
        say "Removing: $name"
        bash "$DEBSWAY_DIR/extras/$name.sh" --remove || failed+=("$name")
    done
    say "Removing done"
    if [ ${#failed[@]} -gt 0 ]; then
        warn "These didn't finish: ${failed[*]}. Try one again with: bash extras/NAME.sh --remove"
        pause_if_asked
        exit 1
    fi
    pause_if_asked
    exit 0
fi

failed=()
for name in "${chosen[@]}"; do
    [ -f "$DEBSWAY_DIR/extras/$name.sh" ] || continue
    say "Extra: $name"
    bash "$DEBSWAY_DIR/extras/$name.sh" || failed+=("$name")
done

say "Extras done"
if [ ${#failed[@]} -gt 0 ]; then
    warn "These failed: ${failed[*]}. Run one again with: bash extras/NAME.sh"
    pause_if_asked
    exit 1
fi
pause_if_asked
