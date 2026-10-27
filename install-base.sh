#!/bin/bash
# The core desktop: sway and foot, a status bar, a key cheat sheet, and
# every part in parts/: automatic security updates, sound, launcher, lock
# and idle, brightness, screenshots, clipboard, notifications, USB
# automount, emoji, firewall, power profiles, NetworkManager and a random
# Wi-Fi MAC address. Everything else is in extras/, Firefox included (with
# its hardening and the throwaway "incognito" Firefox); a list at the end
# lets you pick some.
# It starts by explaining what it will do and asking whether to go on.
# Run as your normal user after you're online:
#   bash install-base.sh          explains, asks, installs
#   bash install-base.sh --yes    skips the explanation and the question
. "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"

assume_yes=false
if [ "${1:-}" = --yes ]; then
    assume_yes=true
    shift
else
    bash "$DEBSWAY_DIR/prep/intro.sh" || exit 1
fi

. "$DEBSWAY_DIR/packages.sh"

need_user
. /etc/os-release
[ "${VERSION_CODENAME:-}" = "$DEBIAN_RELEASE" ] ||
    warn "Written for Debian 13 ($DEBIAN_RELEASE); this is ${PRETTY_NAME:-unknown}."

# Before anything is downloaded, so all of it can go through Tor
if ! $assume_yes; then
    say "Packages through Tor?"
    note "apt can download Debian's packages through Tor, over https, with obfs4 bridges"
    note "that you paste in: your network then can't see which packages you get, and it's"
    note "slower. You can also do it later: bash parts/apt-tor.sh"
    if ask "Download packages through Tor?" n; then
        bash "$DEBSWAY_DIR/parts/apt-tor.sh" ||
            warn "apt-tor didn't finish; packages will download the normal way."
    fi
fi

say "Installing packages"
apt_install "${PKGS[@]}"

say "sway config"
ensure_sway_config
check_sway_config || die "sway reports errors in $SWAY_CONFIG"
note "$SWAY_CONFIG (stock config + include for $SWAY_SNIPPETS)"

say "Key cheat sheet"
# Super+? shows data/keys.txt; it also opens once on the first login
KEYS="$HOME/.local/share/debsway/keys.txt"
mkdir -p "${KEYS%/*}"
install -m 0644 "$DEBSWAY_DIR/data/keys.txt" "$KEYS"
install_bin debsway-welcome
put_snippet help <<'EOF'
# Key cheat sheet on Super+? (debsway install-base.sh)
bindsym $mod+Shift+slash exec foot --app-id=debsway-keys less ~/.local/share/debsway/keys.txt
for_window [app_id="debsway-keys"] floating enable, resize set width 60 ppt height 85 ppt
exec ~/.local/bin/debsway-welcome
EOF
note "Super+? shows it. It also opens by itself on your first login."

say "sway status bar"
# bin/sway-status shows wifi | volume | brightness | battery | date
install_bin sway-status
# Edit the stock bar in place; a second bar block would add a second bar
if grep -q 'status_command while date' "$SWAY_CONFIG"; then
    sed -i 's|^\([[:space:]]*\)status_command while date.*|\1status_command ~/.local/bin/sway-status|' "$SWAY_CONFIG"
    note "Bar now runs sway-status."
fi
check_sway_config || die "sway reports errors in $SWAY_CONFIG"
reload_sway

say "Start sway on tty1 login"
PROFILE="$HOME/.profile"
if grep -q '>>> debsway autostart' "$PROFILE" 2>/dev/null; then
    note "Already set up in $PROFILE"
elif ask "Start sway automatically when you log in on tty1?" y; then
    cat >>"$PROFILE" <<'EOF'

# >>> debsway autostart >>>
if [ "$(tty)" = /dev/tty1 ] && [ -z "${WAYLAND_DISPLAY:-}" ]; then
    exec env XDG_CURRENT_DESKTOP=sway sway
fi
# <<< debsway autostart <<<
EOF
    note "Added to $PROFILE. Other ttys (Ctrl+Alt+F2) still give a plain shell."
else
    note "Start it yourself by typing: sway"
fi

# Last, because the network-manager part can drop the connection briefly
failed=()
for part in "${PARTS[@]}"; do
    say "Part: $part"
    bash "$DEBSWAY_DIR/parts/$part.sh" || failed+=("$part")
done

if [ ${#failed[@]} -gt 0 ]; then
    warn "These parts failed: ${failed[*]}. Re-run one with: bash parts/NAME.sh"
fi

# The optional programs: a list to check boxes in, or none
bash "$DEBSWAY_DIR/install-extras.sh" ||
    warn "Some extras didn't install; the message above says which."

say "Done"
cat <<'EOF'
    Log out (exit) and log in on tty1. Super+? lists every key; it also
    opens by itself the first time. bash status.sh shows what's installed;
    bash install-extras.sh picks more extras any time. incognito opens a
    throwaway Firefox. Reboot once: the boot hardening applies after it
    (check with: cat /proc/cmdline).
EOF
