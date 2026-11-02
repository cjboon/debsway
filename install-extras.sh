#!/bin/bash
# Pick optional programs from a list and install them: arrow keys to move,
# space bar to check a box, Tab to the Install or No extras button. With
# dialog (installed with the debsway menu), a click checks a box and a click on
# Install installs; without it, whiptail draws the list, which takes no clicks. Every
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
. "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"

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
        if [ "$installed" = 1 ]; then summary="* $summary"; else summary="  $summary"; fi
        ITEMS+=("$name" "$summary" OFF)
    done
}

# pick_with PROGRAM: the check boxes, drawn by dialog or whiptail (the same
# options), into chosen. Both draw on the terminal and answer on stderr.
pick_with() {
    local prog=$1 rows cols out c keep=() opts=()
    ITEMS=()
    checklist_items
    rows=$(stty size </dev/tty 2>/dev/null | cut -d' ' -f1)
    cols=$(stty size </dev/tty 2>/dev/null | cut -d' ' -f2)
    rows=${rows:-24} cols=${cols:-80}
    [ "$rows" -ge 14 ] || rows=14
    [ "$cols" -ge 76 ] || cols=76
    [ "$cols" -le 100 ] || cols=100
    if [ "$prog" = dialog ]; then
        opts=(--ok-label Install --cancel-label "No extras" --separate-output)
        # Its colours, as whiptail's below (yours win if you set DIALOGRC)
        [ -n "${DIALOGRC:-}" ] || export DIALOGRC=$DEBSWAY_DIR/data/dialogrc
    else
        opts=(--ok-button Install --cancel-button "No extras" --separate-output)
    fi
    if out=$("$prog" --title "Optional extras" "${opts[@]}" \
        --checklist "Arrow keys move, Space (or a click) checks a box, Tab reaches the buttons.\n* = already installed (checking it runs it again, to repair or update).\nInstall puts the checked ones in; No extras finishes without any." \
        $((rows - 2)) $((cols - 4)) $((rows - 10)) "${ITEMS[@]}" 3>&1 1>&2 2>&3 </dev/tty); then
        # One name per line (--separate-output); a heading, ~TIER, is no extra
        while IFS= read -r c; do
            [ -n "$c" ] && [[ $c != "~"* ]] && keep+=("$c")
        done <<<"$out"
        chosen=("${keep[@]}")
    else
        chosen=()
    fi
}

# Without whiptail: numbers typed at a prompt
pick_with_numbers() {
    local i=0 line name summary installed tier last='' reply n
    echo "Optional extras:"
    for line in "${EXTRAS[@]}"; do
        IFS=$'\t' read -r name summary installed tier <<<"$line"
        if [ "$tier" != "$last" ]; then
            printf '  %s\n' "$(tier_heading "$tier")"
            last=$tier
        fi
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
    if command -v dialog >/dev/null && [ -n "${TERM:-}" ] && [ "$TERM" != dumb ]; then
        pick_with dialog
    elif command -v whiptail >/dev/null && [ -n "${TERM:-}" ] && [ "$TERM" != dumb ]; then
        pick_with whiptail
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
