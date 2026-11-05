# shellcheck shell=bash
# Tab completion for the Wren Linux command: written by Wren Linux parts/wren-menu.sh
# (data/wrenctl-completion.bash), as ~/.local/share/bash-completion/completions/wrenctl,
# where Debian's bash-completion finds it. The options come from wrenctl --help
# and the names from the extras/ and parts/ folders, so nothing here goes stale.
_wrenctl() {
    local cur=${COMP_WORDS[COMP_CWORD]} prev=${COMP_WORDS[COMP_CWORD - 1]} dir f words=()
    COMPREPLY=()
    if [ "$COMP_CWORD" -eq 1 ]; then
        # every option, with and without its dashes
        mapfile -t words < <(wrenctl --help 2>/dev/null | sed -n 's/^  \(--[a-z]*\).*/\1/p')
        words+=("${words[@]#--}")
    elif [ "$COMP_CWORD" -eq 2 ]; then
        dir=$(wrenctl --dir 2>/dev/null) || return 0
        case $prev in
            install | --install | remove | --remove | manual | --manual)
                for f in "$dir"/extras/*.sh; do f=${f##*/}; words+=("${f%.sh}"); done ;;
            part | --part)
                for f in "$dir"/parts/*.sh; do f=${f##*/}; words+=("${f%.sh}"); done ;;
            --wifi | --bluetooth | --mic | --camera) words=(on off) ;;
            update | --update) words=(--since --all) ;;
            apps | --apps) words=(--list) ;;
            git | --git) mapfile -t COMPREPLY < <(compgen -d -- "$cur"); return 0 ;;
            gh | --gh) words=(rulesets --logout) ;;
        esac
    fi
    [ ${#words[@]} -gt 0 ] || return 0
    mapfile -t COMPREPLY < <(compgen -W "${words[*]}" -- "$cur")
}
complete -F _wrenctl wrenctl
