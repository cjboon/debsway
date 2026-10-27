# shellcheck shell=bash
# lib/net.sh: Wi-Fi and network config helpers. Sourced by lib.sh.

# drop_ifupdown_iface IF: comment out IF's stanza in /etc/network/interfaces
drop_ifupdown_iface() {
    local ifc=$1 file=/etc/network/interfaces tmp
    [ -f "$file" ] || return 0
    $SUDO grep -Eq "^[[:space:]]*(auto|allow-hotplug|iface)[[:space:]]+$ifc([[:space:]]|$)" "$file" ||
        return 0
    [ -e "$file.debsway.bak" ] || $SUDO cp -a "$file" "$file.debsway.bak"
    tmp=$(mktemp)
    $SUDO cat "$file" | awk -v i="$ifc" '
        /^[^[:space:]#]/ { inside = 0 }
        $1 == "iface" && $2 == i { inside = 1 }
        ($1 == "auto" || $1 == "allow-hotplug") && $2 == i && NF == 2 { print "#" $0; next }
        inside && !/^#/ { print "#" $0; next }
        { print }' >"$tmp"
    $SUDO tee "$file" <"$tmp" >/dev/null
    rm -f "$tmp"
    note "Commented out $ifc in $file (backup: $file.debsway.bak)"
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
    } | $SUDO install -D -m 0600 /dev/stdin "/etc/NetworkManager/system-connections/debsway-$hex.nmconnection"
}
