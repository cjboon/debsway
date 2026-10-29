#!/bin/bash
# Firefox as its own locked-down user, for everyday browsing. The firefox
# command opens it as a normal window on your sway, but it runs as a different
# user ("firefox") that has no password, no login and none of your files, so a
# hacked page reaches only that user's own profile, not your documents, ssh keys
# or passwords.
#  - Your logins, history and bookmarks are kept, in that user's own home
#    (/var/lib/debsway-firefox).
#  - The clipboard is shared while its window has focus; ~/Downloads is shared
#    both ways (treat what lands there as untrusted).
#  - Links from other programs open in the Firefox that is already running.
#  - Sound goes through a pipe into a player of yours; it never gets your audio
#    server, so it cannot hear your microphone.
#  - A firewall rule on that user keeps it off your router, printers and this
#    computer's own services (data/firefox-firewall.nft); how to lift it for a
#    while is in that file. DNS stays open.
#  - Your user may run exactly one thing as firefox (a rule in /etc/sudoers.d).
#  - It becomes your default browser, so links from other programs (a terminal,
#    a file manager...) open in it, not in firefox-esr. firefox-esr is the same
#    Firefox run as you, with everything you can reach, and stays installed.
#  - Firefox profiles made with firefox-profiles/new-profile.sh each get a user
#    of their own like this one (fx-NAME).
# There is no KeePassXC browser add-on (debsway's KeePassXC is the minimal
# build without it): copy and paste a password; the clipboard is shared.
# Usage: bash firefox-sandbox.sh [--remove]
# summary: Firefox as its own locked-down user
# status: file:/usr/local/bin/firefox
# files: bin/no-abstract-sockets bin/wayland-restrict data/firefox-firewall.nft data/firefox-user.js data/debsway-firefox.desktop lib/firefox-sandbox.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
. "$DEBSWAY_DIR/lib/firefox-sandbox.sh"
need_user

NAME=firefox
HOME_DIR=/var/lib/debsway-firefox
CMD=/usr/local/bin/firefox
SESSION=/usr/local/libexec/firefox-session
SHARE=/usr/local/share/debsway
PREFS=$SHARE/firefox-user.js
LIMITS=/etc/security/limits.d/50-debsway-firefox.conf
FIREWALL=/etc/debsway/firefox.nft
UNIT=/etc/systemd/system/debsway-firefox-firewall.service
DESKTOP="$HOME/.local/share/applications/debsway-firefox.desktop"

