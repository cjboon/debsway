#!/bin/bash
# Encrypted, checked DNS. Every name this computer looks up goes to Unbound,
# running on this computer only (127.0.0.1). Unbound checks every answer with
# DNSSEC and asks one resolver you choose, over an encrypted connection (DNS
# over TLS, port 853) whose certificate has to match that resolver's name. Your
# network and your ISP then see neither the names nor the answers, and can't
# forge one; the resolver you chose sees the names instead. The choice is
# yours, from the non-profit resolvers in pins.sh (DOT_*); nothing is chosen
# for you.
#  - It fails closed. A firewall rule lets only Unbound send DNS out, so a
#    program that asks some other DNS server itself is refused, and if the
#    resolver can't be reached, names stop resolving: nothing falls back to
#    unencrypted DNS. An answer DNSSEC proves false is refused too.
#  - NetworkManager, dhclient, dhcpcd and wifi.sh stop writing /etc/resolv.conf.
#  - Mullvad VPN still uses its own DNS inside its tunnel while connected.
#  - Wi-Fi with a sign-in page (cafés, hotels, trains) doesn't work while this
#    is on: those pages need the network's own DNS. --remove puts that back.
#  - DNS over HTTPS can't be stopped by a firewall: Firefox's is switched off
#    (parts/firefox-hardening.sh), Mullvad Browser keeps its own.
# Before anything is switched over it checks that names resolve through the
# resolver you chose; if they don't, it puts everything back.
# Usage: bash secure-dns.sh [--remove]
# summary: Encrypted DNS: Unbound, DNSSEC, DNS over TLS
# status: file:/etc/unbound/unbound.conf.d/debsway-secure-dns.conf
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
. "$DEBSWAY_DIR/lib/secure-dns.sh"
need_user

CONF=$SECURE_DNS_CONF
RESOLV=/etc/resolv.conf
BACKUP=/etc/resolv.conf.debsway-secure-dns.bak
NM_CONF=/etc/NetworkManager/conf.d/90-debsway-secure-dns.conf
DHCLIENT_HOOK=/etc/dhcp/dhclient-enter-hooks.d/debsway-secure-dns
DHCPCD_CONF=/etc/dhcpcd.conf
DHCPCD_BEGIN='# >>> debsway secure-dns >>>'
DHCPCD_END='# <<< debsway secure-dns <<<'
FIREWALL=/etc/debsway/secure-dns.nft
UNIT=/etc/systemd/system/debsway-secure-dns-firewall.service

reload_nm() {
    if systemctl is-active --quiet NetworkManager; then sudo nmcli general reload conf >/dev/null 2>&1 || true; fi
}

# The things that would rewrite /etc/resolv.conf with the network's DNS server
keep_hands_off() {
    printf '%s\n' '# Written by debsway extras/secure-dns.sh: NetworkManager leaves' \
        '# /etc/resolv.conf alone; it points at Unbound on this computer.' \
        '[main]' 'dns=none' 'rc-manager=unmanaged' |
        sudo install -D -m 0644 /dev/stdin "$NM_CONF"
    # dhclient (ifupdown's wired connections) calls make_resolv_conf; an enter
    # hook can replace it with nothing
    printf '%s\n' '# Written by debsway extras/secure-dns.sh: leave /etc/resolv.conf alone;' \
        '# it points at Unbound on this computer.' 'make_resolv_conf() { :; }' |
        sudo install -D -m 0644 /dev/stdin "$DHCLIENT_HOOK"
    if [ -f "$DHCPCD_CONF" ] && ! sudo grep -qxF "$DHCPCD_BEGIN" "$DHCPCD_CONF"; then
        printf '%s\n' "$DHCPCD_BEGIN" 'nohook resolv.conf' "$DHCPCD_END" | sudo tee -a "$DHCPCD_CONF" >/dev/null
    fi
    reload_nm
}

hands_back() {
    sudo rm -f "$NM_CONF" "$DHCLIENT_HOOK"
    if [ -f "$DHCPCD_CONF" ]; then
        sudo sed -i "\\|^$DHCPCD_BEGIN\$|,\\|^$DHCPCD_END\$|d" "$DHCPCD_CONF"
    fi
    reload_nm
}

