#!/bin/bash
# Download Debian's packages through Tor, over https, so your network
# doesn't see which packages you get (or when), and Debian's mirrors don't
# see your address. It first asks whether you need a bridge to reach Tor
# (obfs4 with lines you paste, or Snowflake; Debian has no client for
# webtunnel or meek), installs tor, apt-transport-tor and the bridge
# program that kind needs, checks that Tor connects, and only then points
# apt's Debian sources at
# tor+https://deb.debian.org and tor+https://security.debian.org. If Tor
# doesn't connect, nothing is changed.
# Packages are still checked by apt's signatures, as always; this changes who
# can see the download. It is slower, and other apt repositories you added
# (Mullvad, Claude Code) are still fetched directly.
# install-base.sh offers it first, answering no by default.
# Usage: bash apt-tor.sh [--remove]
# status: file:/etc/tor/.debsway-apt-tor
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
need_user

MARK=/etc/tor/.debsway-apt-tor
TORRC=/etc/tor/torrc
BEGIN='# >>> debsway apt-tor >>>'
END='# <<< debsway apt-tor <<<'
BAK_SUFFIX=.debsway-tor.bak

# The files that name Debian's mirrors: classic lines and deb822 stanzas
source_files() {
    { [ -f /etc/apt/sources.list ] && echo /etc/apt/sources.list
      grep -ls 'debian\.org' /etc/apt/sources.list.d/*.sources /etc/apt/sources.list.d/*.list 2>/dev/null
    } || true
}

use_tor_sources() {
    local f
    for f in $(source_files); do
        grep -qE 'https?://(deb|security)\.debian\.org' "$f" || continue
        [ -e "$f$BAK_SUFFIX" ] || sudo cp -a "$f" "$f$BAK_SUFFIX"
        sudo sed -i -E 's#https?://(deb|security)\.debian\.org#tor+https://\1.debian.org#g' "$f"
        note "Now through Tor: $f"
    done
}

restore_sources() {
    local f
    for f in $(source_files) /etc/apt/sources.list.d/*.sources /etc/apt/sources.list.d/*.list; do
        [ -e "$f$BAK_SUFFIX" ] || continue
        sudo mv "$f$BAK_SUFFIX" "$f"
        note "Restored $f"
    done
}

if [ "${1:-}" = --remove ]; then
    restore_sources
    sudo apt-get update || warn "apt couldn't update with the restored sources; check /etc/apt/sources.list*"
    sudo sed -i "\\|^$BEGIN\$|,\\|^$END\$|d" "$TORRC" 2>/dev/null || true
    # another script (remote access) may still use the same tor service
    if system_tor_wanted .debsway-apt-tor; then
        sudo systemctl restart tor@default.service >/dev/null 2>&1 || true
    else
        sudo systemctl disable --now tor@default.service >/dev/null 2>&1 || true
    fi
    sudo rm -f "$MARK"
    apt_purge tor obfs4proxy snowflake-client apt-transport-tor
    # OnionShare keeps the system tor service off, unless something still needs it
    if is_installed onionshare-cli && ! system_tor_wanted .debsway-apt-tor; then
        sudo systemctl mask tor.service tor@default.service >/dev/null
    fi
    note "apt downloads directly again."
    exit
fi

say "apt through Tor"
# Asked first, before anything is installed
say "Bridges"
pick_bridges system-tor
if $BRIDGE_WANTED && [ "$BRIDGE_TYPE" = none ]; then
    warn "You said you need a bridge, but none was set up: Tor would connect to the Tor"
    warn "network directly, and your network could see that you use Tor."
    ask "Go on without a bridge?" n || die "Stopped before changing anything. Run this again with a bridge."
elif [ "$BRIDGE_TYPE" = none ]; then
    note "No bridge: Tor connects directly (your network can see that you use Tor)."
fi

# Debian starts tor the moment it is installed, and it would connect without
# your bridge. Mask it until the bridge is in place.
sudo systemctl mask tor.service tor@default.service >/dev/null
pkgs=(tor apt-transport-tor)
case $BRIDGE_TYPE in
    obfs4) pkgs+=(obfs4proxy) ;;
    snowflake) pkgs+=(snowflake-client) ;;
esac
say "Installing ${pkgs[*]}"
note "(These come in the normal way, once; everything after goes through Tor.)"
apt_install "${pkgs[@]}"

sudo sed -i "\\|^$BEGIN\$|,\\|^$END\$|d" "$TORRC"
if [ "$BRIDGE_TYPE" != none ]; then
    { echo "$BEGIN"; tor_bridge_config; echo "$END"; } | sudo tee -a "$TORRC" >/dev/null
fi
printf '%s\n' 'Written by debsway parts/apt-tor.sh: the system tor service is used for apt.' | sudo tee "$MARK" >/dev/null

say "Starting Tor"
sudo systemctl unmask tor.service tor@default.service >/dev/null
sudo systemctl enable --now tor@default.service >/dev/null
connected=false
for i in $(seq 90); do
    if tor_connected; then connected=true; break; fi
    [ $((i % 10)) -ne 0 ] || note "Waiting for Tor ($((i * 2))s)..."
    sleep 2
done
if ! $connected; then
    sudo journalctl _COMM=tor -n 5 --no-pager 2>/dev/null | sed 's/^/    /' >&2 || true
    warn "Tor didn't connect in 3 minutes (a bridge that is down or wrong is the usual reason)."
    warn "apt was not changed. Check the bridge, or try another kind, and run this again."
    exit 1
fi
note "Tor is connected."

say "Pointing apt at Tor"
use_tor_sources
if ! sudo apt-get update; then
    restore_sources
    sudo apt-get update >/dev/null || true
    die "apt couldn't update through Tor, so its sources were put back. (Some exit nodes are blocked by mirrors; try again.)"
fi
unset DEBSWAY_APT_UPDATED
note "apt now downloads Debian's packages through Tor over https. It is slower."
note "Undo: bash parts/apt-tor.sh --remove"
