#!/bin/bash
# Mullvad Browser as its own locked-down user, mullvad-browser, so a hacked page doesn't reach
# your files. Made by the Tor Project and Mullvad, with Tor Browser's protections against tracking
# and fingerprinting but without Tor: meant for use with a VPN, and it forgets everything when
# closed. From Mullvad's apt repository (its key pinned in pins.sh).
#  - It has no password or login, and its own home (/home/mullvad-browser).
#  - It opens inside cage, a tiny Wayland compositor shown as one window in your sway, with a
#    private X server: it runs on X11, where any program can read every window and key. A
#    restricted socket (bin/wayland-restrict) keeps it from your screen.
#  - A firewall rule (data/mullvad-browser-firewall.nft) keeps it off this computer and your
#    local network. It reaches the internet the way your computer does: through your VPN, if one
#    is connected.
#  - Nothing crosses by itself. A line of text goes through browser-sandbox clip (Super+Ctrl+b),
#    which shows it to you first; files through ~/Browsers/mullvad-browser.
# extras/mullvad-browser-regular.sh is the same browser as you, for ease. /usr/bin/mullvad-browser,
# by its full path, runs as you whichever you have.
# Usage: bash mullvad-browser-sandbox.sh [--remove | --manual]
# summary: Mullvad Browser as its own user (no Tor: use a VPN)
# security: most
# status: file:/usr/local/bin/mullvad-browser
# files: lib/browser-sandbox.sh lib/mullvad-repo.sh bin/browser-sandbox bin/browser-session data/mullvad-browser-firewall.nft bin/no-abstract-sockets bin/wayland-restrict bin/sandbox-net-check
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
. "$WREN_DIR/lib/mullvad-repo.sh"
. "$WREN_DIR/lib/browser-sandbox.sh"
if [ "${1:-}" = --manual ]; then print_manual; exit; fi
need_user

NAME=mullvad-browser

if [ "${1:-}" = --remove ]; then
    browser_remove "$NAME"
    remove_wayland_restrict
    remove_no_abstract
    remove_net_check
    # (the package stays while extras/mullvad-browser-regular.sh's marker holds it)
    apt_purge
    remove_mullvad_repo_if_unused
    exit
fi

say "Mullvad apt repository"
add_mullvad_repo

say "Installing Mullvad Browser and what it needs"
# cage, xwayland: its window and private X server; xclip, wl-clipboard: browser-sandbox clip;
# acl: sharing the socket and the folder; nftables, python3: the firewall and its check,
# wayland-restrict; the pipewire ones: its sound server, and pw-cat, the player of yours that
# reads its one pipe
need_xwayland
apt_install mullvad-browser cage xclip wl-clipboard acl nftables python3 \
    pipewire-bin pipewire-pulse wireplumber

say "The $NAME user"
browser_user "$NAME" "Wren Linux sandboxed Mullvad Browser"
browser_files "$NAME"

say "The commands"
install_bin wayland-restrict
install_no_abstract
install_net_check
browser_commands "$NAME"
browser_allow "$NAME"

say "Keeping $NAME off this computer and your network"
browser_firewall "$NAME"
browser_clip_key

note "Run it with: mullvad-browser   (or Super+d)"
note "It doesn't hide your IP address by itself: connect a VPN first."
note "Text in or out: Super+Ctrl+b, which shows it first. Files: ~/Browsers/mullvad-browser."
