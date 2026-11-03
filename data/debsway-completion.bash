# shellcheck shell=bash
# Tab completion for the debsway command: written by debsway parts/debsway-menu.sh
# (data/debsway-completion.bash), as ~/.local/share/bash-completion/completions/debsway,
# where Debian's bash-completion finds it. The options come from debsway --help
# and the names from the extras/ and parts/ folders, so nothing here goes stale.
_debsway() {
    local cur=${COMP_WORDS[COMP_CWORD]} prev=${COMP_WORDS[COMP_CWORD - 1]} dir f words=()
    COMPREPLY=()
    if [ "$COMP_CWORD" -eq 1 ]; then
        # every option, with and without its dashes
        mapfile -t words < <(debsway --help 2>/dev/null | sed -n 's/^  \(--[a-z]*\).*/\1/p')
        words+=("${words[@]#--}")
    elif [ "$COMP_CWORD" -eq 2 ]; then
        dir=$(debsway --dir 2>/dev/null) || return 0
        case $prev in
            install | --install | remove | --remove | manual | --manual)
                for f in "$dir"/extras/*.sh; do f=${f##*/}; words+=("${f%.sh}"); done ;;
            part | --part)
                for f in "$dir"/parts/*.sh; do f=${f##*/}; words+=("${f%.sh}"); done ;;
            --wifi | --bluetooth | --mic | --camera) words=(on off) ;;
            update | --update) words=(--since --all) ;;
            apps | --apps) words=(--list) ;;
        esac
    fi
    [ ${#words[@]} -gt 0 ] || return 0
    mapfile -t COMPREPLY < <(compgen -W "${words[*]}" -- "$cur")
}
complete -F _debsway debsway
