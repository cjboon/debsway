#!/bin/bash
# DNS from Wren Linux's sandbox users only to the resolver this computer uses.
# Their firewall rules (data/*-firewall.nft: the sandboxed Firefox, incognito,
# the Wi-Fi sign-in window, yt-dlp, Claude's own user, the VMs) take port 53
# only to the addresses in a set, "resolvers", in their own table, instead of
# to any address. A root helper (bin/sandbox-dns-update, installed as
# /usr/local/libexec/wren-sandbox-dns) fills those sets from /etc/resolv.conf:
# Unbound on 127.0.0.1 while secure DNS is on, the network's resolver while it
# is off. systemd runs it at boot, whenever /etc/resolv.conf changes (a path
# unit), and after each sandbox's firewall is loaded (a drop-in for its
# service, since loading empties the set).
# A hacked sandbox is kept off whatever else listens on port 53 nearby; it can
# still send data out, as it can reach the internet anyway.
# Usage: bash sandbox-dns.sh [--remove]
# status: file:/usr/local/libexec/wren-sandbox-dns
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
need_user

HELPER=/usr/local/libexec/wren-sandbox-dns
SERVICE=/etc/systemd/system/wren-sandbox-dns.service
WATCH=/etc/systemd/system/wren-sandbox-dns.path
# The sandboxes' firewall services, set up now or later by their scripts
FIREWALLS=(wren-firefox-firewall wren-incognito-firewall wren-ytdlp-firewall wren-claude-firewall wren-tor-browser-firewall wren-mullvad-browser-firewall
    wren-claude-vm-firewall wren-opencode-vm-firewall wren-onion-site-firewall wren-distro-vm-firewall)
DROPIN=60-wren-sandbox-dns.conf

if [ "${1:-}" = --remove ]; then
    sudo systemctl disable --now wren-sandbox-dns.path wren-sandbox-dns.service >/dev/null 2>&1 || true
    for u in "${FIREWALLS[@]}"; do sudo rm -f "/etc/systemd/system/$u.service.d/$DROPIN"; done
    sudo rm -f "$SERVICE" "$WATCH" "$HELPER"
    sudo systemctl daemon-reload
    warn "The sandboxes' DNS sets are no longer filled: after their firewalls are next loaded,"
    warn "the sandboxed Firefox, incognito, yt-dlp and the others can't look names up."
    warn "Put it back with: wrenctl part sandbox-dns"
    exit
fi

say "DNS from the sandboxes only to this computer's resolver"
sudo install -d -o root -g root -m 0755 "${HELPER%/*}"
sudo install -o root -g root -m 0755 "$WREN_DIR/bin/sandbox-dns-update" "$HELPER"
printf '%s\n' '# Written by Wren Linux parts/sandbox-dns.sh' '[Unit]' \
    "Description=Wren Linux: the sandboxes' DNS to this computer's resolver only" \
    "After=network-pre.target $(printf '%s.service ' "${FIREWALLS[@]}")" '' \
    '[Service]' 'Type=oneshot' "ExecStart=$HELPER" '' '[Install]' 'WantedBy=multi-user.target' |
    sudo tee "$SERVICE" >/dev/null
printf '%s\n' '# Written by Wren Linux parts/sandbox-dns.sh: whenever the resolver changes' '[Path]' \
    'PathChanged=/etc/resolv.conf' 'Unit=wren-sandbox-dns.service' '' '[Install]' 'WantedBy=multi-user.target' |
    sudo tee "$WATCH" >/dev/null
for u in "${FIREWALLS[@]}"; do
    sudo install -d -o root -g root -m 0755 "/etc/systemd/system/$u.service.d"
    printf '%s\n' '# Written by Wren Linux parts/sandbox-dns.sh: loading the rule empties its' \
        '# resolvers set, so it is filled again right after' '[Service]' "ExecStartPost=-$HELPER" |
        sudo tee "/etc/systemd/system/$u.service.d/$DROPIN" >/dev/null
done
sudo systemctl daemon-reload
sudo systemctl enable --now wren-sandbox-dns.path >/dev/null
sudo systemctl enable wren-sandbox-dns.service >/dev/null
sudo systemctl start wren-sandbox-dns.service || warn "Couldn't fill the sets now; they are filled at the next boot."
note "The sandboxes send DNS only to: $(sed -n 's/^nameserver //p' /etc/resolv.conf 2>/dev/null | paste -sd' ' || true)"
