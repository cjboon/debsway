# shellcheck shell=bash
# lib/secure-dns.sh: the DNS-over-TLS resolvers extras/secure-dns.sh offers,
# and the files it writes. Sourced after lib.sh (by the extra, status.sh and
# the tests). The addresses are pinned in pins.sh (DOT_*). Where the files are
# is in lib/net.sh (SECURE_DNS_CONF), since wifi.sh needs to know too.

# In the order they are offered
DNS_PROVIDERS=(quad9 digiges appliedprivacy)

# dns_pin NAME: "TLS-NAME ADDRESS..." from pins.sh
dns_pin() {
    case $1 in
        quad9) echo "$DOT_QUAD9" ;;
        digiges) echo "$DOT_DIGIGES" ;;
        appliedprivacy) echo "$DOT_APPLIEDPRIVACY" ;;
        *) return 1 ;;
    esac
}

# dns_describe NAME: one line on who it is
dns_describe() {
    case $1 in
        quad9) echo "Quad9 (Switzerland, the Quad9 Foundation): also blocks known malware sites" ;;
        digiges) echo "Digitale Gesellschaft (Switzerland, an association): no filtering, says it logs no queries" ;;
        appliedprivacy) echo "Applied Privacy (Austria, the Foundation for Applied Privacy): no filtering, one server" ;;
        *) return 1 ;;
    esac
}

# dns_tls_name NAME: the name the resolver's certificate must carry
dns_tls_name() { local p; p=$(dns_pin "$1") || return 1; echo "${p%% *}"; }

# dns_unbound_conf NAME: Unbound's settings for that resolver. Debian's own
# root-auto-trust-anchor-file.conf already turns DNSSEC checking on; this adds
# where Unbound listens and where it asks.
dns_unbound_conf() {
    local name=$1 pin tls a
    pin=$(dns_pin "$name") || return 1
    tls=${pin%% *}
    cat <<EOF
# Written by debsway extras/secure-dns.sh. Run it again to change the resolver.
# provider: $name
# Unbound answers this computer only, checks every answer with DNSSEC, and asks
# $tls, encrypted (DNS over TLS on port 853); its certificate has to be
# for that name. Nothing goes out unencrypted, and nothing falls back.
server:
    interface: 127.0.0.1
    access-control: 127.0.0.0/8 allow
    tls-cert-bundle: /etc/ssl/certs/ca-certificates.crt
    hide-identity: yes
    hide-version: yes
    harden-dnssec-stripped: yes
    val-permissive-mode: no
    prefetch: yes

forward-zone:
    name: "."
    forward-tls-upstream: yes
    forward-first: no
EOF
    for a in ${pin#* }; do
        printf '    forward-addr: %s@853#%s\n' "$a" "$tls"
    done
}

# dns_current: the resolver in use (from SECURE_DNS_CONF), or nothing
dns_current() {
    sed -n 's/^# provider: //p' "${DEBSWAY_ETC:-/etc}/unbound/unbound.conf.d/debsway-secure-dns.conf" 2>/dev/null | head -1
}

# dns_status: one line for status.sh
dns_status() {
    local name tls
    if secure_dns_on && name=$(dns_current) && tls=$(dns_tls_name "$name"); then
        echo "DNS: encrypted to $tls, checked with DNSSEC (extras/secure-dns.sh)"
    else
        echo "DNS: unencrypted, to the network's DNS server (extras/secure-dns.sh encrypts it)"
    fi
}
