#!/bin/bash
# Pick optional programs from a list and install them: arrow keys to move,
# space bar to check a box, Tab to the Install or No extras button. Every
# program is a script in extras/. install-base.sh asks right after you agree to
# the base install and installs what you picked once the base is done; you can
# run this again whenever you like. Nothing is checked to begin with.
#   bash install-extras.sh               the list, then installs what you check
#   bash install-extras.sh --list        only print what is available
#   bash install-extras.sh --choose F    the list only; writes the names you checked to file F
#   bash install-extras.sh --install F   installs the names in file F (no list)
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

mode=both file=
case "${1:-}" in
    --choose) mode=choose file=${2:?"usage: install-extras.sh --choose FILE"} ;;
    --install) mode=install file=${2:?"usage: install-extras.sh --install FILE"} ;;
esac

chosen=()
if [ "$mode" != install ] && ! { : </dev/tty; } 2>/dev/null; then
    note "There is no terminal to ask on. Pick extras later with: bash install-extras.sh"
    [ "$mode" != choose ] || : >"$file"
    exit 0
fi

# The checklist in white on black, to match the terminal it opens in, the
# chosen line reversed. Your own NEWT_COLORS wins if you set one. The same
# block as bin/nmtui.
# A button is drawn in compactbutton colors until Tab reaches it, then in button colors:
# button is the reversed pair so the chosen one shows.
# newt (whiptail, nmtui) reads #rrggbb colors only when the terminal says it
# has 24-bit color (COLORTERM=truecolor); otherwise it ignores them all and
# draws its own blue and red, the chosen line hard to see. foot has 24-bit
# color, so it is said for it. The Linux console has none and gets color
# names (its black is black; foot's "black" is a dark teal). Every one of
# newt's color sets is given: one left out stays red.
if [ -z "${NEWT_COLORS:-}" ]; then
    if [ "${TERM:-}" = linux ]; then
        _w=white _b=black _g=gray
    else
        _w='#ffffff' _b='#000000' _g='#aaaaaa'
        case ${COLORTERM:-} in truecolor | 24bit) ;; *) export COLORTERM=truecolor ;; esac
    fi
    NEWT_COLORS="root=$_w,$_b border=$_w,$_b window=$_w,$_b shadow=$_b,$_b title=$_w,$_b"
    NEWT_COLORS+=" button=$_b,$_w actbutton=$_b,$_w compactbutton=$_w,$_b"
    NEWT_COLORS+=" checkbox=$_w,$_b actcheckbox=$_b,$_w entry=$_w,$_b disentry=$_g,$_b label=$_w,$_b"
    NEWT_COLORS+=" listbox=$_w,$_b actlistbox=$_b,$_w sellistbox=$_w,$_b actsellistbox=$_b,$_w"
    NEWT_COLORS+=" textbox=$_w,$_b acttextbox=$_b,$_w helpline=$_w,$_b roottext=$_w,$_b"
    NEWT_COLORS+=" emptyscale=$_w,$_b fullscale=$_b,$_w"
    unset _w _b _g
fi
export NEWT_COLORS

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

if [ "$mode" = install ]; then
    # the names were picked earlier (--choose): one per line
    mapfile -t chosen < <(grep . "$file" 2>/dev/null || true)
else
    say "Optional extras"
    if command -v whiptail >/dev/null && [ -n "${TERM:-}" ] && [ "$TERM" != dumb ]; then
        pick_with_whiptail
    else
        pick_with_numbers
    fi
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
