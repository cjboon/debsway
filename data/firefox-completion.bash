# shellcheck shell=bash
# Tab completion for the sandboxed Firefox command: written by Wren Linux
# extras/firefox-sandbox.sh (data/firefox-completion.bash), as
# ~/.local/share/bash-completion/completions/firefox, where Debian's
# bash-completion finds it. Its options, and after --profile or
# --remove-profile the profiles there are (their settings files' names).
_wren_firefox() {
    local cur=${COMP_WORDS[COMP_CWORD]} prev=${COMP_WORDS[COMP_CWORD - 1]} f words=()
    COMPREPLY=()
    case $prev in
        --profile | --remove-profile)
            for f in "${WREN_FX_PROFILE_DIR:-/etc/wren/firefox-profiles}"/*.conf; do
                [ -f "$f" ] || continue
                f=${f##*/}
                words+=("${f%.conf}")
            done ;;
        *)
            [ "$COMP_CWORD" -eq 1 ] || return 0
            words=(--profiles --new-profile --remove-profile --profile --no-audio) ;;
    esac
    [ ${#words[@]} -gt 0 ] || return 0
    mapfile -t COMPREPLY < <(compgen -W "${words[*]}" -- "$cur")
}
complete -F _wren_firefox firefox
