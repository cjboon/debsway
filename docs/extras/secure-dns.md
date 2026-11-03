# Encrypted DNS (`extras/secure-dns.sh`)

## SYNOPSIS

```
bash ~/debsway/extras/secure-dns.sh            switch it on, or change the resolver (it asks which)
bash ~/debsway/extras/secure-dns.sh --remove   back to the network's own, unencrypted DNS
bash ~/debsway/extras/secure-dns.sh --manual   print the manual steps below

bash ~/debsway/status.sh                       the Network part says which resolver is in use
```

DNS turns names like `debian.org` into addresses, and is normally sent
unencrypted to whatever server the network hands out, so the network and your
ISP see every name you look up and could answer with a false one. With this
on, every lookup goes to Unbound, running on this computer only (127.0.0.1).
Unbound checks every answer with DNSSEC, refusing one that is proven false,
and asks one resolver you choose, over DNS over TLS (port 853), whose
certificate must be for that resolver's name. The resolvers on offer are
non-profit ones, pinned in `pins.sh` (`DOT_*`): Quad9, which also blocks known
malware sites; Digitale Gesellschaft, with no filtering and no query logs, it
says; and Applied Privacy, with no filtering and one server. A firewall rule
lets only Unbound send DNS out, so it fails closed: if the resolver can't be
reached, names stop resolving rather than going out unencrypted.
NetworkManager, dhclient and dhcpcd are told to leave `/etc/resolv.conf`
alone. Before switching over, the script checks that names resolve through
the resolver you chose, and if they don't it puts everything back.

## LIMITS

- The resolver you choose sees every name you look up, from your address.
- Wi-Fi with a sign-in page (cafés, hotels, trains) doesn't work while it's on: those pages need the network's own DNS. `--remove` puts that back.
- DNS over HTTPS can't be stopped by a firewall: debsway's Firefox switches its own off while this is installed (and encrypts its own to Quad9 without it); Mullvad Browser uses its own.
- Mullvad VPN uses its own DNS inside its tunnel while connected.
- The sites you then connect to are still seen by your network (by address, and usually by name in the TLS handshake).

## MANUAL INSTALL

```
# Nothing else may run DNS here: this must print nothing (no resolvconf or
# systemd-resolved link, nothing on port 53)
test -L /etc/resolv.conf && readlink /etc/resolv.conf
sudo ss -Hlntup 'sport = :53'

# Pick the resolver: run ONE of these three lines
# Quad9 (Switzerland, the Quad9 Foundation): also blocks known malware sites
NAME=quad9 DOT="@DOT_QUAD9@"
# Digitale Gesellschaft (Switzerland, an association): no filtering, says it logs no queries
NAME=digiges DOT="@DOT_DIGIGES@"
# Applied Privacy (Austria, the Foundation for Applied Privacy): no filtering, one server
NAME=appliedprivacy DOT="@DOT_APPLIEDPRIVACY@"
# The name its certificate must carry, and its addresses
TLS=${DOT%% *} ADDRS=${DOT#* }

# Unbound; dns-root-data is the DNSSEC root key; nftables for the firewall rule
sudo apt install --no-install-recommends unbound dns-root-data ca-certificates nftables

# Unbound's settings: answer this computer only, check DNSSEC, ask the
# resolver over TLS on port 853 and nothing else (no fallback)
{
    printf '%s\n' "# provider: $NAME" 'server:' '    interface: 127.0.0.1' \
        '    access-control: 127.0.0.0/8 allow' \
        '    tls-cert-bundle: /etc/ssl/certs/ca-certificates.crt' \
        '    hide-identity: yes' '    hide-version: yes' \
        '    harden-dnssec-stripped: yes' '    val-permissive-mode: no' '    prefetch: yes' \
        '' 'forward-zone:' '    name: "."' '    forward-tls-upstream: yes' '    forward-first: no'
    for a in $ADDRS; do printf '    forward-addr: %s@853#%s\n' "$a" "$TLS"; done
} | sudo tee /etc/unbound/unbound.conf.d/debsway-secure-dns.conf
# Unbound accepts them, and DNSSEC is on (the second line must name a file)
sudo unbound-checkconf
sudo unbound-checkconf -o auto-trust-anchor-file
sudo systemctl enable unbound && sudo systemctl restart unbound

# Keep NetworkManager, dhclient and dhcpcd from rewriting /etc/resolv.conf
printf '%s\n' '[main]' 'dns=none' 'rc-manager=unmanaged' |
    sudo tee /etc/NetworkManager/conf.d/90-debsway-secure-dns.conf
printf '%s\n' 'make_resolv_conf() { :; }' |
    sudo install -D -m 0644 /dev/stdin /etc/dhcp/dhclient-enter-hooks.d/debsway-secure-dns
test -f /etc/dhcpcd.conf && echo 'nohook resolv.conf' | sudo tee -a /etc/dhcpcd.conf
sudo nmcli general reload conf

# Every program asks Unbound (keep a copy of the old file to undo this)
sudo cp -a /etc/resolv.conf /etc/resolv.conf.debsway-secure-dns.bak
printf '%s\n' 'nameserver 127.0.0.1' 'options edns0 trust-ad' | sudo tee /etc/resolv.conf

# Names resolve through the resolver (if not, port 853 may be blocked here:
# undo the last step). The second must fail: its DNSSEC is broken on purpose.
getent hosts deb.debian.org
getent hosts dnssec-failed.org

# Only Unbound may send DNS out (data/secure-dns-firewall.nft), loaded at
# every boot before the network comes up
sudo install -D -m 0644 @DEBSWAY_DIR@/data/secure-dns-firewall.nft /etc/debsway/secure-dns.nft
printf '%s\n' '[Unit]' 'Description=Only Unbound sends DNS out of this computer' \
    'Before=network-pre.target' 'Wants=network-pre.target' '' '[Service]' \
    'Type=oneshot' 'RemainAfterExit=yes' 'ExecStart=/usr/sbin/nft -f /etc/debsway/secure-dns.nft' \
    'ExecStop=/usr/sbin/nft delete table inet debsway_secure_dns' '' '[Install]' 'WantedBy=multi-user.target' |
    sudo tee /etc/systemd/system/debsway-secure-dns-firewall.service
sudo systemctl daemon-reload
sudo systemctl enable --now debsway-secure-dns-firewall.service
getent hosts deb.debian.org
```

To undo:

```
# The firewall rule off, and its unit and rule file gone
sudo systemctl disable --now debsway-secure-dns-firewall.service
sudo rm /etc/systemd/system/debsway-secure-dns-firewall.service /etc/debsway/secure-dns.nft
sudo systemctl daemon-reload
# NetworkManager, dhclient and dhcpcd may write /etc/resolv.conf again
sudo rm /etc/NetworkManager/conf.d/90-debsway-secure-dns.conf /etc/dhcp/dhclient-enter-hooks.d/debsway-secure-dns
sudo sed -i '/^nohook resolv.conf$/d' /etc/dhcpcd.conf
sudo nmcli general reload conf
# The old /etc/resolv.conf back
sudo mv /etc/resolv.conf.debsway-secure-dns.bak /etc/resolv.conf
# Unbound's settings, then Unbound
sudo rm /etc/unbound/unbound.conf.d/debsway-secure-dns.conf
sudo apt purge unbound dns-root-data
sudo apt autoremove --purge
```