if [ "${1:-}" = --remove ]; then
    sudo systemctl disable --now debsway-firefox-firewall.service >/dev/null 2>&1 || true
    sudo nft delete table inet debsway_firefox 2>/dev/null || true
    [ -f "$BIN/media-sandbox" ] || [ -x /usr/local/bin/incognito ] || remove_bin wayland-restrict
    fx_disallow_session "$NAME"
    sudo rm -f "$LIMITS" "$CMD" "$SESSION" "$PREFS" "$FIREWALL" "$UNIT"
    remove_no_abstract
    sudo systemctl daemon-reload >/dev/null 2>&1 || true
    sudo rmdir "$SHARE" /usr/local/libexec /etc/debsway 2>/dev/null || true
    sudo rm -rf /dev/shm/firefox-run
    # links open in firefox-esr again
    unset_default_app debsway-firefox.desktop
    rm -f "$DESKTOP"
    mapfile -t profiles < <(fx_profile_names)
    if [ ${#profiles[@]} -gt 0 ]; then
        warn "These Firefox profiles still have users of their own: ${profiles[*]}"
        warn "Remove each with: bash extras/firefox-profiles/new-profile.sh --remove NAME"
    fi
    if id "$NAME" >/dev/null 2>&1; then
        sudo pkill -KILL -u "$NAME" 2>/dev/null || true
        sudo userdel "$NAME"
        note "Removed the user $NAME."
    fi
    if [ -d "$HOME_DIR" ]; then
        note "Its profile (logins, history, bookmarks) is still in $HOME_DIR."
        if ask "Delete that profile too?" n; then sudo rm -rf "$HOME_DIR"; fi
    fi
    # Firefox itself stays: it is the Firefox extra's
    exit
fi

say "Firefox and what it needs"
# acl: gives the firefox user the socket and ~/Downloads, and takes them away again
# pipewire-bin, wireplumber, pipewire-pulse: its own audio server; pw-cat (in
# pipewire-bin) is the player that reads its pipe. dbus-daemon: the private bus
# that carries links to the running Firefox. nftables: the firewall rule.
apt_install firefox-esr libavcodec61 webext-ublock-origin-firefox acl nftables python3 dbus-daemon \
    pipewire-bin pipewire-pulse wireplumber
bash "$DEBSWAY_DIR/parts/firefox-hardening.sh"

say "The $NAME user"
# No password to guess, no login shell, a home only it can enter; in the group
# debsway-fx that the firewall rule matches (profiles with a user of their own are too)
fx_create_user "$NAME" "$HOME_DIR" "debsway sandboxed Firefox"
note "$NAME: no password, no login, group $FX_GROUP (and render); home $HOME_DIR."

say "The firefox command"
sudo install -d -o root -g root -m 0755 "$SHARE" /usr/local/libexec
install_bin wayland-restrict
install_no_abstract
sudo install -o root -g root -m 0755 "$DEBSWAY_DIR/bin/firefox" "$CMD"
sudo install -o root -g root -m 0755 "$DEBSWAY_DIR/bin/firefox-session" "$SESSION"
sudo install -o root -g root -m 0644 "$DEBSWAY_DIR/data/firefox-user.js" "$PREFS"

say "What your user may run as $NAME"
fx_allow_session "$NAME"
note "Wrote /etc/sudoers.d/debsway-$NAME"

# A limit on processes keeps a runaway page from filling the machine; for every
# user in the group (a profile with a user of its own too)
printf '# Written by debsway extras/firefox-sandbox.sh\n@%s hard nproc 4096\n@%s hard core 0\n' "$FX_GROUP" "$FX_GROUP" |
    sudo tee "$LIMITS" >/dev/null

say "Keeping $NAME off your network"
sudo install -d -o root -g root -m 0755 "${FIREWALL%/*}"
sudo install -o root -g root -m 0644 "$DEBSWAY_DIR/data/firefox-firewall.nft" "$FIREWALL"
# Loaded before the network comes up, at every boot
printf '%s\n' '# Written by debsway extras/firefox-sandbox.sh' '[Unit]' \
    'Description=Keep the firefox user off the local network (debsway)' \
    'Before=network-pre.target' 'Wants=network-pre.target' '' '[Service]' \
    'Type=oneshot' 'RemainAfterExit=yes' \
    "ExecStart=/usr/sbin/nft -f $FIREWALL" \
    'ExecStop=/usr/sbin/nft delete table inet debsway_firefox' '' '[Install]' \
    'WantedBy=multi-user.target' | sudo tee "$UNIT" >/dev/null
sudo systemctl daemon-reload
# Restart, not just enable --now: a changed rule file is only loaded by a restart
sudo systemctl enable debsway-firefox-firewall.service >/dev/null &&
    sudo systemctl restart debsway-firefox-firewall.service ||
    warn "Couldn't load the firewall rule; check: systemctl status debsway-firefox-firewall"

say "Default browser"
# Links from other programs go to xdg-open, which asks this list. Only your user's
# settings change; firefox-esr stays installed and can still be started by name.
install -D -m 0644 "$DEBSWAY_DIR/data/debsway-firefox.desktop" "$DESKTOP"
set_default_app debsway-firefox.desktop x-scheme-handler/http x-scheme-handler/https
note "Links from other programs now open in the sandboxed Firefox."

note "Run it with: firefox   (or Super+d). firefox-esr runs Firefox as you instead."
note "It cannot reach your router or local services; to allow that for a while:"
note "  sudo systemctl stop debsway-firefox-firewall"
note "Downloads go to ~/Downloads, shared with you. Copy and paste works while its window has focus."
