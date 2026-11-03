# shellcheck shell=bash
# Written by Wren Linux parts/command-hints.sh (data/command-hints.bash), as
# /usr/local/share/wren/command-hints.bash; ~/.bashrc loads it.
# A command that isn't installed anywhere: if a Wren Linux extra provides it
# (its "# status:" line names bin:NAME or file:/usr/local/bin/NAME), this
# says which script installs it. It only prints: it never installs or runs
# anything, and it looks up plain names only. Bash calls it only when no
# program of that name exists, so it never hides a real one. Anything else
# goes to Debian's command-not-found, if installed, as /etc/bash.bashrc does.
command_not_found_handle() {
    local dir=@WREN_DIR@ f line w script='' words=()
    if [[ $1 =~ ^[A-Za-z0-9][A-Za-z0-9._+-]{0,63}$ ]]; then
        for f in "$dir"/extras/*.sh; do
            line=$(grep -m1 '^# status:' "$f" 2>/dev/null) || continue
            read -ra words <<<"${line#\# status:}"
            for w in "${words[@]}"; do
                case $w in "bin:$1" | "file:/usr/local/bin/$1") script=${f##*/}; break 2 ;; esac
            done
        done
    fi
    if [ -n "$script" ]; then
        printf '%s: not installed. Wren Linux installs it with:\n    wrenctl install %s\n(or the Wren menu: Install apps)\n' \
            "$1" "${script%.sh}" >&2
        return 127
    fi
    if [ -x /usr/lib/command-not-found ]; then
        /usr/lib/command-not-found -- "$1"
        return $?
    fi
    printf '%s: command not found\n' "$1" >&2
    return 127
}
