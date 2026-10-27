# shellcheck shell=bash
# profiles.sh: helpers for new-profile.sh, sourced after lib.sh.

BIN="$HOME/.local/bin"
# Files written by the scripts here
OURS='debsway firefox-profiles/[a-z-]+\.sh'

# Firefox keeps using ~/.mozilla if it's there; new installs use ~/.config
if [ -f "$HOME/.mozilla/firefox/profiles.ini" ]; then
    ROOT="$HOME/.mozilla/firefox"
else
    ROOT="${XDG_CONFIG_HOME:-$HOME/.config}/mozilla/firefox"
fi
INI="$ROOT/profiles.ini"

need_firefox_closed() {
    is_installed firefox-esr || die "Firefox isn't installed. Run install-base.sh first."
    if pgrep -f '^/usr/lib/firefox-esr/firefox-esr' >/dev/null; then
        die "Close Firefox first; it rewrites its profile list when it exits."
    fi
}

# profile_path NAME: the profile's directory relative to ROOT, if it exists
profile_path() {
    [ -f "$INI" ] || return 0
    awk -v n="$1" '
        /^\[/ { if (name == n && path != "") { print path; found = 1; exit } name = ""; path = "" }
        /^Name=/ { name = substr($0, 6) }
        /^Path=/ { path = substr($0, 6) }
        END { if (!found && name == n && path != "") print path }' "$INI"
}

firefox_headless() { timeout 90 firefox-esr --headless "$@" >/dev/null 2>&1 || true; }

ensure_profile() {
    if [ -n "$(profile_path "$1")" ]; then
        note "$1: profile already exists"
    else
        firefox_headless -CreateProfile "$1"
        [ -n "$(profile_path "$1")" ] || die "Firefox didn't create the $1 profile."
        note "$1: profile created"
    fi
}

# write_userjs NAME < prefs: Firefox applies user.js on every start
write_userjs() {
    local f
    f="$ROOT/$(profile_path "$1")/user.js"
    if [ -f "$f" ] && ! grep -qE "^// Written by $OURS\$" "$f"; then
        warn "$f wasn't written by debsway; leaving it alone."
        return 0
    fi
    { echo "// Written by debsway firefox-profiles/new-profile.sh"; cat; } >"$f"
}

# make_profile NAME URL FAST: the profile, its settings and firefox-NAME.
# FAST=yes turns the JavaScript JIT back on for this profile only.
make_profile() {
    local name=$1 url=$2 fast=$3 cmd="$BIN/firefox-$1"
    need_firefox_closed
    say "Firefox profile: $name"
    ensure_profile "$name"
    {
        echo "// Opens $url on start; keeps its cookies and logins."
        echo 'user_pref("browser.startup.page", 1);'
        echo "user_pref(\"browser.startup.homepage\", \"$url\");"
        echo 'user_pref("browser.shell.checkDefaultBrowser", false);'
        if [ "$fast" = yes ]; then
            echo "// Fast JavaScript (JIT on) for this profile; the debsway default is off."
            echo 'user_pref("javascript.options.ion", true);'
            echo 'user_pref("javascript.options.baselinejit", true);'
            echo 'user_pref("javascript.options.native_regexp", true);'
            echo 'user_pref("javascript.options.asmjs", true);'
        fi
    } | write_userjs "$name"
    note "$name: opens $url$([ "$fast" = yes ] && echo ', fast JavaScript')"

    mkdir -p "$BIN"
    if [ -e "$cmd" ] && ! grep -qsE "$OURS" "$cmd"; then
        warn "$cmd already exists and isn't ours; leaving it."
        return 0
    fi
    cat >"$cmd" <<EOF
#!/bin/sh
# firefox-$name: $url in its own Firefox profile.
# Written by debsway firefox-profiles/new-profile.sh
[ \$# -gt 0 ] || set -- '$url'
exec firefox-esr --name firefox-$name -P $name "\$@"
EOF
    chmod +x "$cmd"
    note "Start it with: firefox-$name   (Super+d finds it too)"
    # Debian's standard ~/.profile adds ~/.local/bin to PATH at login
    grep -qs '\.local/bin' "$HOME/.profile" ||
        warn "$BIN isn't added to your PATH by ~/.profile; start it as $cmd"
}

# remove_profile NAME: removes firefox-NAME; the profile itself is kept
remove_profile() {
    local cmd="$BIN/firefox-$1"
    if grep -qsE "$OURS" "$cmd"; then
        rm -f "$cmd"
        note "Removed firefox-$1. The profile and its logins are kept;"
        note "delete it in Firefox at about:profiles if you want it gone."
    else
        note "firefox-$1 isn't set up."
    fi
}
