# shellcheck shell=bash
# lib/checklist.sh: a list of check boxes on the whole terminal, for
# install-extras.sh (Install apps, Remove apps). Drawn by bash itself, as the
# Wren menu is, so it needs no other program:
#   arrows or j/k move, wrapping round at both ends; Page Up/Down and Home/End
#   jump; Space checks a box; Enter (or a click on the first button) goes on;
#   Esc or q (or a click on the second) cancels; the mouse wheel scrolls; a
#   click on a line checks its box. / or Tab (or a click) goes to the search box
#   at the bottom: what you type there narrows the list, by name and description, keeping
#   what's checked. Tab or an arrow goes back to the list, and Esc clears the search first.
# Sourced after lib.sh.
#
# checklist: shows ITEMS (an array of TAG DESCRIPTION ON|OFF triples; a TAG
# starting with ~ is a heading, which can't be checked) with CL_TITLE, CL_TEXT
# (lines, joined by \n), and the buttons CL_OK and CL_CANCEL. Sets chosen to
# the checked tags, in list order. Returns 1 if cancelled. CL_ALONE, if set,
# is the tag of a box that is only ever checked on its own ("none of these"):
# checking it unchecks the others, and checking another unchecks it.
CL_ESC_WAIT=${WREN_ESC_WAIT:-0.05}

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
                    CL_KEY=other
                    # three numbers, or nothing: bash arithmetic on CL_Y would
                    # run whatever else came in (pasted text can look like this)
                    [[ $report =~ ^[0-9]{1,4}\;[0-9]{1,4}\;[0-9]{1,4}$ ]] || return 0
                    IFS=';' read -r btn CL_X CL_Y <<<"$report"
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
    local view=() filter='' searching=false searchrow
    for ((i = 0; i < ${#ITEMS[@]}; i += 3)); do
        tags+=("${ITEMS[i]}") descs+=("${ITEMS[i + 1]}")
        if [ "${ITEMS[i + 2]}" = ON ]; then on+=(1); else on+=(0); fi
    done
    n=${#tags[@]}
    for ((i = 0; i < n; i++)); do [[ ${tags[i]} == "~"* ]] || { cur=$i; break; }; done
    mapfile -t textlines < <(printf '%b\n' "$CL_TEXT")
    # cl_toggle: the box on line cur checked or unchecked (and CL_ALONE kept alone)
    cl_toggle() {
        local k
        [ "$cur" -ge 0 ] || return 0
        on[cur]=$((1 - on[cur]))
        [ -n "${CL_ALONE:-}" ] && [ "${on[cur]}" = 1 ] || return 0
        for ((k = 0; k < n; k++)); do
            [ "$k" != "$cur" ] || continue
            if [ "${tags[cur]}" = "$CL_ALONE" ] || [ "${tags[k]}" = "$CL_ALONE" ]; then on[k]=0; fi
        done
    }
    # cl_view: which lines show: all, or those the search finds, each under its heading.
    # cur stays on its line if that still shows, else moves to the first that can be checked
    cl_view() {
        local f=${filter,,} k heading=-1 keep=false
        view=()
        for ((k = 0; k < n; k++)); do
            if [ -z "$f" ]; then view+=("$k"); continue; fi
            if [[ ${tags[k]} == "~"* ]]; then heading=$k; continue; fi
            if [[ ${tags[k],,} == *"$f"* || ${descs[k],,} == *"$f"* ]]; then
                if [ "$heading" -ge 0 ]; then view+=("$heading"); heading=-1; fi
                view+=("$k")
            fi
        done
        for k in "${view[@]}"; do [ "$k" != "$cur" ] || keep=true; done
        $keep && [ "$cur" -ge 0 ] && [[ ${tags[cur]} != "~"* ]] && return 0
        cur=-1
        for k in "${view[@]}"; do [[ ${tags[k]} == "~"* ]] || { cur=$k; break; }; done
        top=0
    }
    # cl_pos: where cur is in the view (-1: nowhere)
    cl_pos() {
        local k
        pos=-1
        for ((k = 0; k < ${#view[@]}; k++)); do [ "${view[k]}" != "$cur" ] || { pos=$k; return; }; done
    }
    # cl_step D: the next line that can be checked, D (1 or -1) lines on, round
    # the ends; cl_near D: the same, but stopping at the ends (the wheel)
    cl_step() {
        local pos m count=${#view[@]}
        [ "$count" -gt 0 ] || return 0
        cl_pos
        for ((m = 0; m < count; m++)); do
            pos=$(((pos + $1 + count) % count))
            [[ ${tags[view[pos]]} == "~"* ]] || { cur=${view[pos]}; return; }
        done
    }
    cl_near() {
        local pos
        cl_pos
        [ "$pos" -ge 0 ] || return 0
        while :; do
            pos=$((pos + $1))
            [ "$pos" -ge 0 ] && [ "$pos" -lt ${#view[@]} ] || return 0
            [[ ${tags[view[pos]]} == "~"* ]] || { cur=${view[pos]}; return; }
        done
    }
    cl_draw() {
        size=$(stty size </dev/tty 2>/dev/null || echo "24 80")
        read -r rows cols <<<"$size"
        head=$((2 + ${#textlines[@]}))
        listtop=$((head + 2))
        btnrow=$((rows - 1))
        searchrow=$((btnrow - 1))
        height=$((searchrow - listtop))
        [ "$height" -ge 1 ] || height=1
        local pos
        cl_pos
        if [ "$pos" -ge 0 ]; then
            [ "$pos" -ge "$top" ] || top=$pos
            [ "$pos" -lt $((top + height)) ] || top=$((pos - height + 1))
            # the heading just above the first line stays in sight
            if [ "$top" -gt 0 ] && [ "$top" -eq "$pos" ] && [[ ${tags[view[top - 1]]} == "~"* ]]; then top=$((top - 1)); fi
        fi
        # (E is the escape character; every code below starts with it)
        local E=$'\e'
        out="${E}[H${E}[2J${E}[1;3H${E}[1m${CL_TITLE:0:cols-4}${E}[0m"
        for ((j = 0; j < ${#textlines[@]}; j++)); do
            out+="${E}[$((3 + j));3H${textlines[j]:0:cols-4}"
        done
        for ((j = 0; j < height; j++)); do
            [ $((top + j)) -lt ${#view[@]} ] || break
            i=${view[top + j]}
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
        [ ${#view[@]} -gt 0 ] || out+="${E}[$listtop;3HNothing matches \"${filter:0:cols-24}\"."
        if $searching; then
            out+="${E}[$searchrow;3H${E}[7m Search: ${filter:0:cols-16}_ ${E}[0m"
        else
            out+="${E}[$searchrow;3H Search: ${filter:0:cols-16} ${E}[2m(/ or Tab)${E}[0m"
        fi
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
    cl_view
    while [ -z "$rc" ]; do
        cl_draw
        cl_key
        # In the search box, keys are letters. Only what prints goes in, so nothing typed
        # or pasted can reach the screen as a control code.
        if $searching; then
            case $CL_KEY in
                tab | enter) searching=false; continue ;;
                esc) filter='' searching=false; cl_view; continue ;;
                space) CL_KEY=' ' ;;
                up | down) searching=false ;;
            esac
            if [ ${#CL_KEY} -eq 1 ]; then
                if [ "$CL_KEY" = $'\x7f' ] || [ "$CL_KEY" = $'\b' ]; then
                    filter=${filter%?}
                elif [[ $CL_KEY == [[:print:]] ]] && [ ${#filter} -lt 40 ]; then
                    filter+=$CL_KEY
                fi
                cl_view
                continue
            fi
            [ "$CL_KEY" != click ] || searching=false
        fi
        case $CL_KEY in
            / | tab) searching=true ;;
            down | j) cl_step 1 ;;
            up | k) cl_step -1 ;;
            wheeldown) cl_near 1 ;;
            wheelup) cl_near -1 ;;
            pgdn) for ((j = 0; j < height; j++)); do cl_near 1; done ;;
            pgup) for ((j = 0; j < height; j++)); do cl_near -1; done ;;
            home) cur=-1; cl_step 1 ;;
            end) cur=-1; cl_step -1 ;;
            space | x)
                cl_toggle ;;
            enter) rc=0 ;;
            esc) if [ -n "$filter" ]; then filter=''; cl_view; else rc=1; fi ;;
            q) rc=1 ;;
            click)
                if [ "$CL_Y" -eq "$btnrow" ] && [ "$CL_X" -ge "$okfrom" ] && [ "$CL_X" -lt "$okto" ]; then
                    rc=0
                elif [ "$CL_Y" -eq "$btnrow" ] && [ "$CL_X" -ge "$cfrom" ] && [ "$CL_X" -lt "$cto" ]; then
                    rc=1
                elif [ "$CL_Y" -eq "$searchrow" ]; then
                    searching=true
                elif [ "$CL_Y" -ge "$listtop" ] && [ "$CL_Y" -lt $((listtop + height)) ]; then
                    j=$((top + CL_Y - listtop))
                    if [ "$j" -lt ${#view[@]} ] && [[ ${tags[view[j]]} != "~"* ]]; then
                        cur=${view[j]}
                        cl_toggle
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
