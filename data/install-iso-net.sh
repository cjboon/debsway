#!/bin/sh
# preseed/early_command for debsway's install ISO (prep/make-install-iso.sh):
# runs inside the Debian installer before it sets up the network.
#
# If a wired port has a cable plugged in, nothing changes: the installer
# configures it and uses the mirror. If there is no wired link (a laptop on
# wifi only), network setup is switched off, so the installer doesn't stop
# with questions about wifi or "network autoconfiguration failed", and it
# installs from the ISO alone. wifi.sh sets up wifi after the install, when
# debsway's own install begins.
# (DEBSWAY_NET, DEBSWAY_SEED and DEBSWAY_WAIT are for tests.)

NET=${DEBSWAY_NET:-/sys/class/net}
SEED=${DEBSWAY_SEED:-debconf-set-selections}
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

# The questions and their templates are not loaded yet (netcfg, apt-setup and
# pkgsel run later in the menu), so debconf-set would silently not set them.
# debconf-set-selections registers a dummy template when it has to, and is
# what the preseed itself goes through.
seed=$(mktemp)
{
    printf '%s\n' 'd-i netcfg/enable boolean false' \
        'd-i apt-setup/use_mirror boolean false' \
        'd-i pkgsel/upgrade select none'
} >"$seed"
# (debconf-set-selections reads the values from stdin)
$SEED <"$seed" 2>/dev/null
rm -f "$seed"
logger -t debsway "no wired link: network setup skipped (wifi.sh does wifi after the install)" 2>/dev/null || true
exit 0
