#!/bin/bash
# Checks parts/no-live-extras.sh and lib/live-extras.sh: what Debian's live
# image adds is taken out, printing only if you don't print, dkms and mdadm
# only when nothing needs them, sudo is marked wanted first, and a removal that
# would take something the system needs is refused. Runs the part with a
# pretend sudo (it only logs), dpkg-query, apt-mark, apt-get (-s answers),
# apt-cache, lsblk and modinfo, a pretend /sys, /proc/mdstat and DKMS folder,
# so nothing on this computer changes. Run by test.sh, or:
#   bash tools/test-live-extras.sh
# shellcheck disable=SC2016  # the pretend programs expand their own variables
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
fails=0
check() { # DESCRIPTION CONDITION-COMMAND...
    local what=$1
    shift
    if "$@" >/dev/null 2>&1; then printf '  ok    %s\n' "$what"; else printf '  FAIL  %s\n' "$what"; fails=$((fails + 1)); fi
}
not() { ! "$@"; }

mkdir -p "$T/bin" "$T/etc/mdadm" "$T/dkms"
cat >"$T/bin/sudo" <<EOF
#!/bin/sh
[ "\$1" = -v ] && exit 0
echo "\$*" >>"$T/root-calls"
EOF
# Installed: the packages in $T/installed; apt-mark showauto: those in $T/auto
cat >"$T/bin/dpkg-query" <<EOF
#!/bin/sh
for a; do p=\$a; done
grep -qx "\$p" "$T/installed" && echo 'install ok installed'
exit 0
EOF
cat >"$T/bin/apt-mark" <<EOF
#!/bin/sh
[ "\$1" = showauto ] && { shift; for p; do grep -x "\$p" "$T/auto"; done; }
exit 0
EOF
# apt-get -s purge --autoremove PKG...: each PKG, and what $T/also says it takes
cat >"$T/bin/apt-get" <<EOF
#!/bin/sh
[ "\$1" = -s ] || exit 1
shift 3
for p; do echo "Purg \$p [1.0]"; done
cat "$T/also" 2>/dev/null | sed 's/^/Purg /; s/\$/ [1.0]/'
EOF
# apt-cache rdepends --installed ... dkms: what $T/dkms-users lists
cat >"$T/bin/apt-cache" <<EOF
#!/bin/sh
printf 'dkms\nReverse Depends:\n'
sed 's/^/  /' "$T/dkms-users" 2>/dev/null
exit 0
EOF
cat >"$T/bin/lsblk" <<EOF
#!/bin/sh
cat "$T/lsblk" 2>/dev/null
EOF
cat >"$T/bin/modinfo" <<EOF
#!/bin/sh
[ "\$1" = -n ] && cat "$T/modpath-\$2"
EOF
chmod +x "$T/bin/"*

R=$T/r
mkdir -p "$R/parts"
sed 's|^export PATH=.*|export PATH="$LIVE_TEST_PATH"|' "$HERE/lib.sh" >"$R/lib.sh"
grep -q LIVE_TEST_PATH "$R/lib.sh" || { echo "  FAIL  lib.sh's PATH line wasn't found"; exit 1; }
cp "$HERE/pins.sh" "$HERE/packages.sh" "$R/"
ln -s "$HERE/lib" "$R/lib"
cp "$HERE/parts/no-live-extras.sh" "$R/parts/"
export LIVE_TEST_PATH="$T/bin:$PATH" WREN_DKMS_DIR=$T/dkms WREN_MDSTAT=$T/mdstat WREN_ETC=$T/etc

LIVE="avahi-daemon libnss-mdns hw-probe extrepo inetutils-telnet"
PRINT="cups cups-daemon cups-core-drivers cups-browsed"
# setup PACKAGES...: a clean computer with these installed (sudo "automatic")
setup() {
    printf '%s\n' sudo "$@" >"$T/installed"
    echo sudo >"$T/auto"
    : >"$T/also"; : >"$T/dkms-users"; : >"$T/lsblk"; : >"$T/etc/mdadm/mdadm.conf"
    rm -rf "${T:?}/dkms/"*
    printf 'Personalities : [raid1]\nunused devices: <none>\n' >"$T/mdstat"
}
# run ANSWER...: the part, with these typed answers
run() {
    printf '%s\n' "$@" >"$T/answers"
    : >"$T/root-calls"
    WREN_TEST_ANSWERS="$T/answers" bash "$R/parts/no-live-extras.sh" >"$T/out" 2>&1
}
purged() { # PACKAGE: it was in the purge
    grep '^apt-get purge' "$T/root-calls" | tr ' ' '\n' | grep -qx "$1"
}
purge_ran() { grep -q '^apt-get purge' "$T/root-calls"; }

