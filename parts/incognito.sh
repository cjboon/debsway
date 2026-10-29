#!/bin/bash
# A throwaway, locked-down Firefox for sites you don't trust or don't want
# tied to you. It adds a user called incognito and a command, incognito,
# that opens Firefox as that user:
#  - incognito has no password, no login, no home folder on disk and no
#    group but render (no sound card, no microphone, no USB; render lets cage
#    open the graphics card's render node, which wlroots' Wayland backend
#    needs, but not take over the screen); a limit on processes keeps a
#    runaway page from filling the machine.
#  - Firefox runs inside cage, a tiny Wayland compositor shown as one window
#    in your sway. cage is a separate window system, so the clipboard is
#    not shared with your programs, and incognito can't read your files, so
#    no folder is either (a download stays in memory and vanishes).
#  - It talks to your sway through a restricted socket (bin/wayland-restrict,
#    sway's security-context protocol), not your real one, so it can't read
#    your screen or type for you.
#  - Its profile, cache and cookies live in memory (/dev/shm) and are
#    deleted when the window closes. The profile is always in private
#    browsing, with tracking and fingerprinting protection on.
#  - Sound and video work. incognito runs its own small audio server with
#    no sound card; its only output is a pipe into a player running as you,
#    which plays it through your speakers like any other program. It never
#    reaches your audio server, so it can't hear your microphone or your
#    other programs. Video is decoded by the CPU (software rendering),
#    so 720p is comfortable and 1080p may stutter. incognito --no-audio
#    leaves the pipe out.
#  - A firewall rule that matches only that user keeps it off your computer
#    and local network: a hacked page can reach the internet, but not your
#    router, printers, other computers, or programs of yours listening on
#    this machine (DNS stays open). It is loaded at every boot.
#  - Your user may run exactly one thing as incognito: the wrapper that
#    starts this (a rule in /etc/sudoers.d). While it runs, incognito can
#    reach your sway's socket and nothing else of yours.
# It is still your network and your IP address: use Tor Browser or a VPN
# for that. See THREAT-MODEL.md.
# Usage: bash incognito.sh [--remove]
# status: file:/usr/local/bin/incognito
# files: bin/no-abstract-sockets
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
need_user

NAME=incognito
CMD=/usr/local/bin/incognito
SESSION=/usr/local/libexec/incognito-session
SHARE=/usr/local/share/debsway
PREFS=$SHARE/incognito-user.js
SUDOERS=/etc/sudoers.d/debsway-incognito
LIMITS=/etc/security/limits.d/50-debsway-incognito.conf
FIREWALL=/etc/debsway/incognito.nft
UNIT=/etc/systemd/system/debsway-incognito-firewall.service

if [ "${1:-}" = --remove ]; then
    sudo systemctl disable --now debsway-incognito-firewall.service >/dev/null 2>&1 || true
    sudo nft delete table inet debsway_incognito 2>/dev/null || true
    # the media sandbox needs it too
    [ -f "$BIN/media-sandbox" ] || remove_bin wayland-restrict
    sudo rm -f "$SUDOERS" "$LIMITS" "$CMD" "$SESSION" "$PREFS" "$FIREWALL" "$UNIT"
    remove_no_abstract
    sudo systemctl daemon-reload >/dev/null 2>&1 || true
    sudo rmdir "$SHARE" /usr/local/libexec /etc/debsway 2>/dev/null || true
    if id "$NAME" >/dev/null 2>&1; then
        sudo pkill -KILL -u "$NAME" 2>/dev/null || true
        sudo userdel "$NAME"
        note "Removed the user $NAME."
    fi
    sudo rm -rf /dev/shm/incognito.*
    # cage goes too, unless another script needs it
    apt_purge
    exit
fi

say "Installing cage and acl"
# acl: lets the incognito command give the user access to its Wayland socket
# and take it away again; python3: runs wayland-restrict
# pipewire-bin, wireplumber, pipewire-pulse: incognito's own audio server;
# pw-cat (in pipewire-bin) is the player that reads its pipe
# nftables: the rule that keeps the user off your local network
apt_install cage acl firefox-esr libavcodec61 pipewire-bin pipewire-pulse wireplumber nftables python3

