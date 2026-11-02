#!/bin/bash
# Checks extras/signal.sh: Signal's repository goes in only with the pinned
# key; unattended-upgrades updates it; the sandbox helper's setuid bit is taken
# off before the package is installed, by an override updates keep; --remove
# undoes it all. Runs the extra with a pretend sudo (it runs only gpg and
# install into the temp folder, and logs the rest), a pretend server serving a
# throwaway key, and a pretend dpkg, in a temp home, so nothing on this computer
# changes. Run by test.sh, or:  bash tools/test-signal.sh
# shellcheck disable=SC2016  # the pretend programs expand their own variables
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
command -v gpg >/dev/null || { echo "  ok    skipped: gpg isn't installed"; exit 0; }

T=$(mktemp -d)
trap 'gpgconf --homedir "$T/gh" --kill all 2>/dev/null; rm -rf "$T"' EXIT
fails=0
check() { # DESCRIPTION CONDITION-COMMAND...
    local what=$1
    shift
    if "$@" >/dev/null 2>&1; then printf '  ok    %s\n' "$what"; else printf '  FAIL  %s\n' "$what"; fails=$((fails + 1)); fi
}
not() { ! "$@"; }

# Two throwaway keys: the "pinned" one, and another
mkdir -m 700 "$T/gh"
for n in good other; do
    gpg --homedir "$T/gh" --batch --quiet --passphrase '' --quick-gen-key "$n <$n@test>" ed25519 sign never 2>/dev/null
    gpg --homedir "$T/gh" --batch --armor --export "$n@test" >"$T/$n.asc"
done
GOOD=$(gpg --show-keys --with-colons "$T/good.asc" | awk -F: '/^fpr/ { print $10; exit }')

mkdir -p "$T/bin" "$T/home" "$T/root"
# sudo: installing a file goes into $T/root; the rest is logged
cat >"$T/bin/sudo" <<EOF
#!/bin/bash
[ "\$1" = -v ] && exit 0
echo "sudo \$*" >>"$T/calls"
case "\$1" in
    install) args=("\$@"); dest=\${args[-1]}; mkdir -p "$T/root\${dest%/*}"; args[-1]="$T/root\$dest"; "\${args[@]}" ;;
    tee) mkdir -p "\$(dirname "$T/root\$2")"; cat >"$T/root\$2" ;;
esac
EOF
# wget -qO FILE URL: the key the "server" has now
cat >"$T/bin/wget" <<EOF
#!/bin/sh
cp "$T/served.asc" "\$2"
EOF
# dpkg-query: every package "installed" (so no download), the marker holding
# nothing yet (so it is built and installed); dpkg-statoverride: none yet
cat >"$T/bin/dpkg-query" <<'EOF'
#!/bin/sh
case "$*" in *Status*) echo 'install ok installed' ;; esac
EOF
printf '#!/bin/sh\nexit 1\n' >"$T/bin/dpkg-statoverride"
chmod +x "$T/bin/"*

R=$T/r
mkdir -p "$R/extras"
sed 's|^export PATH=.*|export PATH="$SIGNAL_TEST_PATH"|' "$HERE/lib.sh" >"$R/lib.sh"
grep -q SIGNAL_TEST_PATH "$R/lib.sh" || { echo "  FAIL  lib.sh's PATH line wasn't found"; exit 1; }
sed "s|^SIGNAL_FPR=.*|SIGNAL_FPR=$GOOD|" "$HERE/pins.sh" >"$R/pins.sh"
for f in packages.sh lib data docs bin; do ln -s "$HERE/$f" "$R/$f"; done
cp "$HERE/extras/signal.sh" "$R/extras/"
export SIGNAL_TEST_PATH="$T/bin:$PATH" HOME=$T/home
[ "$(bash -c '. "$1/lib.sh"; command -v sudo' _ "$R")" = "$T/bin/sudo" ] || { echo "  FAIL  the real sudo would run; stopping"; exit 1; }
run() { : >"$T/calls"; rm -rf "${T:?}/root"; mkdir -p "$T/root"; bash "$R/extras/signal.sh" "$@" >"$T/out" 2>&1; }

cp "$T/other.asc" "$T/served.asc"
run
check "a key that isn't the pinned one: nothing goes in" bash -c '[ -z "$(ls -A "$1/root")" ] && ! grep -q "apt-get install" "$2"' _ "$T" "$T/calls"
cat "$T/good.asc" "$T/other.asc" >"$T/served.asc"
run
check "...nor the pinned key with a second one next to it" not test -e "$T/root/usr/share/keyrings/signal-desktop-keyring.asc"
cp "$T/good.asc" "$T/served.asc"
run
check "the pinned key: it goes in" cmp "$T/good.asc" "$T/root/usr/share/keyrings/signal-desktop-keyring.asc"
check "...the repository, trusted with that key only" \
    grep -qx 'deb \[arch=amd64 signed-by=/usr/share/keyrings/signal-desktop-keyring.asc\] https://updates.signal.org/desktop/apt xenial main' "$T/root/etc/apt/sources.list.d/signal-desktop.list"
check "...updated by unattended-upgrades" grep -q 'site=updates.signal.org' "$T/root/etc/apt/apt.conf.d/52debsway-signal"
check "...the sandbox helper made not setuid, by an override updates keep" grep -qx 'sudo dpkg-statoverride --add root root 0755 /opt/Signal/chrome-sandbox' "$T/calls"
check "...before Signal is installed" \
    bash -c 'o=$(grep -n "dpkg-statoverride --add" "$1" | cut -d: -f1); i=$(grep -n "apt-get install .*debsway-signal.deb" "$1" | cut -d: -f1); [ -n "$o" ] && [ -n "$i" ] && [ "$o" -lt "$i" ]' _ "$T/calls"
printf '#!/bin/sh\necho "/opt/Signal/chrome-sandbox root root 0755"\n' >"$T/bin/dpkg-statoverride"
run --remove
check "--remove: the override, the repository, its key and the update rule go" \
    bash -c 'grep -q "dpkg-statoverride --remove /opt/Signal/chrome-sandbox" "$1" && grep -q "rm -f /etc/apt/sources.list.d/signal-desktop.list /usr/share/keyrings/signal-desktop-keyring.asc" "$1" && grep -q "rm -f /etc/apt/apt.conf.d/52debsway-signal" "$1"' _ "$T/calls"
check "...and Signal, through its marker" grep -q 'apt-get purge -y debsway-signal' "$T/calls"

[ "$fails" -eq 0 ]
