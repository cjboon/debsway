#!/bin/bash
# Checks bin/tether and parts/tether.sh on a pretend /sys, with pretend ip, sudo, DHCP
# clients, nmcli and swaymsg: it connects only after a yes, only to a USB device with a
# phone's driver, asks for no name to be sent, and leaves secure DNS alone. That the
# real clients then send no name was seen once in a real DHCP server's log, in network
# namespaces; a real phone hasn't been tried by this test.
# Run by test.sh, or:  bash tools/test-tether.sh
# shellcheck disable=SC2016  # the inner shells and pretend programs expand their own variables
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
T=$(mktemp -d) || { echo "  FAIL  couldn't make a temp folder (is /tmp full?)"; exit 1; }
trap 'rm -rf "$T"' EXIT
fails=0
check() { # DESCRIPTION CONDITION-COMMAND...
    local what=$1
    shift
    if "$@" >/dev/null 2>&1; then printf '  ok    %s\n' "$what"; else printf '  FAIL  %s\n' "$what"; fails=$((fails + 1)); fi
}
not() { ! "$@"; }
command -v script >/dev/null || { echo "  FAIL  script (util-linux) is needed to answer on a terminal"; exit 1; }

# dev NAME DRIVER SUBSYSTEM [wireless]: a network device in the pretend /sys
S=$T/sys
mkdir -p "$S/class/net" "$S/bus"
dev() {
    local d=$S/class/net/$1 x=$S/devices/$1
    mkdir -p "$d" "$x" "$S/drivers/$2" "$S/bus/$3"
    ln -s "$x" "$d/device"
    ln -s "$S/drivers/$2" "$x/driver"
    ln -s "$S/bus/$3" "$x/subsystem"
    if [ -n "${4:-}" ]; then mkdir "$d/wireless"; fi
}
nodevs() { rm -rf "$S/class/net" "$S/devices"; mkdir -p "$S/class/net"; }

B=$T/bin
mkdir -p "$B" "$T/run"
# Everything but the clients: each writes down how it was called
printf '#!/bin/bash\necho "sudo $*" >>"%s/calls"\ncase $1 in tee) cat >"%s/run/${2##*/}" ;; chmod) ;; ip) ;; *) exec "$@" ;; esac\n' "$T" "$T" >"$B/sudo"
printf '#!/bin/sh\ncase "$*" in *route\\ show\\ default*) [ ! -e "%s/online" ] || echo "default via 192.0.2.1" ;; monitor*) cat "%s/events" ;; esac\n' "$T" "$T" >"$B/ip"
printf '#!/bin/sh\necho "swaymsg $*" >>"%s/calls"\n' "$T" >"$B/swaymsg"
for p in basename cat grep readlink sed wc date head dirname env; do
    ln -s "$(command -v "$p")" "$B/$p"
done
client() { for c in "$@"; do printf '#!/bin/sh\necho "%s $*" >>"%s/calls"\n[ ! -e "%s/client-fails" ]\n' "$c" "$T" "$T" >"$B/$c"; chmod +x "$B/$c"; done; }
noclients() { rm -f "$B/dhcpcd" "$B/dhclient" "$B/busybox" "$B/nmcli"; }
chmod +x "$B/sudo" "$B/ip" "$B/swaymsg"
R=$T/resolv.conf
echo 'nameserver 192.0.2.53' >"$R"

t() { # ANSWER ARGS...: tether, answered on a terminal, its screen in $T/out
    local a=$1
    shift
    : >"$T/calls"
    printf '%s\n' "$a" | WREN_SYS="$S" WREN_RESOLV="$R" WREN_TETHER_PATH="$B" \
        script -qec "bash '$HERE/bin/tether' $*" /dev/null >"$T/out" 2>&1
}
said() { grep -q -- "$1" "$T/out"; }
called() { grep -q -- "$1" "$T/calls"; }

# ---- what it finds ----
dev enx1a2b3c rndis_host usb
dev usb1 cdc_ncm usb
dev eth0 e1000e pci
dev eth1 cdc_ether pci
dev wlan0 rndis_host usb wireless
dev eth2 r8152 usb
dev 'bad;name' rndis_host usb
found=$(WREN_SYS="$S" WREN_TETHER_PATH="$B" bash "$HERE/bin/tether" --list | LC_ALL=C sort | paste -sd,)
check "finds USB devices with a phone's driver, and nothing else (no PCI, radio, other driver, odd name)" \
    test "$found" = "enx1a2b3c rndis_host,usb1 cdc_ncm"
