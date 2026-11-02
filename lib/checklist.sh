# shellcheck shell=bash
# lib/checklist.sh: a list of check boxes on the whole terminal, for
# install-extras.sh (Install apps, Remove apps). Drawn by bash itself, as the
# debsway menu is, so it needs no other program:
#   arrows or j/k move, wrapping round at both ends; Page Up/Down and Home/End
#   jump; Space checks a box; Enter (or a click on the first button) goes on;
#   Esc or q (or a click on the second) cancels; the mouse wheel scrolls; a
#   click on a line checks its box.
# Sourced after lib.sh.
#
# checklist: shows ITEMS (an array of TAG DESCRIPTION ON|OFF triples; a TAG
# starting with ~ is a heading, which can't be checked) with CL_TITLE, CL_TEXT
# (lines, joined by \n), and the buttons CL_OK and CL_CANCEL. Sets chosen to
# the checked tags, in list order. Returns 1 if cancelled.
CL_ESC_WAIT=${DEBSWAY_ESC_WAIT:-0.05}

# cl_key: the next key on the terminal, into CL_KEY (up down pgup pgdn home end
# space enter esc click wheelup wheeldown, or the character), with the click's
# column and row in CL_X and CL_Y
cl_key() {
    local c k2 k3 k4 report btn
    CL_KEY=other
    IFS= read -rsn1 c </dev/tty || { CL_KEY=esc; return; }
    case $c in
        '') CL_KEY=enter ;;
        ' ') CL_KEY=space ;;
        $'\t') CL_KEY=tab ;;
        $'\e')
            CL_KEY=esc   # a plain Esc has nothing after it; an arrow or a mouse report does, at once
            IFS= read -rsn1 -t "$CL_ESC_WAIT" k2 </dev/tty || return 0
            [ "$k2" = '[' ] || [ "$k2" = O ] || return 0
            IFS= read -rsn1 -t "$CL_ESC_WAIT" k3 </dev/tty || return 0
            case $k3 in
                A) CL_KEY=up ;;
                B) CL_KEY=down ;;
                H) CL_KEY=home ;;
                F) CL_KEY=end ;;
                [0-9])
                    IFS= read -rsn1 -t "$CL_ESC_WAIT" k4 </dev/tty || return 0   # the ~ that ends it
                    case $k3 in
                        1 | 7) CL_KEY=home ;;
                        4 | 8) CL_KEY=end ;;
                        5) CL_KEY=pgup ;;
                        6) CL_KEY=pgdn ;;
                        *) CL_KEY=other ;;
                    esac ;;
                '<')
                    # mouse: button;column;row then M (press) or m (release)
                    report=
                    while IFS= read -rsn1 -t "$CL_ESC_WAIT" c </dev/tty; do
                        if [ "$c" = M ] || [ "$c" = m ]; then break; fi
                        report+=$c
                    done
                    IFS=';' read -r btn CL_X CL_Y <<<"$report"
                    CL_KEY=other
                    if [ "$c" = M ]; then
                        case $btn in
                            0) CL_KEY=click ;;
                            64) CL_KEY=wheelup ;;
                            65) CL_KEY=wheeldown ;;
                        esac
                    fi ;;
                *) CL_KEY=other ;;
            esac ;;
        *) CL_KEY=$c ;;
    esac
}

