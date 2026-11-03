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
#  - It asks five things (remembered, in /etc/debsway/firefox.conf, which only
#    root can write; asked again when you run this again in a terminal):
#    fast JavaScript (the JIT; default no: it is where many browser attacks
#    happen), sound (default yes), whether it is your default browser, so
#    links from other programs open in it (default yes), uBlock Origin's
#    mode: medium (default: other sites' scripts blocked, ublock-allow lets a
#    site through) or standard (ads, trackers and malware only), and, for
#    when the secure DNS extra isn't installed, Firefox's own encrypted DNS
#    to Quad9: strict (default) or with fallback to the network's. firefox-esr is the
#    same Firefox run as you, with everything you can reach, and stays
#    installed. No video calls: it has no microphone or camera, so WebRTC is off.
#  - Firefox profiles made with firefox-profiles/new-profile.sh each get a user
#    of their own like this one (fx-NAME).
#  - It sets up Firefox ESR the debsway way for every profile (video codecs,
#    uBlock Origin, HTTPS-Only Mode, the JavaScript JIT off, a restart notice:
#    parts/firefox-hardening.sh), and sets up incognito too, a throwaway Firefox
#    in a locked-down user of its own with nothing kept (parts/incognito.sh).
# There is no KeePassXC browser add-on (debsway's KeePassXC is the minimal
# build without it): copy and paste a password; the clipboard is shared.
# Usage: bash firefox-sandbox.sh [--remove | --manual]
# summary: Firefox as its own locked-down user
# security: most
# status: file:/usr/local/bin/firefox
# files: bin/no-abstract-sockets bin/wayland-restrict data/firefox-firewall.nft data/firefox-user.js data/debsway-firefox.desktop lib/firefox-sandbox.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
. "$DEBSWAY_DIR/lib/firefox-sandbox.sh"
# The hardening and incognito it sets up first, then the sandbox itself
if [ "${1:-}" = --manual ]; then print_manual firefox; print_manual; exit; fi
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
    fx_sandbox_unused
    # incognito first: whether it stays decides what else may go
    keep_incognito=false
    if [ -x /usr/local/bin/incognito ]; then
        if ask "Remove incognito (the throwaway Firefox) too?" y; then
            bash "$DEBSWAY_DIR/parts/incognito.sh" --remove
        else
            keep_incognito=true
        fi
    fi
    sudo systemctl disable --now debsway-firefox-firewall.service >/dev/null 2>&1 || true
    sudo nft delete table inet debsway_firefox 2>/dev/null || true
    [ -f "$BIN/media-sandbox" ] || [ -x /usr/local/bin/incognito ] || remove_bin wayland-restrict
    fx_disallow_session "$NAME"
    sudo rm -f /etc/debsway/firefox.conf
    sudo rm -f "$LIMITS" "$CMD" "$SESSION" "$PREFS" "$FIREWALL" "$UNIT"
    remove_no_abstract
    sudo systemctl daemon-reload >/dev/null 2>&1 || true
    sudo rmdir "$SHARE" /usr/local/libexec /etc/debsway 2>/dev/null || true
    sudo rm -rf /dev/shm/firefox-run
    # links open in firefox-esr again
    unset_default_app debsway-firefox.desktop
    rm -f "$DESKTOP"
    if id "$NAME" >/dev/null 2>&1; then
        sudo pkill -KILL -u "$NAME" 2>/dev/null || true
        sudo userdel "$NAME"
        note "Removed the user $NAME."
    fi
    # The group the firewall rule matched; no user is left in it now
    if getent group "$FX_GROUP" >/dev/null; then sudo groupdel "$FX_GROUP" 2>/dev/null || true; fi
    if [ -d "$HOME_DIR" ]; then
        note "Its profile (logins, history, bookmarks) is still in $HOME_DIR."
        if ask "Delete that profile too?" n; then sudo rm -rf "$HOME_DIR"; fi
    fi
    # Firefox itself and its hardening, unless incognito still uses them
    if $keep_incognito; then
        note "incognito stays, and with it Firefox ESR and its hardening."
    else
        bash "$DEBSWAY_DIR/parts/firefox-hardening.sh" --remove
    fi
    apt_purge
    note "Your own Firefox profiles (firefox-esr's bookmarks, logins) stay in ~/.mozilla."
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
# debsway once had a separate extra for Firefox run as you (extras/firefox.sh);
# this one installs it now. Its marker package goes: what it held, this
# script's marker holds now, so nothing is removed.
if is_installed debsway-firefox; then
    DEBSWAY_OWNER=firefox apt_purge >/dev/null
    note "Took over Firefox ESR from debsway's old Firefox extra."
