#!/bin/bash
# BitTorrent, from the terminal: Debian's Transmission running in the
# background as its own locked-down user (debian-transmission), and a
# "torrent" command to add, list, copy out and remove downloads.
#  - Debian's service is already hardened (no capabilities, no new privileges,
#    private /tmp and devices, a system-call filter...); a drop-in adds: it
#    can't see /home at all, may write only its own folders, keeps its files
#    private and leaves no memory dumps.
#  - Its remote control listens on this computer only, with a password of its
#    own (made here, kept in ~/.config/debsway/torrent-rpc, readable by you
#    only), not Debian's default "transmission".
#  - It opens no ports on your router (UPnP and NAT-PMP off) and doesn't look
#    for peers on your local network. debsway's firewall (ufw) keeps incoming
#    connections out, so it only connects out: slower for some torrents, and
#    nothing on the internet can start a conversation with it.
#  - A firewall rule keeps it off your router, printers and this computer's
#    own services (data/torrent-firewall.nft). DNS stays open.
#  - Finished downloads are in /var/lib/debsway-torrent/downloads, which you
#    can read but not change; torrent get copies them into ~/Downloads.
#  - With the Mullvad VPN app on, it goes through the VPN like everything
#    else; with Mullvad's lockdown mode it stops while the VPN is off.
# Everyone sharing a torrent sees your IP address (a VPN hides it; Tor
# doesn't, and asks not to be used for BitTorrent).
# Usage: bash torrent.sh [--remove]
# summary: BitTorrent (Transmission) as its own locked user
# status: file:/etc/systemd/system/transmission-daemon.service.d/50-debsway.conf
# files: bin/torrent data/torrent-settings.py data/torrent-firewall.nft
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
need_user

NAME=debian-transmission
SETTINGS=/etc/transmission-daemon/settings.json
DIR=/var/lib/debsway-torrent
DL=$DIR/downloads
PARTIAL=$DIR/incomplete
DROPIN=/etc/systemd/system/transmission-daemon.service.d/50-debsway.conf
AUTH_FILE=${XDG_CONFIG_HOME:-$HOME/.config}/debsway/torrent-rpc
FIREWALL=/etc/debsway/torrent.nft
UNIT=/etc/systemd/system/debsway-torrent-firewall.service

if [ "${1:-}" = --remove ]; then
    sudo systemctl disable --now transmission-daemon.service >/dev/null 2>&1 || true
    sudo systemctl disable --now debsway-torrent-firewall.service >/dev/null 2>&1 || true
    sudo nft delete table inet debsway_torrent 2>/dev/null || true
    sudo rm -f "$DROPIN" "$FIREWALL" "$UNIT"
    sudo rmdir "${DROPIN%/*}" /etc/debsway 2>/dev/null || true
    sudo systemctl daemon-reload >/dev/null 2>&1 || true
    remove_bin torrent
    rm -f "$AUTH_FILE"
    # Transmission and its settings (apt purge takes /etc/transmission-daemon)
    apt_purge
    if [ -d "$DIR" ]; then
        if [ -n "$(sudo find "$DIR" -mindepth 2 -print -quit 2>/dev/null)" ]; then
            note "Downloads are still in $DL (copies you made with torrent get are in ~/Downloads)."
            if ask "Delete $DIR and everything in it?" n; then sudo rm -rf "$DIR"; fi
        else
            sudo rm -rf "$DIR"
        fi
    fi
    exit
fi

say "Transmission"
had=false
is_installed transmission-daemon && had=true
# transmission-remote is in transmission-cli; python3 edits the settings
apt_install transmission-daemon transmission-cli python3 nftables
$had && ! [ -f "$DROPIN" ] &&
    warn "Transmission was installed already; its settings are changed to debsway's below."
# Debian starts it with its defaults on install; it is set up while stopped
# (it writes its settings back when it stops)
sudo systemctl stop transmission-daemon.service
id "$NAME" >/dev/null 2>&1 || die "Debian's package didn't make the user $NAME. Nothing more was changed."

