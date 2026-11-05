#!/bin/bash
# Encrypted, checked DNS, with a switch. Every name this computer looks up goes
# to Unbound, running on this computer only (127.0.0.1). Unbound checks every
# answer with DNSSEC and asks one resolver you choose, over an encrypted
# connection (DNS over TLS, port 853) whose certificate has to match that
# resolver's name. Your network and your ISP then see neither the names nor the
# answers, and can't forge one; the resolver you chose sees the names instead.
# Enter picks Quad9 (also what Firefox uses for its own when this is off).
#  - It fails closed while on. A firewall rule lets only Unbound send DNS out,
#    so a program that asks some other DNS server itself (the sandboxed Claude
#    and the VMs included) is refused, and if the resolver can't be reached,
#    names stop resolving: nothing falls back to unencrypted DNS. An answer
#    DNSSEC proves false is refused too.
#  - The switch (the Wren menu's Secure DNS line, or: secure-dns on|off):
#    off is for Wi-Fi with a sign-in page (cafés, hotels, trains), which needs
#    the network's own DNS; on again once signed in. Switching on checks that
#    names resolve first, and stays off if they don't. Your user may switch it
#    without a password (bin/secure-dns-switch, through a sudo rule that allows
#    exactly "on" and "off"), so a program running as you could switch it off.
#  - While it is off, Wren Linux's Firefox encrypts its own lookups (to Quad9; set
#    at its start). Other programs use the network's DNS. The Wi-Fi sign-in
#    window (wifi-signin, parts/incognito.sh) switches it off and on for you.
#  - While it is on, NetworkManager, dhclient, dhcpcd and wifi.sh leave
#    /etc/resolv.conf alone. Mullvad VPN still uses its own DNS in its tunnel.
# Run again (as update.sh does), it keeps the switch where you left it; it
# asks the resolver again only if you want another.
# Usage: bash secure-dns.sh [--remove]
# files: bin/secure-dns-switch data/secure-dns-firewall.nft lib/secure-dns.sh
# status: file:/etc/unbound/unbound.conf.d/wren-secure-dns.conf bin:secure-dns
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
. "$WREN_DIR/lib/secure-dns.sh"
need_user

CONF=$SECURE_DNS_CONF
RESOLV=/etc/resolv.conf
SWITCH=/usr/local/libexec/wren-secure-dns
SUDOERS=/etc/sudoers.d/wren-secure-dns
FIREWALL=/etc/wren/secure-dns.nft
UNIT=/etc/systemd/system/wren-secure-dns-firewall.service

RC=$HOME/.bashrc
RC_BEGIN='# >>> Wren Linux secure-dns check >>>'
RC_END='# <<< Wren Linux secure-dns check <<<'
rc_take_out() { [ -f "$RC" ] && sed -i "\\|^$RC_BEGIN\$|,\\|^$RC_END\$|d" "$RC"; return 0; }

if [ "${1:-}" = --remove ]; then
    remove_snippet secure-dns
    rc_take_out
    # (the switch puts resolv.conf and the network's DNS back, and tells Firefox)
    if [ -x "$SWITCH" ]; then sudo "$SWITCH" off || true; fi
    sudo systemctl disable --now wren-secure-dns-firewall.service >/dev/null 2>&1 || true
    sudo nft delete table inet wren_secure_dns 2>/dev/null || true
    sudo rm -f "$FIREWALL" "$UNIT" "$SUDOERS" "$SWITCH" "$CONF"
    sudo systemctl daemon-reload >/dev/null 2>&1 || true
    sudo rmdir /usr/local/libexec /etc/wren 2>/dev/null || true
    remove_bin secure-dns
    apt_purge unbound dns-root-data
    note "DNS goes to the network's own DNS server again, unencrypted (Wren Linux's Firefox encrypts its own)."
    exit
fi

# What doesn't fit here is said and skipped, so the rest of the install goes on
if [ -L "$RESOLV" ] && ! grep -qsE '^# Written by Wren Linux (parts|extras)/secure-dns\.sh' "$RESOLV"; then
    note "$RESOLV is a link ($(readlink "$RESOLV")): something else (resolvconf, systemd-resolved) runs DNS"
    note "here. Secure DNS works with a plain file only, so it was skipped; nothing was changed."
    exit 0
fi
# Unbound listens on 127.0.0.1:53, so nothing else may (sudo: ss names another
# user's program only for root)
other=$(sudo ss -Hlntup 'sport = :53' 2>/dev/null | grep -v '"unbound"' || true)
if [ -n "$other" ]; then
    note "Something else already answers DNS on this computer (port 53): $other."
    note "Secure DNS was skipped; nothing was changed."
    exit 0
fi

say "Which resolver"
first=true
[ ! -f "$CONF" ] || first=false
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
    tty_read choice "Which one (1-${#DNS_PROVIDERS[@]}, Enter: 1)? "
    [ -n "$choice" ] || choice=1
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
rm -f "$old"
note "Unbound listens on 127.0.0.1 and asks $tls on port 853."

