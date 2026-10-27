# shellcheck shell=bash
# lib/mime.sh: default applications (~/.config/mimeapps.list, read by
# Firefox and other apps). Sourced by lib.sh.

# set_default_app DESKTOP MIME...: opens these file types with DESKTOP
set_default_app() {
    local app=$1 f="$HOME/.config/mimeapps.list" mime tmp
    shift
    mkdir -p "${f%/*}"
    [ -f "$f" ] || printf '[Default Applications]\n' >"$f"
    grep -q '^\[Default Applications\]' "$f" || printf '\n[Default Applications]\n' >>"$f"
    for mime in "$@"; do
        tmp=$(mktemp)
        awk -v k="$mime" -v v="$app" '
            /^\[/ { if (sect && !done) { print k "=" v; done = 1 } sect = ($0 == "[Default Applications]") }
            sect && index($0, k "=") == 1 { if (!done) print k "=" v; done = 1; next }
            { print }
            END { if (!done) print k "=" v }' "$f" >"$tmp"
        mv "$tmp" "$f"
    done
}

# unset_default_app DESKTOP: forgets every default that points at DESKTOP
unset_default_app() {
    local f="$HOME/.config/mimeapps.list" esc
    [ -f "$f" ] || return 0
    # The name goes into a sed pattern, so its dots must not match anything
    esc=$(sed 's/[][\.*^$/]/\\&/g' <<<"$1")
    sed -i "/=$esc\$/d" "$f"
}
