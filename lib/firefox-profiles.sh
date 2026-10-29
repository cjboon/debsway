# shellcheck shell=bash
# lib/firefox-profiles.sh: helpers for new-profile.sh, sourced after lib.sh and
# lib/firefox-sandbox.sh.

# Files written by the scripts here
OURS='debsway (extras/)?firefox-profiles/[a-z-]+\.sh'

# make_profile NAME URL FAST: a Firefox profile with a locked-down user of its
# own (fx-NAME), its settings, and the firefox-NAME command. FAST=yes turns the
# JavaScript JIT back on for this profile only. The user is like the sandboxed
# Firefox's (extras/firefox-sandbox.sh): no password, no login, none of your
# files; only the clipboard and ~/Downloads/NAME are shared with you.
make_profile() {
    local name=$1 url=$2 fast=$3 cmd="$BIN/firefox-$1" user=fx-$1 conf
    fx_profile_name_ok "$name" || die "\"$name\" can't be a profile name: lowercase letters, digits and dashes, starting with a letter, at most 28 long."
    # The sandbox itself (the group, the firewall, the session script) comes first
    if [ ! -x "$FX_CLIENT" ] || [ ! -x "$FX_SESSION" ]; then
        note "A profile with its own user needs the sandboxed Firefox (extras/firefox-sandbox.sh)."
        ask "Set that up now?" y || die "Nothing was changed."
        bash "$DEBSWAY_DIR/extras/firefox-sandbox.sh" || die "The sandboxed Firefox didn't finish; the profile was not made."
    fi
    say "Firefox profile: $name (user $user)"
    fx_create_user "$user" "$FX_HOME_ROOT/$name" "debsway Firefox profile $name"
    # Its address and JavaScript choice, in a file only root can write: the session
    # reads it as the profile's user, who has no way to change it
    conf="$FX_PROFILE_DIR/$name.conf"
    sudo install -d -o root -g root -m 0755 "$FX_PROFILE_DIR"
    printf '# Written by debsway extras/firefox-profiles/new-profile.sh\nurl=%s\nfast_js=%s\n' "$url" "$fast" |
        sudo tee "$conf" >/dev/null
    fx_allow_session "$user"
    note "$name: opens $url$([ "$fast" = yes ] && echo ', fast JavaScript'); runs as $user"

    mkdir -p "$BIN"
    if [ -e "$cmd" ] && ! grep -qsE "$OURS" "$cmd"; then
        warn "$cmd already exists and isn't ours; leaving it."
        return 0
    fi
    cat >"$cmd" <<EOF
#!/bin/sh
# firefox-$name: $url in its own Firefox profile, as its own locked-down user.
# Written by debsway extras/firefox-profiles/new-profile.sh
exec $FX_CLIENT --profile $name "\$@"
EOF
    chmod +x "$cmd"
    note "Start it with: firefox-$name   (Super+d finds it too)"
    note "Its downloads go to ~/Downloads/$name; it cannot read your files or the other profiles'."
    # Debian's standard ~/.profile adds ~/.local/bin to PATH at login
    grep -qs '\.local/bin' "$HOME/.profile" ||
        warn "$BIN isn't added to your PATH by ~/.profile; start it as $cmd"
}

# remove_profile NAME: removes firefox-NAME. A profile with a user of its own
# (made by this version) loses its sudo rule and its settings file, and you are
# asked whether to delete the logins and the user too; the older kind (a profile
# in your own Firefox) keeps its profile, as before.
remove_profile() {
    local name=$1 cmd="$BIN/firefox-$1" user=fx-$1 sandboxed=false
    if ! grep -qsE "$OURS" "$cmd"; then
        note "firefox-$name isn't set up."
        return 0
    fi
    # (decided from the launcher, before it is removed)
    if grep -qs -e 'firefox --profile' "$cmd"; then sandboxed=true; fi
    rm -f "$cmd"
    if ! $sandboxed; then
        note "Removed firefox-$name. The profile and its logins are kept;"
        note "delete it in Firefox at about:profiles if you want it gone."
        return 0
    fi
    fx_disallow_session "$user"
    sudo rm -f "$FX_PROFILE_DIR/$name.conf"
    note "Removed firefox-$name and the permission to run it."
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