say "Only Unbound may send DNS out (while it is on)"
sudo install -d -o root -g root -m 0755 "${FIREWALL%/*}"
sudo install -o root -g root -m 0644 "$WREN_DIR/data/secure-dns-firewall.nft" "$FIREWALL"
# Loaded before the network comes up, at every boot, while the switch is on
# (the switch enables and disables it)
printf '%s\n' '# Written by Wren Linux parts/secure-dns.sh' '[Unit]' \
    'Description=Only Unbound sends DNS out of this computer (Wren Linux)' \
    'Before=network-pre.target' 'Wants=network-pre.target' '' '[Service]' \
    'Type=oneshot' 'RemainAfterExit=yes' \
    "ExecStart=/usr/sbin/nft -f $FIREWALL" \
    'ExecStop=/usr/sbin/nft delete table inet wren_secure_dns' '' '[Install]' \
    'WantedBy=multi-user.target' | sudo tee "$UNIT" >/dev/null
sudo systemctl daemon-reload

say "The switch"
sudo install -d -o root -g root -m 0755 "${SWITCH%/*}"
sudo install -o root -g root -m 0755 "$WREN_DIR/bin/secure-dns-switch" "$SWITCH"
# Off without a password, or (your choice) only with it: a program running as
# you can then no longer switch it off silently (the bar shows it either way)
STRICT=$HOME/.config/wren/secure-dns-strict
note "Off sends this computer's lookups to the network unencrypted. Anything running as"
note "you can switch it off as easily as you can (the bar shows \"dns OFF\" then). With a"
note "password, it can't do it without you; the Wi-Fi sign-in window and the menu then ask too."
rule=$(mktemp)
# Yes unless you said no before (the switch's rule is there, without your yes):
# a run again keeps your answer as its default
strict_default=y
if [ ! -e "$STRICT" ] && sudo test -e "$SUDOERS"; then strict_default=n; fi
if auto_or_ask WREN_SECURE_DNS_STRICT "Switching secure DNS off: ask for your password?" "$strict_default"; then
    mkdir -p "${STRICT%/*}" && : >"$STRICT"
    printf '# Written by Wren Linux parts/secure-dns.sh. %s may switch secure DNS on, and\n# nothing else, without a password; off asks for it (sudo %s off).\n%s ALL=(root) NOPASSWD: %s on\n' \
        "$(id -un)" "$SWITCH" "$(id -un)" "$SWITCH" >"$rule"
else
    rm -f "$STRICT"
    printf '# Written by Wren Linux parts/secure-dns.sh. %s may switch secure DNS on and off,\n# and nothing else, without a password (the Wren menu does).\n%s ALL=(root) NOPASSWD: %s on, %s off\n' \
        "$(id -un)" "$(id -un)" "$SWITCH" "$SWITCH" >"$rule"
fi
# A broken sudoers file locks you out of sudo, so it is checked first
if ! sudo visudo -cf "$rule" >/dev/null; then
    rm -f "$rule"
    die "The sudoers rule didn't pass visudo's check, so it wasn't installed."
fi
sudo install -o root -g root -m 0440 "$rule" "$SUDOERS"
rm -f "$rule"
install_bin secure-dns
# At login: a word if the Wi-Fi sign-in window left secure DNS off (logged out
# while it was open). In sway a notification; on a text console, the shell
put_snippet secure-dns <<'EOF'
# Says so at login if the Wi-Fi sign-in window left secure DNS off (Wren Linux parts/secure-dns.sh)
exec ~/.local/bin/secure-dns login-check
EOF
rc_take_out
# shellcheck disable=SC2016  # written into ~/.bashrc as it is, expanded there
printf '%s\n' "$RC_BEGIN" '[ -n "${WAYLAND_DISPLAY:-}" ] || [ ! -x ~/.local/bin/secure-dns ] || ~/.local/bin/secure-dns login-check' "$RC_END" >>"$RC"

# On at the first install, and whenever it was on; a switch you turned off stays off
if $first || [ "$("$BIN/secure-dns" status)" = on ]; then
    if [ "$("$BIN/secure-dns" status)" = on ]; then
        # already on: the firewall rule and Firefox's policy again, as they may have changed
        sudo systemctl restart wren-secure-dns-firewall.service ||
            warn "Couldn't load the firewall rule; check: systemctl status wren-secure-dns-firewall"
        if [ -x /usr/local/bin/ublock-allow ]; then sudo /usr/local/bin/ublock-allow --refresh >/dev/null || true; fi
        note "Secure DNS is on: every lookup goes, encrypted, to $tls and is checked with DNSSEC."
    elif sudo "$SWITCH" on; then
        note "Every lookup goes, encrypted, to $tls and is checked with DNSSEC."
    else
        warn "Secure DNS is installed but off (see above). Switch it on once names resolve:"
        warn "the Wren menu's Secure DNS line, or: secure-dns on"
    fi
else
    note "Secure DNS stays off, as you left it: the Wren menu, or secure-dns on."
fi
# A test domain whose signature is deliberately broken: DNSSEC must refuse it.
# (Only a wrong result is reported: refused and "no such name" look the same here.)
if [ "$("$BIN/secure-dns" status)" = on ] && getent hosts dnssec-failed.org >/dev/null 2>&1; then
    warn "dnssec-failed.org, whose DNSSEC signature is broken on purpose, resolved: DNSSEC checking doesn't seem to be on."
fi
note "Wi-Fi with a sign-in page: switch it off in the Wren menu (Secure DNS), sign in,"
note "and switch it on again. Change the resolver: run this again."
