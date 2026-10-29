# Encrypted, checked DNS (`extras/secure-dns.sh`)

This makes every name lookup on your computer go through a small program called Unbound, which asks one resolver of your choice over an encrypted connection and checks the answers for forgery. A firewall rule stops other programs from sending lookups around it. If it cannot work, lookups fail rather than going out unprotected.

## The problem it solves

Before your computer can connect to `example.org`, it has to ask someone for the number (the IP address) behind that name. Normally it asks the DNS server the network gave it, usually your router and from there your provider, and it asks in plain text. Your network and provider see every name you look up, and anyone on the way can answer with a false address.

## The ideas behind it

**DNS (Domain Name System).** The phone book of the internet: names in, numbers out.

**A resolver.** A server that answers DNS questions for you.

**DNS over TLS (DoT).** The same questions, sent inside an encrypted connection (on port 853) to a resolver. Outsiders see that you talk to that resolver, not the names. The resolver itself still sees every name. The script requires the resolver's certificate to be for its name, so you really are talking to it.

**DNSSEC.** The records of the phone book can be signed. Unbound checks the signatures, starting from the root key that Debian ships in `dns-root-data`. An answer proven false is refused.

**Unbound.** A DNS program that runs on your computer, answering only 127.0.0.1 (this computer). Programs ask it, and it asks the resolver.

**A firewall rule.** An instruction to the network layer to allow or refuse certain traffic. This one is an `nft` (nftables) rule that refuses DNS leaving the computer unless it comes from Unbound.

**Fail closed.** If protection breaks, stop working instead of falling back to the unprotected way.

**DNS over HTTPS (DoH).** Encrypted DNS inside ordinary web traffic. It looks like any web page, so no firewall rule can single it out.

## How it works, step by step

1. **Checks it is safe to go on.** `/etc/resolv.conf` must be a plain file (not a link made by something like systemd-resolved), and nothing else may answer on port 53. Otherwise it stops and changes nothing.
2. **You choose a resolver.** If one is already configured it offers to keep it. The choices come from `pins.sh`: Quad9 (`dns.quad9.net`, Switzerland, blocks known malware sites), Digitale Gesellschaft (`dns.digitale-gesellschaft.ch`, Switzerland, no filtering, says it logs no queries) and Applied Privacy (`dot1.applied-privacy.net`, Austria, no filtering, one server). Nothing is chosen for you.
3. **Installs** `unbound`, `dns-root-data`, `ca-certificates` and `nftables`.
4. **Writes Unbound's settings** to `/etc/unbound/unbound.conf.d/debsway-secure-dns.conf`: listen on 127.0.0.1, check DNSSEC, forward everything with `forward-tls-upstream: yes` and `forward-first: no` to the resolver's addresses on port 853 with its name, hide Unbound's identity and version. It validates them with `unbound-checkconf` and restarts Unbound; on failure it puts the old settings back.
5. **Points the computer at Unbound.** It saves the old `/etc/resolv.conf` as `/etc/resolv.conf.debsway-secure-dns.bak`, stops NetworkManager (`dns=none`), dhclient (an enter hook) and dhcpcd (`nohook resolv.conf`) from rewriting it, and writes `nameserver 127.0.0.1`.
6. **Tests.** It checks that names resolve through your resolver (several tries). If not (port 853 blocked, a sign-in page, resolver down), it puts DNS back as it was and stops. It also checks that the deliberately broken `dnssec-failed.org` does not resolve, and warns if it does.
7. **Adds the firewall rule.** `data/secure-dns-firewall.nft` is installed as `/etc/debsway/secure-dns.nft` and loaded at every boot by the service `debsway-secure-dns-firewall.service`. In the `output` chain, it accepts traffic on the loopback, traffic from the user `unbound`, and traffic over `wg*` and `tun*` tunnels; it then refuses UDP and TCP to ports 53 and 853. It tests again; if names stop resolving, the rule is removed and the script says so.

## What it changes on your computer

- Packages: `unbound`, `dns-root-data`, `ca-certificates`, `nftables`.
- `/etc/unbound/unbound.conf.d/debsway-secure-dns.conf`; the `unbound` service enabled.
- `/etc/resolv.conf` (now `nameserver 127.0.0.1`) and the backup `/etc/resolv.conf.debsway-secure-dns.bak`.
- `/etc/NetworkManager/conf.d/90-debsway-secure-dns.conf`, `/etc/dhcp/dhclient-enter-hooks.d/debsway-secure-dns`, and a marked block in `/etc/dhcpcd.conf` if that file exists.
- `/etc/debsway/secure-dns.nft` and `/etc/systemd/system/debsway-secure-dns-firewall.service` (the nft table is `inet debsway_secure_dns`).
- `wifi.sh` no longer rewrites `/etc/resolv.conf` while this is on.
- Nothing in `~/.local/bin`.

## Using it

- Run `bash extras/secure-dns.sh` again to pick another resolver.
- `bash status.sh` (the Network part) shows which resolver is in use.
- With Mullvad VPN connected, it uses its own DNS inside its tunnel; the rule lets `wg*` and `tun*` through. When it disconnects, Unbound takes over again.

## What it protects against

- **Your network or ISP reading the names you look up,** and **forging answers** (`THREAT-MODEL.md`).
- **A program sneaking DNS around Unbound** with port 53 or 853. The rule refuses it.
- **Silent fallback to unencrypted DNS.** If the resolver cannot be reached, names stop resolving.
- **Answers proven false by DNSSEC.**

## What it doesn't protect against

- **The resolver you pick** seeing every name. You trust it instead of your network.
- **The site name travelling unencrypted** at the start of most HTTPS connections, so your network can still often see where you go. It hides it less than a VPN or Tor does.
- **DNS over HTTPS** in programs that have their own (Mullvad Browser keeps its own; Firefox's is off through `parts/firefox-hardening.sh`).
- **Wi-Fi sign-in pages** (cafés, hotels, trains): they need the network's own DNS and do not work while this is on. `--remove` switches back.
- **Names not signed with DNSSEC,** which are not protected from forgery by it.
- **Anything running as you,** which could change things.
- Mullvad's public DNS is not offered because it shuts down on 2 November 2026 (`docs/extras.md`).

## Removing it

`bash extras/secure-dns.sh --remove` removes the firewall service and rule, the network-manager, dhclient and dhcpcd settings, restores `/etc/resolv.conf` from the backup (or lets NetworkManager write it again), deletes Unbound's settings and uninstalls `unbound` and `dns-root-data`. DNS then goes to the network's own server, unencrypted.
