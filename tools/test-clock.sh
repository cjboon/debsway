#!/bin/bash
# Checks parts/clock.sh: it switches NTP on, asks for a time zone while the
# clock is on UTC, sets only a real one, and leaves an unattended run alone.
# Runs the part with a pretend sudo, timedatectl and dpkg-query (systemd-timesyncd
# "already installed"), so nothing on this computer changes. Run by test.sh, or:
#   bash tools/test-clock.sh
# shellcheck disable=SC2016  # sed and the inner bash expand their own variables
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

mkdir -p "$T/bin"
cat >"$T/bin/sudo" <<'EOF'
#!/bin/sh
[ "$1" = -v ] && exit 0
exec "$@"
EOF
cat >"$T/bin/timedatectl" <<EOF
#!/bin/sh
case "\$1" in
    show) cat "$T/zone" ;;
    list-timezones) printf '%s\n' UTC Europe/Berlin America/New_York ;;
    *) echo "timedatectl \$*" >>"$T/calls" ;;
esac
EOF
cat >"$T/bin/dpkg-query" <<'EOF'
#!/bin/sh
case "$*" in
    *Status*) echo 'install ok installed' ;;
    *Depends*) echo 'systemd-timesyncd' ;;
esac
EOF
chmod +x "$T/bin/"*

# lib.sh sets PATH itself; a copy of Wren Linux whose lib.sh keeps the test's, so
# the pretend programs are the ones found
R=$T/r
mkdir -p "$R/parts"
sed 's|^export PATH=.*|export PATH="$CLOCK_TEST_PATH"|' "$HERE/lib.sh" >"$R/lib.sh"
grep -q CLOCK_TEST_PATH "$R/lib.sh" || { echo "  FAIL  lib.sh's PATH line wasn't found"; exit 1; }
cp "$HERE/pins.sh" "$HERE/packages.sh" "$R/"
ln -s "$HERE/lib" "$R/lib"
cp "$HERE/parts/clock.sh" "$R/parts/"
export CLOCK_TEST_PATH="$T/bin:$PATH"

# run ZONE ANSWERS... : the part, with the clock on ZONE and these typed answers
run() {
    echo "$1" >"$T/zone"
    shift
    printf '%s\n' "$@" >"$T/answers"
    : >"$T/calls"
    WREN_TEST_ANSWERS="$T/answers" bash "$R/parts/clock.sh" >"$T/out" 2>&1
}

run Etc/UTC Europe/Berlin
check "NTP is switched on" grep -qx 'timedatectl set-ntp true' "$T/calls"
check "on UTC, it asks for the time zone and sets the one typed" grep -qx 'timedatectl set-timezone Europe/Berlin' "$T/calls"
run Etc/UTC ''
check "Enter keeps UTC" not grep -q 'set-timezone' "$T/calls"
run Etc/UTC 'Mars/Olympus' 'Europe;id' America/New_York
check "a zone that isn't one is refused, and asked again" grep -qx 'timedatectl set-timezone America/New_York' "$T/calls"
check "...and never passed on" not grep -qE 'Mars|id' "$T/calls"
run Europe/Berlin y
check "another zone is kept when you say so" not grep -q 'set-timezone' "$T/calls"
echo Etc/UTC >"$T/zone"; : >"$T/calls"
WREN_NONINTERACTIVE=1 bash "$R/parts/clock.sh" >/dev/null 2>&1
check "an unattended run sets up NTP but asks nothing" \
    bash -c 'grep -qx "timedatectl set-ntp true" "$1" && ! grep -q set-timezone "$1"' _ "$T/calls"
check "it is a base part (update.sh offers a new base part to computers set up before)" \
    bash -c '. "$1/packages.sh"; printf "%s\n" "${PARTS[@]}" | grep -qx clock' _ "$HERE"

[ "$fails" -eq 0 ]