say "The $NAME user"
if id "$NAME" >/dev/null 2>&1; then
    [ "$(id -u "$NAME")" -lt 1000 ] ||
        die "A regular user account called $NAME already exists; this needs a system user. Rename or remove it first."
else
    sudo useradd --system --user-group --no-create-home --home-dir /nonexistent \
        --shell /usr/sbin/nologin --comment "debsway incognito Firefox" "$NAME"
fi
# No password to guess, and no shell to log in with
sudo usermod --lock --shell /usr/sbin/nologin "$NAME"
# cage's Wayland backend (wlroots 0.18) opens the GPU's render node even with the
# software renderer, and fails to start without it. render, not video: no modesetting.
if getent group render >/dev/null; then
    sudo usermod -aG render "$NAME"
fi
note "$NAME: no password, no login, no home folder, no groups but its own and render (cage needs the GPU's render node)."

say "The incognito command"
sudo install -d -o root -g root -m 0755 "$SHARE" /usr/local/libexec
install_bin wayland-restrict
install_no_abstract
sudo install -o root -g root -m 0755 "$DEBSWAY_DIR/bin/incognito" "$CMD"
sudo install -o root -g root -m 0755 "$DEBSWAY_DIR/bin/incognito-session" "$SESSION"
sudo install -o root -g root -m 0644 "$DEBSWAY_DIR/data/incognito-user.js" "$PREFS"

say "What your user may run as $NAME"
rule=$(mktemp)
printf '# Written by debsway parts/incognito.sh. %s may run the incognito wrapper,\n# and nothing else, as the user incognito.\n%s ALL=(%s) NOPASSWD: %s\n' \
    "$(id -un)" "$(id -un)" "$NAME" "$SESSION" >"$rule"
# A broken sudoers file locks you out of sudo, so it is checked first
if ! sudo visudo -cf "$rule" >/dev/null; then
    rm -f "$rule"
    die "The sudoers rule didn't pass visudo's check, so it wasn't installed."
fi
sudo install -o root -g root -m 0440 "$rule" "$SUDOERS"
rm -f "$rule"
note "Wrote $SUDOERS"

printf '# Written by debsway parts/incognito.sh\n%s hard nproc 4096\n%s hard core 0\n' "$NAME" "$NAME" |
    sudo tee "$LIMITS" >/dev/null

say "Keeping $NAME off your network"
sudo install -d -o root -g root -m 0755 "${FIREWALL%/*}"
sudo install -o root -g root -m 0644 "$DEBSWAY_DIR/data/incognito-firewall.nft" "$FIREWALL"
# Loaded before the network comes up, at every boot
printf '%s\n' '# Written by debsway parts/incognito.sh' '[Unit]' \
    'Description=Keep the incognito user off the local network (debsway)' \
    'Before=network-pre.target' 'Wants=network-pre.target' '' '[Service]' \
    'Type=oneshot' 'RemainAfterExit=yes' \
    "ExecStart=/usr/sbin/nft -f $FIREWALL" \
    'ExecStop=/usr/sbin/nft delete table inet debsway_incognito' '' '[Install]' \
    'WantedBy=multi-user.target' | sudo tee "$UNIT" >/dev/null
sudo systemctl daemon-reload
# Restart, not just enable --now: the unit stays "active" after it first ran,
# so a rule file changed by an update would otherwise not be loaded
sudo systemctl enable debsway-incognito-firewall.service >/dev/null &&
    sudo systemctl restart debsway-incognito-firewall.service ||
    warn "Couldn't load the firewall rule; check: systemctl status debsway-incognito-firewall"
note "$NAME can reach the internet, not your router, printers or your own local services."
note "(Wi-Fi login pages at cafes are on the local network: sign in with your own Firefox first.)"

note "Run it with: incognito   (or Super+d); incognito https://example.org/ opens a page."
note "Videos play with sound (software decoding); incognito --no-audio keeps it silent."
note "Nothing is kept when you close it: no bookmarks, logins, cookies or downloads."