for d in ipheth cdc_ether; do
    nodevs; dev phone "$d" usb
    check "...$d too" test "$(WREN_SYS="$S" WREN_TETHER_PATH="$B" bash "$HERE/bin/tether" --list)" = "phone $d"
done

# ---- it asks ----
noclients; client dhcpcd; nodevs
t y
check "no phone: it says what to do, and changes nothing" bash -c 'grep -q "No phone found" "$1/out" && grep -q "USB tethering" "$1/out" && [ ! -s "$1/calls" ]' _ "$T"

dev enx1a2b3c rndis_host usb
t ''
check "a phone, and Enter: nothing is run, and it says so" bash -c 'grep -q "Nothing was changed" "$1/out" && [ ! -s "$1/calls" ]' _ "$T"
t n
check "...n: the same" bash -c 'grep -q "Nothing was changed" "$1/out" && [ ! -s "$1/calls" ]' _ "$T"
check "it says what it found, and that it might not be a phone" bash -c 'grep -q "enx1a2b3c (rndis_host)" "$1/out" && grep -q "so can other USB devices" "$1/out"' _ "$T"
: >"$T/calls"
WREN_SYS="$S" WREN_RESOLV="$R" WREN_TETHER_PATH="$B" setsid -w bash "$HERE/bin/tether" </dev/null >"$T/out" 2>&1
check "no terminal to answer on: nothing is run" test ! -s "$T/calls"

dev usb1 cdc_ncm usb
t y
check "two found: it asks you to unplug one, and runs nothing" bash -c 'grep -q "more than one" "$1/out" && [ ! -s "$1/calls" ]' _ "$T"
rm -rf "$S/class/net/usb1"

: >"$T/online"
t ''
check "online already: it says so" said "You are online already"
rm -f "$T/online"

# ---- with no NetworkManager: the first client there is, sending no name ----
noclients; client dhcpcd dhclient busybox
t y
check "yes, with dhcpcd: that device comes up, and dhcpcd gets it" bash -c '
    grep -q "^sudo ip link set enx1a2b3c up" "$1/calls" && grep -q "^sudo dhcpcd .*enx1a2b3c" "$1/calls" && ! grep -qE "^(sudo )?(dhclient|busybox)" "$1/calls"' _ "$T"
check "...with settings of its own, without the hostname line of Debian's" bash -c '
    grep -q "^sudo dhcpcd .*-f /run/wren-tether-dhcpcd.conf" "$1/calls" && [ -s "$1/run/wren-tether-dhcpcd.conf" ] && ! grep -q hostname "$1/run/wren-tether-dhcpcd.conf"' _ "$T"
check "...DNS left to it while secure DNS is off" not called "--nohook"
check "...and it says it connected" said "Connected through enx1a2b3c"

printf '# Written by Wren Linux parts/secure-dns.sh\nnameserver 127.0.0.1\n' >"$R"
t y
check "secure DNS on: dhcpcd leaves resolv.conf alone" called "^sudo dhcpcd .*--nohook resolv.conf"
echo 'nameserver 192.0.2.53' >"$R"

noclients; client dhclient busybox
t y
check "no dhcpcd: dhclient, with settings of its own that send no name" bash -c '
    grep -q "^sudo dhclient -4 -1 -cf /run/wren-tether-dhclient.conf enx1a2b3c" "$1/calls" && ! grep -q send "$1/run/wren-tether-dhclient.conf"' _ "$T"

noclients; client busybox
t y
check "no dhclient either: busybox" called "^sudo busybox udhcpc -i enx1a2b3c -s /run/wren-tether-udhcpc.sh"
check "...whose script leaves secure DNS alone, and a linked resolv.conf" bash -c '
    grep -q "secure-dns" "$1/run/wren-tether-udhcpc.sh" && grep -q "! -L /etc/resolv.conf" "$1/run/wren-tether-udhcpc.sh"' _ "$T"
bash -n "$T/run/wren-tether-udhcpc.sh"
check "...a script that parses" sh -n "$T/run/wren-tether-udhcpc.sh"

noclients
t y
check "no client at all: it says which to install" said "no DHCP client here"

noclients; client dhcpcd; : >"$T/client-fails"
t y
check "the client fails: it says so, and doesn't claim to be connected" bash -c 'grep -q "couldn.t get a connection" "$1/out" && ! grep -q "Connected through" "$1/out"' _ "$T"
rm -f "$T/client-fails"

