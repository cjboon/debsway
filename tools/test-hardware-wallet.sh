#!/bin/bash
# Checks extras/hardware-wallet.sh and its rule with a pretend sudo: the rule
# gives the devices to the user at the keyboard only (uaccess: no mode, group
# or program), udev takes it, and it goes in and out. Nothing outside a temp
# folder changes. Run by test.sh, or:  bash tools/test-hardware-wallet.sh
# shellcheck disable=SC2016  # the inner shells and pretend programs expand their own variables
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
RULES=$HERE/data/hardware-wallets.rules

body=$(grep -vE '^[[:space:]]*(#|$)' "$RULES")
check "the rule only ever adds uaccess (no mode, group, owner or program for anyone)" bash -c '
    ! grep -qE "MODE|GROUP|OWNER|RUN|PROGRAM|IMPORT|0666" <<<"$1" && [ "$(grep -c "TAG+=\"uaccess\"" <<<"$1")" = 6 ]' _ "$body"
check "...for Trezor, Ledger, Coldcard, BitBox02 and KeepKey" bash -c '
    for v in "534c" "1209" "2c97" "d13e" "03eb" "2b24"; do grep -q "ATTRS{idVendor}==\"$v\"" <<<"$1" || exit 1; done' _ "$body"
check "...and comes before udev's seat rules apply uaccess (60-, under 73-seat-late)" grep -q '60-wren-hardware-wallets.rules' "$HERE/extras/hardware-wallet.sh"
if command -v udevadm >/dev/null && udevadm verify --help >/dev/null 2>&1; then
    cp "$RULES" "$T/60-x.rules"
    check "...and udev takes it (udevadm verify)" udevadm verify "$T/60-x.rules"
fi

# The extra itself, with a pretend sudo, in a copy of Wren Linux
mkdir -p "$T/bin" "$T/home"
cat >"$T/bin/sudo" <<EOF
#!/bin/bash
echo "sudo \$*" >>"$T/calls"
case \$1 in
    -v | -k | udevadm) exit 0 ;;
    install) shift; args=(); while [ \$# -gt 0 ]; do case \$1 in -o | -g | -m) shift 2 ;; -D) shift ;; *) args+=("\$1"); shift ;; esac; done
             mkdir -p "\$(dirname "\${args[-1]}")" && cp "\${args[0]}" "\${args[-1]}"; exit ;;
esac
exec "\$@"
EOF
chmod +x "$T/bin/sudo"
R=$T/r
mkdir -p "$R/extras" "$R/lib"
sed 's|^export PATH=.*|export PATH="$HW_TEST_PATH"|' "$HERE/lib.sh" >"$R/lib.sh"
grep -q HW_TEST_PATH "$R/lib.sh" || { echo "  FAIL  lib.sh's PATH line wasn't found"; exit 1; }
for f in pins.sh packages.sh data bin docs; do ln -s "$HERE/$f" "$R/$f"; done
for f in "$HERE"/lib/*; do ln -s "$f" "$R/lib/${f##*/}"; done
cp "$HERE/extras/hardware-wallet.sh" "$R/extras/"
export HW_TEST_PATH="$T/bin:$PATH"
hw() { : >"$T/calls"; HOME=$T/home WREN_HW_ROOT=$T/root bash "$R/extras/hardware-wallet.sh" "$@" 2>&1; }
D=$T/root/etc/udev/rules.d/60-wren-hardware-wallets.rules

out=$(hw)
check "installed as root's file, exactly the rule in data/" bash -c 'cmp "$1" "$2" && grep -q "sudo install -D -o root -g root -m 0644" "$3"' _ "$RULES" "$D" "$T/calls"
check "...udev reads it, and looks at the plugged-in devices again" bash -c 'grep -q "sudo udevadm control --reload-rules" "$1" && grep -q "sudo udevadm trigger" "$1"' _ "$T/calls"
check "...and it says what matters most: the device's screen, the recovery words, air-gapped" bash -c '
    grep -q "device.s own screen" <<<"$1" && grep -q "recovery words are the real key" <<<"$1" && grep -q "never connects" <<<"$1"' _ "$out"
out=$(hw --remove)
check "--remove takes the rule out" bash -c '[ ! -e "$1" ] && grep -q "sudo udevadm control --reload-rules" "$2"' _ "$D" "$T/calls"
check "no package is installed for it (no maker's app)" not grep -q 'apt_install' "$HERE/extras/hardware-wallet.sh"

[ "$fails" -eq 0 ]
