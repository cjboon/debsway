#!/bin/bash
# Pick optional programs from a list and install them: arrow keys to move,
# space bar to check a box, Tab to the Install or No extras button. Every
# program is a script in extras/; install-base.sh runs this at the end, and
# you can run it again whenever you like.
#   bash install-extras.sh          the list
#   bash install-extras.sh --list   only print what is available
. "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"

# One line per extra: NAME<TAB>SUMMARY<TAB>installed(1|0)
mapfile -t EXTRAS < <(
    for f in "$DEBSWAY_DIR"/extras/*.sh; do
        name=$(basename -- "$f" .sh)
        summary=$(sed -n 's/^# summary: //p' "$f" | head -1)
        installed=0
        if [ -n "$(script_found "$f")" ]; then installed=1; fi
        printf '%s\t%s\t%s\n' "$name" "${summary:-$name}" "$installed"
    done
)

if [ "${1:-}" = --list ]; then
    for line in "${EXTRAS[@]}"; do
        IFS=$'\t' read -r name summary installed <<<"$line"
        printf '  %-16s %s%s\n' "$name" "$summary" "$([ "$installed" = 1 ] && echo '  [installed]')"
    done
    exit 0
fi

if ! { : </dev/tty; } 2>/dev/null; then
    note "There is no terminal to ask on. Pick extras later with: bash install-extras.sh"
    exit 0
fi

chosen=()

# The checklist in grays on black, to match the terminal it opens in (whiptail
# is blue and red by default). Your own NEWT_COLORS wins if you set one.
export NEWT_COLORS=${NEWT_COLORS:-'
root=lightgray,black
roottext=lightgray,black
window=lightgray,black
border=gray,black
shadow=black,black
title=white,black
button=black,lightgray
actbutton=black,white
compactbutton=lightgray,black
checkbox=lightgray,black
actcheckbox=black,lightgray
listbox=lightgray,black
actlistbox=lightgray,black
sellistbox=white,black
actsellistbox=black,lightgray
textbox=lightgray,black
acttextbox=black,lightgray
entry=lightgray,black
disentry=gray,black
label=lightgray,black
helpline=gray,black
emptyscale=gray,black
fullscale=lightgray,black
'}

# whiptail comes with Debian's standard system: a list of check boxes
pick_with_whiptail() {
    local items=() line name summary installed rows cols out
    for line in "${EXTRAS[@]}"; do
        IFS=$'\t' read -r name summary installed <<<"$line"
        if [ "$installed" = 1 ]; then summary="* $summary"; else summary="  $summary"; fi
        items+=("$name" "$summary" OFF)
    done
    rows=$(stty size </dev/tty 2>/dev/null | cut -d' ' -f1)
    cols=$(stty size </dev/tty 2>/dev/null | cut -d' ' -f2)
    rows=${rows:-24} cols=${cols:-80}
    [ "$rows" -ge 14 ] || rows=14
    [ "$cols" -ge 76 ] || cols=76
    [ "$cols" -le 100 ] || cols=100
    # whiptail draws on the terminal and answers on stderr
    if out=$(whiptail --title "Optional extras" \
        --ok-button "Install" --cancel-button "No extras" \
        --checklist "Arrow keys move, Space checks a box, Tab reaches the buttons.\n* = already installed (checking it runs it again, to repair or update).\nInstall puts the checked ones in; No extras finishes without any." \
        $((rows - 2)) $((cols - 4)) $((rows - 10)) "${items[@]}" 3>&1 1>&2 2>&3 </dev/tty); then
        # Output looks like: "git" "mousepad"
        read -ra chosen <<<"${out//\"/}"
    else
        chosen=()
    fi
}

# Without whiptail: numbers typed at a prompt
pick_with_numbers() {
    local i=0 line name summary installed reply n
    echo "Optional extras:"
    for line in "${EXTRAS[@]}"; do
        IFS=$'\t' read -r name summary installed <<<"$line"
        i=$((i + 1))
        printf '  %2d) %-16s %s%s\n' "$i" "$name" "$summary" "$([ "$installed" = 1 ] && echo ' [installed]')"
    done
    tty_read reply "Numbers to install, separated by spaces (Enter for none): "
    for n in $reply; do
        if [[ $n =~ ^[0-9]+$ ]] && [ "$n" -ge 1 ] && [ "$n" -le ${#EXTRAS[@]} ]; then
            chosen+=("${EXTRAS[n - 1]%%$'\t'*}")
        fi
    done
}

say "Optional extras"
if command -v whiptail >/dev/null && [ -n "${TERM:-}" ] && [ "$TERM" != dumb ]; then
    pick_with_whiptail
else
    pick_with_numbers
fi

if [ ${#chosen[@]} -eq 0 ]; then
    note "No extras chosen. Add some later with: bash install-extras.sh"
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
