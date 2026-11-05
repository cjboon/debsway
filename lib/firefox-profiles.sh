# shellcheck shell=bash
# lib/firefox-profiles.sh: helpers for new-profile.sh, sourced after lib.sh and
# lib/firefox-sandbox.sh.

# Files written by the scripts here
OURS='Wren Linux (extras/)?firefox-profiles/[a-z-]+\.sh'

# fx_cmd_taken NAME: a command, builtin or keyword is called NAME already.
# ~/.local/bin comes first in PATH, so a profile's command must never take
# such a name: it would stand in for that program (git, sudo, ls...).
fx_cmd_taken() {
    local d
    [ -z "$(type -t "$1")" ] || return 0
    for d in /usr/local/sbin /usr/local/bin /usr/sbin /usr/bin /sbin /bin /usr/local/games /usr/games "$HOME/bin"; do
        [ ! -e "$d/$1" ] || return 0
    done
    return 1
}
# fx_profile_cmd NAME: the command that opens the profile NAME: NAME itself
# (github), or firefox-NAME when NAME is taken or one of yours (not ours) is there
fx_profile_cmd() {
    local short=$BIN/$1
    if [ -e "$short" ]; then
        if grep -qsE "$OURS" "$short"; then echo "$short"; return; fi
    elif ! fx_cmd_taken "$1"; then
        echo "$short"
        return
    fi
    echo "$BIN/firefox-$1"
}

# make_profile NAME URL FAST [TOOLBARS [SOUND [COOKIES]]]: a Firefox profile with a
# locked-down user of its own (fx-NAME), its settings, and a command that opens
# it: NAME, or firefox-NAME when NAME is a command already (fx_profile_cmd).
# FAST=yes turns the JavaScript JIT back on for this profile only. TOOLBARS is
# hidden (the default: the window shows only the page) or shown. SOUND is yes
# (the default) or no. COOKIES is keep (the default: you stay logged in) or
# delete (cookies, site data and the cache go when it closes). The user is like the sandboxed
# Firefox's (extras/firefox-sandbox.sh): no password, no login, none of your
# files; only the clipboard and ~/Downloads/NAME are shared with you.
make_profile() {
    local name=$1 url=$2 fast=$3 toolbars=${4:-hidden} sound=${5:-yes} cookies=${6:-keep} cmd user=fx-$1 conf
    case $toolbars in hidden | shown) ;; *) die "TOOLBARS is hidden or shown, not \"$toolbars\"." ;; esac
    case $sound in yes | no) ;; *) die "SOUND is yes or no, not \"$sound\"." ;; esac
    case $cookies in keep | delete) ;; *) die "COOKIES is keep or delete, not \"$cookies\"." ;; esac
    fx_profile_name_ok "$name" || die "\"$name\" can't be a profile name: lowercase letters, digits and dashes, starting with a letter, at most 28 long (and not esr, restart-check or session)."
    cmd=$(fx_profile_cmd "$name")
    # A firefox-NAME command that isn't ours: stop before any user or rule is made
    if [ -e "$cmd" ] && ! grep -qsE "$OURS" "$cmd"; then
        die "$cmd already exists and isn't Wren Linux's; pick another name. Nothing was changed."
    fi
    # The sandbox itself (the group, the firewall, the session script) comes first
    if [ ! -x "$FX_CLIENT" ] || [ ! -x "$FX_SESSION" ]; then
        note "A profile with its own user needs the sandboxed Firefox (extras/firefox-sandbox.sh)."
        ask "Set that up now?" y || die "Nothing was changed."
        bash "$WREN_DIR/extras/firefox-sandbox.sh" || die "The sandboxed Firefox didn't finish; the profile was not made."
    fi
    say "Firefox profile: $name (user $user)"
    fx_create_user "$user" "$FX_HOME_ROOT/$name" "Wren Linux Firefox profile $name"
    # Its address and its choices, in a file only root can write: the session
    # reads it as the profile's user, who has no way to change it (and the
    # firefox command, for sound)
    conf="$FX_PROFILE_DIR/$name.conf"
    sudo install -d -o root -g root -m 0755 "$FX_PROFILE_DIR"
    printf '# Written by Wren Linux extras/firefox-profiles/new-profile.sh\nurl=%s\nfast_js=%s\ntoolbars=%s\nsound=%s\ncookies=%s\n' "$url" "$fast" "$toolbars" "$sound" "$cookies" |
        sudo tee "$conf" >/dev/null
    fx_allow_session "$user"
    note "$name: opens $url$([ "$fast" = yes ] && echo ', fast JavaScript')$([ "$sound" = no ] && echo ', no sound')$([ "$cookies" = delete ] && echo ', cookies deleted when it closes'); runs as $user"
    if [ "$toolbars" = hidden ]; then
        note "Its window shows only the page: no tabs or address bar. Keys still work:"
        note "  Alt+Left back, Alt+Right forward, F5 reload, Ctrl+W close."
    fi

    mkdir -p "$BIN"
    cat >"$cmd" <<EOF