# resolv.conf back as it was, or (no copy) NetworkManager writes it again
resolv_back() {
    if sudo test -e "$BACKUP"; then
        sudo mv "$BACKUP" "$RESOLV"
    elif grep -qs 'debsway extras/secure-dns.sh' "$RESOLV"; then
        sudo rm -f "$RESOLV"
        if systemctl is-active --quiet NetworkManager; then
            sudo nmcli general reload dns-full >/dev/null 2>&1 || sudo systemctl restart NetworkManager
        else
            warn "There was no copy of the old $RESOLV, so this computer has no DNS server until it"
            warn "reconnects: bash $DEBSWAY_DIR/wifi.sh (or unplug and plug in the cable)."
        fi
    fi
}

firewall_off() {
    sudo systemctl disable --now debsway-secure-dns-firewall.service >/dev/null 2>&1 || true
    sudo nft delete table inet debsway_secure_dns 2>/dev/null || true
}

# resolves: names work now (a few tries: Unbound may still be connecting)
resolves() {
    local i
    for i in $(seq 10); do
        getent hosts deb.debian.org >/dev/null 2>&1 && return 0
        sleep 2
    done
    return 1
}

if [ "${1:-}" = --remove ]; then
    firewall_off
    sudo rm -f "$FIREWALL" "$UNIT"
    sudo systemctl daemon-reload >/dev/null 2>&1 || true
    sudo rmdir /etc/debsway 2>/dev/null || true
    hands_back
    resolv_back
    sudo rm -f "$CONF"
    apt_purge unbound dns-root-data
    note "DNS goes to the network's own DNS server again, unencrypted."
    exit
fi

[ ! -L "$RESOLV" ] ||
    die "$RESOLV is a link ($(readlink "$RESOLV")): something else (resolvconf, systemd-resolved) runs DNS here. This works with a plain file only; nothing was changed."
# Unbound listens on 127.0.0.1:53, so nothing else may (sudo: ss names another
# user's program only for root)
other=$(sudo ss -Hlntup 'sport = :53' 2>/dev/null | grep -v '"unbound"' || true)
[ -z "$other" ] || die "Something else already answers DNS on this computer (port 53): $other. Nothing was changed."

say "Which resolver"
current=$(dns_current)
name='' choice=''
if [ -n "$current" ] && dns_pin "$current" >/dev/null &&
    ask "Keep using $(dns_tls_name "$current")?" y; then
    name=$current