checklist() {
    local tags=() descs=() on=() n i j cur=-1 top=0 saved rows cols size
    local textlines=() head listtop height btnrow okfrom okto cfrom cto out line mark rc
    for ((i = 0; i < ${#ITEMS[@]}; i += 3)); do
        tags+=("${ITEMS[i]}") descs+=("${ITEMS[i + 1]}")
        if [ "${ITEMS[i + 2]}" = ON ]; then on+=(1); else on+=(0); fi
    done
    n=${#tags[@]}
    for ((i = 0; i < n; i++)); do [[ ${tags[i]} == "~"* ]] || { cur=$i; break; }; done
    mapfile -t textlines < <(printf '%b\n' "$CL_TEXT")
    # cl_step D: the next line that can be checked, D (1 or -1) lines on, round
    # the ends; cl_near D: the same, but stopping at the ends (the wheel)
    cl_step() {
        local k=$cur m
        for ((m = 0; m < n; m++)); do
            k=$(((k + $1 + n) % n))
            [[ ${tags[k]} == "~"* ]] || { cur=$k; return; }
        done
    }
    cl_near() {
        local k=$cur
        while :; do
            k=$((k + $1))
            [ "$k" -ge 0 ] && [ "$k" -lt "$n" ] || return 0
            [[ ${tags[k]} == "~"* ]] || { cur=$k; return; }
        done
    }
    cl_draw() {
        size=$(stty size </dev/tty 2>/dev/null || echo "24 80")
        read -r rows cols <<<"$size"
        head=$((2 + ${#textlines[@]}))
        listtop=$((head + 2))
        btnrow=$((rows - 1))
        height=$((btnrow - listtop - 1))
        [ "$height" -ge 1 ] || height=1
        if [ "$cur" -ge 0 ]; then
            [ "$cur" -ge "$top" ] || top=$cur
            [ "$cur" -lt $((top + height)) ] || top=$((cur - height + 1))
            # the heading just above the first line stays in sight
            if [ "$top" -gt 0 ] && [ "$top" -eq "$cur" ] && [[ ${tags[top - 1]} == "~"* ]]; then top=$((top - 1)); fi
        fi
        # (E is the escape character; every code below starts with it)
        local E=$'\e'
        out="${E}[H${E}[2J${E}[1;3H${E}[1m${CL_TITLE:0:cols-4}${E}[0m"
        for ((j = 0; j < ${#textlines[@]}; j++)); do
            out+="${E}[$((3 + j));3H${textlines[j]:0:cols-4}"
        done
        for ((j = 0; j < height; j++)); do
            i=$((top + j))
            [ "$i" -lt "$n" ] || break
            if [[ ${tags[i]} == "~"* ]]; then
                line="  ${descs[i]}"
                out+="${E}[$((listtop + j));3H${E}[1m${line:0:cols-4}${E}[0m"
            else
                if [ "${on[i]}" = 1 ]; then mark='[x]'; else mark='[ ]'; fi
                printf -v line ' %s %-17s %s ' "$mark" "${tags[i]}" "${descs[i]}"
                if [ "$i" -eq "$cur" ]; then
                    out+="${E}[$((listtop + j));3H${E}[7m${line:0:cols-4}${E}[0m"
                else
                    out+="${E}[$((listtop + j));3H${line:0:cols-4}"
                fi
            fi
        done
        okfrom=3 okto=$((3 + ${#CL_OK} + 4))
        cfrom=$((okto + 3)) cto=$((cfrom + ${#CL_CANCEL} + 4))
        out+="${E}[$btnrow;${okfrom}H${E}[7m< $CL_OK >${E}[0m"
        out+="${E}[$btnrow;${cfrom}H< $CL_CANCEL >"
        out+="${E}[$rows;3H${E}[2mSpace or a click checks a box. Enter: $CL_OK. Esc: $CL_CANCEL.${E}[0m"
        printf '%s' "$out" >/dev/tty
    }
    saved=$(stty -g </dev/tty 2>/dev/null)
    printf '\e[?1049h\e[?25l\e[?1000h\e[?1006h' >/dev/tty
    stty -echo -icanon </dev/tty 2>/dev/null
    rc=
    while [ -z "$rc" ]; do
        cl_draw
        cl_key
        case $CL_KEY in
            down | j | tab) cl_step 1 ;;
            up | k) cl_step -1 ;;
            wheeldown) cl_near 1 ;;
            wheelup) cl_near -1 ;;
            pgdn) for ((j = 0; j < height; j++)); do cl_near 1; done ;;
            pgup) for ((j = 0; j < height; j++)); do cl_near -1; done ;;
            home) cur=-1; cl_step 1 ;;
            end) cur=0; cl_step -1 ;;
            space | x)
                if [ "$cur" -ge 0 ]; then on[cur]=$((1 - on[cur])); fi ;;
            enter) rc=0 ;;
            esc | q) rc=1 ;;
            click)
                if [ "$CL_Y" -eq "$btnrow" ] && [ "$CL_X" -ge "$okfrom" ] && [ "$CL_X" -lt "$okto" ]; then
                    rc=0
                elif [ "$CL_Y" -eq "$btnrow" ] && [ "$CL_X" -ge "$cfrom" ] && [ "$CL_X" -lt "$cto" ]; then
                    rc=1
                elif [ "$CL_Y" -ge "$listtop" ] && [ "$CL_Y" -lt $((listtop + height)) ]; then
                    i=$((top + CL_Y - listtop))
                    if [ "$i" -lt "$n" ] && [[ ${tags[i]} != "~"* ]]; then
                        cur=$i
                        on[cur]=$((1 - on[cur]))
                    fi
                fi ;;
        esac
    done
    printf '\e[?1000l\e[?1006l\e[?25h\e[?1049l' >/dev/tty
    [ -z "$saved" ] || stty "$saved" </dev/tty 2>/dev/null
    chosen=()
    if [ "$rc" = 0 ]; then
        for ((i = 0; i < n; i++)); do
            [ "${on[i]}" = 1 ] && [[ ${tags[i]} != "~"* ]] && chosen+=("${tags[i]}")
        done
    fi
    return "$rc"
}