# shellcheck disable=SC2086  # word lists on purpose
setup $LIVE $PRINT dkms mdadm
run n
check "sudo is marked wanted before anything is removed" grep -qx 'apt-mark manual sudo' "$T/root-calls"
check "...first" test "$(head -1 "$T/root-calls")" = 'apt-mark manual sudo'
for p in $LIVE; do check "$p is removed" purged "$p"; done
check "not printing: cups goes" purged cups
check "...and cups-browsed" purged cups-browsed
check "dkms goes when it builds nothing and nothing needs it" purged dkms
check "mdadm goes when there is no RAID" purged mdadm
check "what goes with them is shown first" grep -q 'Going: ' "$T/out"
check "it purges, and lets apt take what only they needed" grep -q '^apt-get purge --autoremove -y ' "$T/root-calls"

# shellcheck disable=SC2086
setup $LIVE $PRINT
run y
check "printing: cups stays" not purged cups
check "...cups-daemon too" not purged cups-daemon
check "...but cups-browsed, which looks for printers on the network, goes" purged cups-browsed
check "...and avahi still goes" purged avahi-daemon

setup dkms
mkdir -p "$T/dkms/rtl8821cu/5.12"
run
check "dkms stays when it builds a module" not purged dkms
check "...and says why" grep -q 'Keeping dkms: it builds the kernel module rtl8821cu' "$T/out"
setup dkms
echo broadcom-sta-dkms >"$T/dkms-users"
run
check "dkms stays when a package needs it" not purged dkms
check "...and says which" grep -q 'broadcom-sta-dkms needs it' "$T/out"

setup mdadm
printf 'Personalities : [raid1]\nmd0 : active raid1 sda1[0] sdb1[1]\nunused devices: <none>\n' >"$T/mdstat"
run
check "mdadm stays while a RAID array runs" not purged mdadm
setup mdadm
printf '\nlinux_raid_member\next4\n' >"$T/lsblk"
run
check "...or a disk is part of one" not purged mdadm
setup mdadm
echo 'ARRAY /dev/md0 metadata=1.2 UUID=x' >"$T/etc/mdadm/mdadm.conf"
run
check "...or its settings name one" not purged mdadm

setup hw-probe
echo sudo >"$T/also"
run
check "a removal that would take sudo with it is refused" grep -q 'would also take out sudo' "$T/out"
check "...and nothing is removed" not purge_ran
setup avahi-daemon
printf 'cryptsetup\nlinux-image-6.12.1-amd64\n' >"$T/also"
run
check "...as is one that would take the disk's encryption or the kernel" not purge_ran

setup
echo x >"$T/auto"
run
check "with nothing to remove, nothing is run" test ! -s "$T/root-calls"
check "...and it says so" grep -q "None of the live image's extras" "$T/out"

# shellcheck disable=SC2086
setup $PRINT
printf '%s\n' n >"$T/answers"; : >"$T/root-calls"
WREN_NONINTERACTIVE=1 bash "$R/parts/no-live-extras.sh" >"$T/out" 2>&1
check "unattended, it doesn't ask and printing goes (the default)" purged cups

: >"$T/root-calls"; bash "$R/parts/no-live-extras.sh" --remove >"$T/out" 2>&1
check "--remove changes nothing" test ! -s "$T/root-calls"

# The status line: done once the packages are gone
check "the part is in the base (PARTS)" bash -c '. "$1/packages.sh"; printf "%s\n" "${PARTS[@]}" | grep -qx no-live-extras' _ "$HERE"
setup avahi-daemon
st=$(cd "$R" && bash -c '. ./lib.sh; script_found parts/no-live-extras.sh')
check "status: reported as done when hw-probe is gone" grep -qx 'no hw-probe' <<<"$st"
check "...not for avahi, still installed" not grep -qx 'no avahi-daemon' <<<"$st"

# wifi.sh's note: a Wi-Fi driver DKMS built
mkdir -p "$T/sys/class/net/wlan0/device/driver" "$T/sys/module/rtw88"
ln -s "$T/sys/module/rtw88" "$T/sys/class/net/wlan0/device/driver/module"
echo /lib/modules/6.12/updates/dkms/rtw88.ko.xz >"$T/modpath-rtw88"
drv() { (export PATH="$T/bin:$PATH"; SYS=$T/sys; . "$HERE/lib/live-extras.sh"; dkms_wifi_driver wlan0); }
check "a Wi-Fi driver DKMS built is recognised" test "$(drv)" = rtw88
echo /lib/modules/6.12/kernel/drivers/net/wireless/rtw88.ko.xz >"$T/modpath-rtw88"
check "...one from the kernel isn't" not drv
check "wifi.sh says so when it picks the device" grep -q 'dkms_wifi_driver "\$IF"' "$HERE/wifi.sh"

[ "$fails" -eq 0 ]
