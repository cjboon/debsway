#!/bin/sh
# preseed/include_command for debsway's install ISO (prep/make-install-iso.sh):
# runs inside the Debian installer before it sets up the network, and its
# standard output must be empty or the location of a preseed part.
#
# If a wired port has a cable plugged in, nothing is printed: the installer
# configures it and uses the mirror. If there is no wired link (a laptop on
# wifi only), a small preseed part is written that switches network setup
# off, so the installer doesn't stop with questions about wifi or "network
# autoconfiguration failed", and it installs from the ISO alone. wifi.sh
# sets up wifi after the install, when debsway's own install begins.
# (DEBSWAY_NET, DEBSWAY_INC and DEBSWAY_WAIT are for tests.)

NET=${DEBSWAY_NET:-/sys/class/net}
INC=${DEBSWAY_INC:-/tmp/debsway-net.preseed}
WAIT=${DEBSWAY_WAIT:-8}

# wired: the names of the ports that are not loopback, wifi or virtual
wired() {
    for d in "$NET"/*; do
        [ -e "$d" ] || continue
        n=${d##*/}
        [ "$n" = lo ] && continue
        [ -e "$d/wireless" ] || [ -e "$d/phy80211" ] && continue
        [ -e "$d/device" ] || continue
        echo "$n"
    done
}

ports=$(wired)
for n in $ports; do
    ip link set "$n" up 2>/dev/null || ifconfig "$n" up 2>/dev/null || true
done

# a cable can take a few seconds to report its link
i=0
while :; do
    for n in $ports; do
        if [ "$(cat "$NET/$n/carrier" 2>/dev/null)" = 1 ]; then
            logger -t debsway "wired link on $n: the installer sets up the network" 2>/dev/null || true
            exit 0
        fi
    done
    [ "$i" -ge "$WAIT" ] && break
    i=$((i + 1))
    [ -n "$ports" ] && sleep 1 || break
done

# Values set from here through debconf-set-selections don't stick: in the
# installer's cdebconf only the preseed loader's own context reliably
# persists the values (its own load of the preseed file does, and other
# contexts get stomped by competing database snapshots). So give the
# decision to that context instead of seeding debconf oneself:
# preseed/include_command takes the location this script prints and the
# loader fetches and applies the part itself (lib/preseed/preseed.sh).
{
    printf '%s\n' 'd-i netcfg/enable boolean false' \
        'd-i apt-setup/use_mirror boolean false' \
        'd-i pkgsel/upgrade select none'
} >"$INC"
logger -t debsway "no wired link: network setup skipped (wifi.sh does wifi after the install)" 2>/dev/null || true
echo "file://$INC"
