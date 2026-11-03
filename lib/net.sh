# shellcheck shell=bash
# lib/net.sh: Wi-Fi and network config helpers. Sourced by lib.sh.

# drop_ifupdown_iface IF: comment out IF's stanza in /etc/network/interfaces
drop_ifupdown_iface() {
    local ifc=$1 file=/etc/network/interfaces tmp
    [ -f "$file" ] || return 0
    $SUDO grep -Eq "^[[:space:]]*(auto|allow-hotplug|iface)[[:space:]]+$ifc([[:space:]]|$)" "$file" ||
        return 0
    [ -e "$file.wren.bak" ] || $SUDO cp -a "$file" "$file.wren.bak"
    tmp=$(mktemp)
    $SUDO cat "$file" | awk -v i="$ifc" '
        /^[^[:space:]#]/ { inside = 0 }
        $1 == "iface" && $2 == i { inside = 1 }
        ($1 == "auto" || $1 == "allow-hotplug") && $2 == i && NF == 2 { print "#" $0; next }
        inside && !/^#/ { print "#" $0; next }
        { print }' >"$tmp"
    $SUDO tee "$file" <"$tmp" >/dev/null
    rm -f "$tmp"
    note "Commented out $ifc in $file (backup: $file.wren.bak)"
}

wifi_ifaces() {
    local d
    for d in /sys/class/net/*; do
        if [ -d "$d/wireless" ] || [ -e "$d/phy80211" ]; then
            basename "$d"
        fi
    done
}

# nm_write_wifi SSID PSK HIDDEN(1|0) IF: a NetworkManager connection written
# straight to its config folder, so the password never shows up in the
# command line of a running nmcli (anyone on the machine can read those).
# An empty PSK is an open network. Returns 1, and writes nothing, for names
# or passwords the file format can't hold; the caller then uses nmcli.
nm_write_wifi() {
    local ssid=$1 psk=$2 hidden=$3 ifc=$4 bytes hex id key
    local edge='^[[:space:]]|[[:space:]]$'
    [[ $ssid != *[[:cntrl:]]* && $psk != *[[:cntrl:]]* ]] || return 1
    [[ ! $ssid =~ $edge && ! $psk =~ $edge ]] || return 1
    # The SSID is written as bytes, so it can hold anything
    bytes=$(printf '%s' "$ssid" | od -An -tu1 -v | tr -s ' \n' ' ' | sed 's/^ //; s/ $//; s/ /;/g;')
    hex=$(printf '%s' "$ssid" | od -An -tx1 -v | tr -d ' \n')
    id=${ssid//\\/\\\\}
    key=${psk//\\/\\\\}
    {
        printf '[connection]\nid=%s\nuuid=%s\ntype=wifi\ninterface-name=%s\n\n' \
            "$id" "$(cat /proc/sys/kernel/random/uuid)" "$ifc"
        printf '[wifi]\nmode=infrastructure\nssid=%s;\n' "$bytes"
        if [ "$hidden" = 1 ]; then printf 'hidden=true\n'; fi
        printf '\n'
        if [ -n "$psk" ]; then printf '[wifi-security]\nkey-mgmt=wpa-psk\npsk=%s\n\n' "$key"; fi
        printf '[ipv4]\nmethod=auto\n\n[ipv6]\naddr-gen-mode=default\nmethod=auto\n'
    } | $SUDO install -D -m 0600 /dev/stdin "/etc/NetworkManager/system-connections/wren-$hex.nmconnection"
}

# ssh_pubkey_ok LINE: one ssh public key, as the .pub file holds it: a key type,
# the key, maybe a comment. Nothing in front (an authorized_keys line can start
# with options such as command= or permitopen=, which a pasted line must not
# smuggle in), and ssh-keygen must be able to read it.
ssh_pubkey_ok() {
    local tmp rc=0
    [[ $1 =~ ^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp(256|384|521)|sk-ssh-ed25519@openssh\.com|sk-ecdsa-sha2-nistp256@openssh\.com)\ [A-Za-z0-9+/]+={0,3}(\ [^[:cntrl:]]*)?$ ]] || return 1
    tmp=$(mktemp)
    printf '%s\n' "$1" >"$tmp"
    ssh-keygen -l -f "$tmp" >/dev/null 2>&1 || rc=1
    rm -f "$tmp"
    return "$rc"
}

# sshd_problems USER: reads `sshd -T` (what sshd will really do) on stdin and
# prints one line for each setting that is not what extras/remote-access.sh
# wants: key login only, no root, USER only, and listening on 127.0.0.1 only.
# sshd takes the first value it finds for a setting, so a file read earlier
# can beat Wren Linux's drop-in; this catches that.
sshd_problems() {
    awk -v user="$1" '
        BEGIN {
            # settings that must be "no" (sshd -T prints every one, in lower case)
            split("AllowTcpForwarding AllowStreamLocalForwarding GatewayPorts AllowAgentForwarding X11Forwarding PermitTunnel PermitUserEnvironment", names, " ")
            for (i in names) off[tolower(names[i])] = names[i]
        }
        ($1 in off) { got[$1] = 1; if ($2 != "no") print off[$1] " is " $2 }
        $1 == "maxauthtries" { tries = 1; if ($2 + 0 > 3) print "MaxAuthTries is " $2 }
        $1 == "passwordauthentication" && $2 != "no" { print "PasswordAuthentication is " $2 }
        $1 == "kbdinteractiveauthentication" && $2 != "no" { print "KbdInteractiveAuthentication is " $2 }
        $1 == "permitrootlogin" && $2 != "no" { print "PermitRootLogin is " $2 }
        $1 == "listenaddress" && $2 !~ /^127\.0\.0\.1:/ { print "ListenAddress " $2 }
        $1 == "allowusers" { seen = 1; if ($0 != "allowusers " user) print "AllowUsers includes " $2 }
        END {
            if (!seen) print "AllowUsers is not set"
            for (k in off) if (!(k in got)) print off[k] " is not set"
            if (!tries) print "MaxAuthTries is not set"
        }'
}

# parts/secure-dns.sh's settings for Unbound (secure DNS is set up), and its
# switch: while it is on, /etc/resolv.conf points at Unbound (and says so in
# its first line) and nothing of Wren Linux's may rewrite it (wifi.sh would put
# the network's DNS server back, which its firewall rule then refuses). An
# older Wren Linux wrote "extras/". WREN_ETC is where /etc is, for tests.
SECURE_DNS_CONF=/etc/unbound/unbound.conf.d/wren-secure-dns.conf
secure_dns_installed() { [ -e "${WREN_ETC:-/etc}${SECURE_DNS_CONF#/etc}" ]; }
secure_dns_on() {
    local r=${WREN_ETC:-/etc}/resolv.conf
    [ ! -L "$r" ] && grep -qsE '^# Written by Wren Linux (parts|extras)/secure-dns\.sh' "$r"
}

# remove_wifi_config: undoes what wifi.sh wrote for a Wi-Fi it set up by hand
# (run as root): the wpa_supplicant files it marked as its own and their
# per-interface services, its ifupdown stanzas, its systemd-networkd files, and
# the DNS file it saved. It leaves alone what NetworkManager has (that is
# parts/network-manager.sh) and every package. Prints what it removed.
# WREN_ETC is where /etc is, for tests.
remove_wifi_config() {
    local etc=${WREN_ETC:-/etc} f ifc networkd=false
    for f in "$etc"/wpa_supplicant/wpa_supplicant-*.conf; do
        [ -f "$f" ] && [ "$(head -1 "$f")" = "# Written by Wren Linux wifi.sh" ] || continue
        ifc=${f##*/wpa_supplicant-}
        ifc=${ifc%.conf}
        systemctl disable --now "wpa_supplicant@$ifc.service" >/dev/null 2>&1 || true
        rm -f "$f"
        note "Removed $f"
    done
    for f in "$etc"/network/interfaces.d/wren-wifi-*; do
        [ -f "$f" ] || continue
        ifc=${f##*/wren-wifi-}
        ifdown "$ifc" >/dev/null 2>&1 || true
        rm -f "$f"
        note "Removed $f"
    done
    for f in "$etc"/systemd/network/50-wren-*.network; do
        [ -f "$f" ] || continue
        rm -f "$f"
        networkd=true
        note "Removed $f"
    done
    if $networkd; then systemctl restart systemd-networkd >/dev/null 2>&1 || true; fi
    # (not while secure DNS points it at Unbound)
    if [ -e "$etc/resolv.conf.wren.bak" ] && [ ! -L "$etc/resolv.conf" ] && ! secure_dns_on; then
        cp -a "$etc/resolv.conf.wren.bak" "$etc/resolv.conf" && rm -f "$etc/resolv.conf.wren.bak"
        note "Put back $etc/resolv.conf"
    fi
}

# set_bluetooth_autoenable FILE false|true: bluez's main.conf decides whether
# the adapter powers up by itself at start. "false" keeps it off until you
# switch it on (the Wren menu or wrenctl --bluetooth on); "true" puts bluez's
# own default back. Lines this wrote end in "# Wren Linux" so they can be undone.
set_bluetooth_autoenable() {
    local f=$1 want=$2 tmp
    if [ "$want" = false ]; then
        if grep -qE '^[#[:space:]]*AutoEnable=' "$f" 2>/dev/null; then
            tmp=$(mktemp)
            sed -E 's/^[#[:space:]]*AutoEnable=.*/AutoEnable=false # Wren Linux/' "$f" >"$tmp"
            cat "$tmp" >"$f"
            rm -f "$tmp"
        else
            printf '\n[Policy]\nAutoEnable=false # Wren Linux\n' >>"$f"
        fi
    else
        tmp=$(mktemp)
        sed -E 's/^AutoEnable=false # Wren Linux$/#AutoEnable=true/' "$f" >"$tmp"
        cat "$tmp" >"$f"
        rm -f "$tmp"
    fi
}