#!/bin/sh
# ${cmd##*/}: $url in its own Firefox profile, as its own locked-down user.
# Written by Wren Linux extras/firefox-profiles/new-profile.sh
exec $FX_CLIENT --profile $name "\$@"
EOF
    chmod +x "$cmd"
    # the other name, from an older version: one command per profile
    fx_remove_cmd "$name" "$cmd"
    if [ "$cmd" != "$BIN/$name" ]; then
        note "\"$name\" is a command already, so this one is called ${cmd##*/}."
    fi
    note "Start it with: ${cmd##*/}   (Super+d finds it too)"
    note "Its downloads go to ~/Downloads/$name; it cannot read your files or the other profiles'."
    # Debian's standard ~/.profile adds ~/.local/bin to PATH at login
    grep -qs '\.local/bin' "$HOME/.profile" ||
        warn "$BIN isn't added to your PATH by ~/.profile; start it as $cmd"
}

# fx_remove_cmd NAME [KEEP]: removes the profile's commands that are ours (NAME,
# firefox-NAME), but KEEP
fx_remove_cmd() {
    local c
    for c in "$BIN/$1" "$BIN/firefox-$1"; do
        if [ "$c" != "${2:-}" ] && grep -qsE "$OURS" "$c"; then rm -f "$c"; fi
    done
}

# remove_profile NAME: removes its command (NAME or firefox-NAME). A profile with
# a user of its own (made by this version) loses its sudo rule and its settings
# file, and you are asked whether to delete the logins and the user too; the
# older kind (a profile in your own Firefox) keeps its profile, as before. A
# profile whose command is gone (deleted by hand, or a run that stopped
# part-way) is still removed from its settings file or its user.
remove_profile() {
    local name=$1 c cmd='' user=fx-$1 sandboxed=false
    for c in "$BIN/$name" "$BIN/firefox-$name"; do
        if grep -qsE "$OURS" "$c"; then cmd=$c; fi
    done
    # (decided from the launcher, before it is removed; your user can't look
    # into /etc/sudoers.d, so the rule itself can't tell)
    if grep -qs -e 'firefox --profile' "$cmd"; then sandboxed=true; fi
    if [ -e "$FX_PROFILE_DIR/$name.conf" ] || id "$user" >/dev/null 2>&1; then sandboxed=true; fi
    if [ -z "$cmd" ] && ! $sandboxed; then
        note "The profile $name isn't set up."
        return 0
    fi
    fx_remove_cmd "$name"
    if ! $sandboxed; then
        note "Removed ${cmd##*/}. The profile and its logins are kept;"
        note "delete it in Firefox at about:profiles if you want it gone."
        return 0
    fi
    fx_disallow_session "$user"
    sudo rm -f "$FX_PROFILE_DIR/$name.conf"
    note "Removed ${cmd:+${cmd##*/}, }the permission to run it and its settings."
    if id "$user" >/dev/null 2>&1; then
        note "Its logins and history are kept in $FX_HOME_ROOT/$name (user $user, locked)."
        if ask "Delete them and the user too?" n; then
            sudo pkill -KILL -u "$user" 2>/dev/null || true
            sudo userdel "$user" 2>/dev/null || true
            sudo rm -rf "${FX_HOME_ROOT:?}/$name" "/dev/shm/$user-run"
            note "Deleted the profile and its user. Files it downloaded are still in ~/Downloads/$name."
        fi
    fi
}

# The ready-made profiles (data/firefox-profiles.list)
FX_CATALOG=$WREN_DIR/data/firefox-profiles.list
# fx_catalog NAME: "URL FAST TOOLBARS SOUND COOKIES ALLOW" of the ready-made
# profile NAME, or nothing (and status 1) when there is none by that name
fx_catalog() {
    awk -v n="$1" '!/^#/ && $1 == n { print $2, $3, $4, $5, $6, $7; f = 1; exit } END { exit !f }' "$FX_CATALOG"
}
# fx_catalog_list: the ready-made profiles, by kind, each with what it is
fx_catalog_list() {
    awk '/^# [A-Z]/ && !/^# [A-Z]+ +[A-Z]/ { if (NR > 15) printf "\n%s\n", substr($0, 3); next }
         !/^#/ && NF { d = $0; sub(/^[^#]*# /, "", d); printf "  %-14s %s\n", $1, d }' "$FX_CATALOG"
}
