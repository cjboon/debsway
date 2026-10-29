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
#  - firefox-esr is the same Firefox run as you, with everything you can reach.
# There is no KeePassXC browser add-on (debsway's KeePassXC is the minimal
# build without it): copy and paste a password; the clipboard is shared.
# Usage: bash firefox-sandbox.sh [--remove]
# summary: Firefox as its own locked-down user
# status: file:/usr/local/bin/firefox
# files: bin/no-abstract-sockets bin/wayland-restrict data/firefox-firewall.nft data/firefox-user.js
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
need_user

NAME=firefox
HOME_DIR=/var/lib/debsway-firefox
CMD=/usr/local/bin/firefox
SESSION=/usr/local/libexec/firefox-session
SHARE=/usr/local/share/debsway
PREFS=$SHARE/firefox-user.js
SUDOERS=/etc/sudoers.d/debsway-firefox
LIMITS=/etc/security/limits.d/50-debsway-firefox.conf
FIREWALL=/etc/debsway/firefox.nft
UNIT=/etc/systemd/system/debsway-firefox-firewall.service

if [ "${1:-}" = --remove ]; then
    sudo systemctl disable --now debsway-firefox-firewall.service >/dev/null 2>&1 || true
    sudo nft delete table inet debsway_firefox 2>/dev/null || true
    [ -f "$BIN/media-sandbox" ] || [ -x /usr/local/bin/incognito ] || remove_bin wayland-restrict
    sudo rm -f "$SUDOERS" "$LIMITS" "$CMD" "$SESSION" "$PREFS" "$FIREWALL" "$UNIT"
    remove_no_abstract
    sudo systemctl daemon-reload >/dev/null 2>&1 || true
    sudo rmdir "$SHARE" /usr/local/libexec /etc/debsway 2>/dev/null || true
    sudo rm -rf /dev/shm/firefox-run
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
if id "$NAME" >/dev/null 2>&1; then
    [ "$(id -u "$NAME")" -lt 1000 ] ||
        die "A regular user account called $NAME already exists; this needs a system user. Rename or remove it first."
else
    sudo useradd --system --user-group --create-home --home-dir "$HOME_DIR" \
        --shell /usr/sbin/nologin --comment "debsway sandboxed Firefox" "$NAME"
fi
# No password to guess, and no shell to log in with; its home is for it alone
sudo usermod --lock --shell /usr/sbin/nologin "$NAME"
sudo chmod 0700 "$HOME_DIR"
# Firefox opens the GPU's render node (software rendering is forced; this is
# only so it can start). render, not video: no modesetting.
if getent group render >/dev/null; then
    sudo usermod -aG render "$NAME"
fi
note "$NAME: no password, no login, no groups but its own and render; home $HOME_DIR."

say "The firefox command"
sudo install -d -o root -g root -m 0755 "$SHARE" /usr/local/libexec
install_bin wayland-restrict
install_no_abstract
sudo install -o root -g root -m 0755 "$DEBSWAY_DIR/bin/firefox" "$CMD"
sudo install -o root -g root -m 0755 "$DEBSWAY_DIR/bin/firefox-session" "$SESSION"
sudo install -o root -g root -m 0644 "$DEBSWAY_DIR/data/firefox-user.js" "$PREFS"

say "What your user may run as $NAME"
rule=$(mktemp)
printf '# Written by debsway extras/firefox-sandbox.sh. %s may run the firefox wrapper,\n# and nothing else, as the user firefox.\n%s ALL=(%s) NOPASSWD: %s\n' \
    "$(id -un)" "$(id -un)" "$NAME" "$SESSION" >"$rule"
# A broken sudoers file locks you out of sudo, so it is checked first
if ! sudo visudo -cf "$rule" >/dev/null; then
    rm -f "$rule"
    die "The sudoers rule didn't pass visudo's check, so it wasn't installed."
fi
sudo install -o root -g root -m 0440 "$rule" "$SUDOERS"
rm -f "$rule"
note "Wrote $SUDOERS"

printf '# Written by debsway extras/firefox-sandbox.sh\n%s hard nproc 4096\n%s hard core 0\n' "$NAME" "$NAME" |
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

note "Run it with: firefox   (or Super+d). firefox-esr runs Firefox as you instead."
note "It cannot reach your router or local services; to allow that for a while:"
note "  sudo systemctl stop debsway-firefox-firewall"
note "Downloads go to ~/Downloads, shared with you. Copy and paste works while its window has focus."
