#!/bin/bash
# The core desktop: sway, foot and Firefox (with video codecs and uBlock
# Origin), a status bar, a key cheat sheet, and every part in parts/:
# automatic security updates, sound, launcher, lock and idle, brightness,
# screenshots, clipboard, notifications, USB automount, emoji, firewall,
# power profiles, Firefox hardening, NetworkManager and a random Wi-Fi MAC
# address. Apps people may not want are in extras/.
# Run as your normal user after you're online: bash install-base.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"

. "$DEBSWAY_DIR/packages.sh"

need_user
. /etc/os-release
[ "${VERSION_CODENAME:-}" = "$DEBIAN_RELEASE" ] ||
    warn "Written for Debian 13 ($DEBIAN_RELEASE); this is ${PRETTY_NAME:-unknown}."

say "Installing packages"
apt_install "${PKGS[@]}" "${PARTS_PKGS[@]}"

say "sway config"
ensure_sway_config
check_sway_config || die "sway reports errors in $SWAY_CONFIG"
note "$SWAY_CONFIG (stock config + include for $SWAY_SNIPPETS)"

say "Key cheat sheet"
# Super+? shows config/keys.txt; it also opens once on the first login
KEYS="$HOME/.local/share/debsway/keys.txt"
WELCOME="$HOME/.local/bin/debsway-welcome"
mkdir -p "${KEYS%/*}" "${WELCOME%/*}"
install -m 0644 "$DEBSWAY_DIR/config/keys.txt" "$KEYS"
cat >"$WELCOME" <<'EOF'
#!/bin/sh
# Shows the key cheat sheet on the first sway login only.
# Written by debsway install-base.sh
marker=${XDG_STATE_HOME:-$HOME/.local/state}/debsway/welcome-seen
[ -e "$marker" ] && exit 0
mkdir -p "${marker%/*}" && touch "$marker"
exec foot --app-id=debsway-keys less "$HOME/.local/share/debsway/keys.txt"
EOF
chmod +x "$WELCOME"
put_snippet help <<'EOF'
# Key cheat sheet on Super+? (debsway install-base.sh)
bindsym $mod+Shift+slash exec foot --app-id=debsway-keys less ~/.local/share/debsway/keys.txt
for_window [app_id="debsway-keys"] floating enable, resize set width 60 ppt height 85 ppt
exec ~/.local/bin/debsway-welcome
EOF
note "Super+? shows it. It also opens by itself on your first login."

say "sway status bar"
# config/sway-status shows wifi | volume | brightness | battery | date
STATUS="$HOME/.local/bin/sway-status"
if [ -f "$STATUS" ] && ! cmp -s "$DEBSWAY_DIR/config/sway-status" "$STATUS"; then
    cp "$STATUS" "$STATUS.bak"
    note "Old one kept as $STATUS.bak"
fi
install -m 0755 "$DEBSWAY_DIR/config/sway-status" "$STATUS"
note "Installed $STATUS"
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

say "Done"
if [ ${#failed[@]} -gt 0 ]; then
    warn "These parts failed: ${failed[*]}. Re-run one with: bash parts/NAME.sh"
fi
cat <<'EOF'
    Log out (exit) and log in on tty1. Super+? lists every key; it also
    opens by itself the first time. bash status.sh shows what's installed;
    extras/ has optional apps (bash extras/NAME.sh).
EOF