# ---- with NetworkManager ----
noclients; client dhcpcd
cat >"$B/nmcli" <<EOF
#!/bin/bash
echo "nmcli \$*" >>"$T/calls"
case "\$*" in
    "-t -f RUNNING general") echo running ;;
    "-g NAME connection show") cat "$T/nm-profiles" 2>/dev/null ;;
    "-t -f GENERAL.STATE device show "*) cat "$T/nm-state" 2>/dev/null ;;
esac
EOF
chmod +x "$B/nmcli"
printf 'tether-old\nHome Wi-Fi\n' >"$T/nm-profiles"
echo 'GENERAL.STATE:30 (disconnected)' >"$T/nm-state"
t y
check "NetworkManager running: it brings it up, and no sudo or client is needed" bash -c '
    grep -q "^nmcli connection up tether-enx1a2b3c" "$1/calls" && ! grep -qE "^(sudo|dhcpcd)" "$1/calls"' _ "$T"
check "...a connection that doesn't start by itself, and sends no name" bash -c '
    grep "^nmcli connection add" "$1/calls" | grep -q "connection.autoconnect no ipv4.dhcp-send-hostname no ipv6.dhcp-send-hostname no"' _ "$T"
check "...an earlier plug-in's goes, and nobody else's" bash -c '
    grep -q "^nmcli connection delete tether-old" "$1/calls" && ! grep -q "connection delete Home" "$1/calls"' _ "$T"
echo 'GENERAL.STATE:10 (unmanaged)' >"$T/nm-state"
t y
check "...a device it doesn't manage: the client instead" called "^sudo dhcpcd"
noclients; client dhcpcd

# ---- the watcher ----
w() { : >"$T/calls"; printf '%s\n' "$@" >"$T/events"; SWAYSOCK=/x WREN_SYS="$S" WREN_RESOLV="$R" WREN_TETHER_PATH="$B" timeout 10 bash "$HERE/bin/tether" --watch >/dev/null 2>&1; }
windows() { grep -c 'swaymsg exec foot' "$T/calls"; }
w 'link change'
check "the watcher, offline, a phone appears: one window" test "$(windows)" = 1
check "...which asks, and connects nothing by itself" bash -c 'grep -q -- "--hold" "$1/calls" && ! grep -qE "^(sudo|dhcpcd|nmcli connection)" "$1/calls"' _ "$T"
w 'one' 'two' 'three' 'four'
check "...a device that flaps: still one window" test "$(windows)" = 1
: >"$T/online"
w 'link change'
check "...online: no window" test "$(windows)" = 0
rm -f "$T/online"
nodevs; dev eth2 r8152 usb
w 'link change'
check "...another USB network card: no window" test "$(windows)" = 0
out=$(env -u SWAYSOCK WREN_SYS="$S" WREN_TETHER_PATH="$B" bash "$HERE/bin/tether" --watch 2>&1) && rc=0 || rc=$?
check "...outside sway: it says so, and stops" bash -c '[ "$1" -ne 0 ] && grep -q "runs in sway" <<<"$2"' _ "$rc" "$out"
check "the watcher needs no root: nothing in it calls sudo" bash -c '! sed -n "/^watch() {/,/^}/p" "$1" | grep -q sudo' _ "$HERE/bin/tether"

# ---- what the real programs need ----
check "it looks in sbin, where a normal user's PATH doesn't" grep -qE '^export PATH=.*:/usr/sbin' "$HERE/bin/tether"

# ---- the part ----
P=$HERE/parts/tether.sh
check "the part is in the base, after NetworkManager's" bash -c '. "$1/packages.sh"; [[ " ${PARTS[*]} " == *" network-manager "*" tether "* ]]' _ "$HERE"
check "NetworkManager won't connect those drivers by itself, and only those" \
    grep -qF "no-auto-default=driver:rndis_host,driver:cdc_ether,driver:cdc_ncm,driver:ipheth" "$P"
check "...the same drivers tether looks for" bash -c 'grep -qx "DRIVERS=.rndis_host cdc_ether cdc_ncm ipheth." "$1"' _ "$HERE/bin/tether"
check "sway starts the watcher, and --remove takes it all out" bash -c '
    grep -q "exec ~/.local/bin/tether --watch" "$1" && grep -q "remove_snippet tether" "$1" && grep -q "remove_bin tether" "$1" && grep -q "sudo rm -f \"\$CONF\"" "$1"' _ "$P"

[ "$fails" -eq 0 ]