fi

say "Your choices (asked again whenever you run this in a terminal)"
CHOICES=/etc/debsway/firefox.conf
chosen() { sed -n "s/^$1=//p" "$CHOICES" 2>/dev/null | head -1; }
# last time's answers are the defaults (with no terminal to ask on: kept)
fast=n sound=y links=y ublock=medium dns=strict
[ "$(chosen fast_js)" != yes ] || fast=y
[ "$(chosen ublock)" != standard ] || ublock=standard
[ "$(chosen dns)" != fallback ] || dns=fallback
[ "$(chosen sound)" != no ] || sound=n
[ "$(chosen default_browser)" != no ] || links=n
note "Fast JavaScript makes heavy sites quicker, but the part that does it (the JIT)"
note "is where many browser attacks happen; off, sites still work, just slower."
if ask "Turn on fast JavaScript?" "$fast"; then fast=yes; else fast=no; fi
if ask "Sound in Firefox (videos, music)? It can't hear your microphone either way." "$sound"; then sound=yes; else sound=no; fi
if ask "Open links from other programs in it (your default browser)?" "$links"; then links=yes; else links=no; fi
note "uBlock Origin blocks ads in every Firefox here. It can work two ways:"
note "  medium    blocks ads, trackers and known malware sites, and also the"
note "            scripts and frames a site loads from other sites, which is where"
note "            most malicious ads come from. Safer, but many sites break until"
note "            you allow them, one by one: ublock-allow example.com (then"
note "            restart Firefox). debsway's default."
note "  standard  blocks ads, trackers and known malware sites; the rest of a site"
note "            runs, so sites work as you expect. Easier for people who'd"
note "            rather not allow sites."
choose ublock "Which way should uBlock Origin work?" "$ublock" medium standard
note "Without the secure DNS extra (which encrypts every program's lookups), Firefox"
note "encrypts its own, to Quad9, so your network can't see which sites you look up:"
note "  strict    always; on Wi-Fi with a sign-in page (cafés, hotels) that page"
note "            won't load in Firefox, and on a network that blocks encrypted DNS"
note "            nothing does. debsway's default."
note "  fallback  if encrypted DNS fails, the network's own, unencrypted: sign-in"
note "            pages work, but such a network can see those lookups."
note "With the secure DNS extra installed, Firefox uses the system's (encrypted) DNS."
choose dns "Firefox's own encrypted DNS?" "$dns" strict fallback
sudo install -d -o root -g root -m 0755 "${CHOICES%/*}"
printf '%s\n' '# Written by debsway extras/firefox-sandbox.sh: run it again to change these' \
    "fast_js=$fast" "sound=$sound" "default_browser=$links" "ublock=$ublock" "dns=$dns" | sudo tee "$CHOICES" >/dev/null
sudo chmod 0644 "$CHOICES"
note "Fast JavaScript: $fast. Sound: $sound. Default browser: $links. uBlock: $ublock mode. DNS: $dns."
# uBlock's mode and Firefox's DNS, for every Firefox profile (ublock-allow came
# with the hardening above; it reads the DNS choice from $CHOICES)
sudo /usr/local/bin/ublock-allow --mode "$ublock" >/dev/null || warn "Couldn't set uBlock's $ublock mode: ublock-allow --mode $ublock"

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
if [ "$links" = yes ]; then
    set_default_app debsway-firefox.desktop x-scheme-handler/http x-scheme-handler/https
    note "Links from other programs now open in the sandboxed Firefox."
else
    unset_default_app debsway-firefox.desktop
    note "Links from other programs open as before (not in the sandboxed Firefox)."
fi

say "incognito"
note "incognito opens a throwaway Firefox as a separate, locked-down user, with"
note "its own clipboard, no shared folders, sound and video, and nothing kept."
bash "$DEBSWAY_DIR/parts/incognito.sh" ||
    warn "incognito didn't finish setting up; run it again with: bash ~/debsway/parts/incognito.sh"

note "Run it with: firefox   (or Super+d). firefox-esr runs Firefox as you instead."
note "It cannot reach your router or local services; to allow that for a while:"
note "  sudo systemctl stop debsway-firefox-firewall"
note "Downloads go to ~/Downloads, shared with you. Copy and paste works while its window has focus."