else
    note "Unbound sends your lookups to one of these, encrypted. It sees the names you look"
    note "up (your network and ISP no longer do). Pick the one you trust most:"
    for i in "${!DNS_PROVIDERS[@]}"; do
        printf '    %d) %s\n' $((i + 1)) "$(dns_describe "${DNS_PROVIDERS[i]}")"
    done
    tty_read choice "Which one (1-${#DNS_PROVIDERS[@]})? "
    if [[ $choice =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#DNS_PROVIDERS[@]} ]; then
        name=${DNS_PROVIDERS[choice - 1]}
    fi
    [ -n "$name" ] || die "No resolver chosen, so nothing was changed. Run this again to choose one."
fi
tls=$(dns_tls_name "$name")
note "Resolver: $tls"

say "Installing Unbound"
# dns-root-data: the DNSSEC root key (only recommended, so named here).
# nftables: the rule that keeps DNS from going around Unbound.
apt_install unbound dns-root-data ca-certificates nftables

say "Unbound's settings"
old=$(mktemp)
had_old=false
if [ -f "$CONF" ]; then cp "$CONF" "$old"; had_old=true; fi
# put_back_conf: Unbound as it was before this run
put_back_conf() {
    if $had_old; then sudo install -m 0644 "$old" "$CONF"; else sudo rm -f "$CONF"; fi
    sudo systemctl restart unbound >/dev/null 2>&1 || true
}
dns_unbound_conf "$name" | sudo install -D -m 0644 /dev/stdin "$CONF"
if ! sudo unbound-checkconf >/dev/null; then
    sudo unbound-checkconf >&2 || true
    put_back_conf
    rm -f "$old"
    die "Unbound didn't accept its settings, so they were taken out again."
fi
[ -n "$(sudo unbound-checkconf -o auto-trust-anchor-file 2>/dev/null)" ] ||
    warn "Unbound has no DNSSEC root key set (Debian's root-auto-trust-anchor-file.conf is missing?): answers are encrypted but not checked."
sudo systemctl enable unbound >/dev/null 2>&1 || true
if ! sudo systemctl restart unbound; then
    put_back_conf
    rm -f "$old"
    die "Unbound didn't start with its settings (journalctl -u unbound says why); they were taken out again."
fi
note "Unbound listens on 127.0.0.1 and asks $tls on port 853."

say "Pointing this computer at Unbound"
# A copy of what was there, unless it is already ours (a second run)
if ! grep -qs 'debsway extras/secure-dns.sh' "$RESOLV" && ! sudo test -e "$BACKUP"; then
    if [ -e "$RESOLV" ]; then sudo cp -a "$RESOLV" "$BACKUP"; fi
fi
keep_hands_off
printf '%s\n' '# Written by debsway extras/secure-dns.sh. Every name goes to Unbound on this' \
    "# computer, which asks $tls over an encrypted connection." \
    'nameserver 127.0.0.1' 'options edns0 trust-ad' |
    sudo install -m 0644 /dev/stdin "$RESOLV"

if ! resolves; then
    if $had_old; then
        # It worked before with the old resolver: go back to that one
        put_back_conf
        rm -f "$old"
        die "Names don't resolve through $tls (port 853 blocked on this network, or the resolver is down). Kept the resolver you had."
    fi
    hands_back
    resolv_back
    put_back_conf
    rm -f "$old"
    die "Names don't resolve through $tls (port 853 blocked on this network, a sign-in page, or the resolver is down), so DNS was put back as it was. Unbound stays installed and unused; --remove takes it out."
fi
rm -f "$old"
note "Names resolve through $tls."
# A test domain whose signature is deliberately broken: DNSSEC must refuse it.
# (Only a wrong result is reported: refused and "no such name" look the same here.)
if getent hosts dnssec-failed.org >/dev/null 2>&1; then
    warn "dnssec-failed.org, whose DNSSEC signature is broken on purpose, resolved: DNSSEC checking doesn't seem to be on."
fi

say "Only Unbound may send DNS out"
sudo install -d -o root -g root -m 0755 "${FIREWALL%/*}"
sudo install -o root -g root -m 0644 "$DEBSWAY_DIR/data/secure-dns-firewall.nft" "$FIREWALL"
# Loaded before the network comes up, at every boot
printf '%s\n' '# Written by debsway extras/secure-dns.sh' '[Unit]' \
    'Description=Only Unbound sends DNS out of this computer (debsway)' \
    'Before=network-pre.target' 'Wants=network-pre.target' '' '[Service]' \
    'Type=oneshot' 'RemainAfterExit=yes' \
    "ExecStart=/usr/sbin/nft -f $FIREWALL" \
    'ExecStop=/usr/sbin/nft delete table inet debsway_secure_dns' '' '[Install]' \
    'WantedBy=multi-user.target' | sudo tee "$UNIT" >/dev/null
sudo systemctl daemon-reload
# Restart, not just enable --now: a changed rule file is only loaded by a restart
sudo systemctl enable debsway-secure-dns-firewall.service >/dev/null &&
    sudo systemctl restart debsway-secure-dns-firewall.service ||
    warn "Couldn't load the firewall rule; check: systemctl status debsway-secure-dns-firewall"
if ! resolves; then
    firewall_off
    die "With the firewall rule on, names stopped resolving, so the rule was taken off again. Encrypted DNS through Unbound stays on; please report this."
fi

note "Done. Every lookup goes, encrypted, to $tls and is checked with DNSSEC."
note "Wi-Fi with a sign-in page won't work while this is on; --remove switches it off."
note "Change the resolver: run this again.   Check it: bash status.sh (the Network part)"