say "Its folders"
# Finished downloads: the daemon writes, your group (only you) reads, nobody
# else gets in. The setgid bit gives what it makes there your group; the
# daemon makes its folders with a plain mkdir, which keeps it.
sudo install -d -o "$NAME" -g "$(id -gn)" -m 0750 "$DIR"
sudo install -d -o "$NAME" -g "$(id -gn)" -m 2750 "$DL"
# Unfinished ones, the same way: a finished file is renamed from here into
# $DL, and a rename keeps the file's group, so it must be yours from the start
sudo install -d -o "$NAME" -g "$(id -gn)" -m 2750 "$PARTIAL"
note "Finished downloads: $DL (you can read them; torrent get copies them out)."

say "Its settings"
mkdir -p "${AUTH_FILE%/*}"
if [ ! -s "$AUTH_FILE" ]; then
    # A new password: random, for the remote control only
    (umask 077 && printf 'debsway:%s\n' "$(od -An -N24 -tx1 /dev/urandom | tr -d ' \n')" >"$AUTH_FILE")
fi
chmod 600 "$AUTH_FILE"
# The password goes in on standard input, never on a command line
cut -d: -f2- "$AUTH_FILE" | sudo python3 -I "$DEBSWAY_DIR/data/torrent-settings.py" "$SETTINGS" "$DL" "$PARTIAL" ||
    die "Couldn't change $SETTINGS. Transmission is left stopped."
note "Remote control: this computer only, with a password of its own ($AUTH_FILE)."
note "No ports opened on your router, no looking for peers on your local network."

say "More locks on the service"
sudo install -d -o root -g root -m 0755 "${DROPIN%/*}"
printf '%s\n' '# Written by debsway extras/torrent.sh: more than Debian'"'"'s own hardening' '[Service]' \
    '# /home, /root and /run/user are invisible; the rest of the system is' \
    '# read-only but for its own folders' \
    'ProtectHome=true' 'ProtectSystem=strict' \
    "ReadWritePaths=/var/lib/transmission-daemon /etc/transmission-daemon $DIR" \
    'UMask=0027' 'LimitCORE=0' 'TasksMax=256' | sudo tee "$DROPIN" >/dev/null

say "Keeping it off your network"
sudo install -d -o root -g root -m 0755 "${FIREWALL%/*}"
sudo install -o root -g root -m 0644 "$DEBSWAY_DIR/data/torrent-firewall.nft" "$FIREWALL"
# Loaded before the network comes up, at every boot
printf '%s\n' '# Written by debsway extras/torrent.sh' '[Unit]' \
    'Description=Keep Transmission off the local network (debsway)' \
    'Before=network-pre.target transmission-daemon.service' 'Wants=network-pre.target' '' '[Service]' \
    'Type=oneshot' 'RemainAfterExit=yes' \
    "ExecStart=/usr/sbin/nft -f $FIREWALL" \
    'ExecStop=/usr/sbin/nft delete table inet debsway_torrent' '' '[Install]' \
    'WantedBy=multi-user.target' | sudo tee "$UNIT" >/dev/null
sudo systemctl daemon-reload
# Restart, not just enable --now: a changed rule file is only loaded by a restart
if sudo systemctl enable debsway-torrent-firewall.service >/dev/null &&
    sudo systemctl restart debsway-torrent-firewall.service; then
    sudo systemctl enable transmission-daemon.service >/dev/null
    sudo systemctl start transmission-daemon.service ||
        warn "Transmission didn't start; see: systemctl status transmission-daemon"
else
    warn "Couldn't load the firewall rule, so Transmission is left stopped. See: systemctl status debsway-torrent-firewall"
fi

say "The torrent command"
install_bin torrent
note "torrent add MAGNET-LINK   then   torrent   (what is downloading)"
note "torrent get N copies a finished one into ~/Downloads; torrent remove N removes it."
note "Everyone sharing a torrent sees your IP address. Never run programs from a torrent;"
note "play videos with mpv from the media extra (it runs in a sandbox)."
