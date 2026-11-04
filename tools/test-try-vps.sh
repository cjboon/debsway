#!/bin/bash
# Checks tools/try-vps.sh without starting a VM: what it runs in the VM is
# setup-vps.sh exactly as it is here, with the test's choices, and valid bash;
# the VM is reachable from this computer only. Changes nothing outside a temp
# folder. Run by test.sh, or:  bash tools/test-try-vps.sh
# shellcheck disable=SC2016  # the inner shells expand their own variables
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
fails=0
check() { # DESCRIPTION CONDITION-COMMAND...
    local what=$1
    shift
    if "$@" >/dev/null 2>&1; then printf '  ok    %s\n' "$what"; else printf '  FAIL  %s\n' "$what"; fails=$((fails + 1)); fi
}
export HOME=$T/home
mkdir -p "$HOME"
CLIENT=ABCDEFGHIJKLMNOPQRSTUVWXYZ234567ABCDEFGHIJKLMNOPQRST
bash "$HERE/tools/try-vps.sh" --print-provision "$CLIENT" >"$T/p.sh"
check "what runs in the VM is valid bash" bash -n "$T/p.sh"
sed -n "/^cat >\/root\/setup-vps.sh <<'WREN_TRY_VPS_SETUP'$/,/^WREN_TRY_VPS_SETUP$/p" "$T/p.sh" | sed '1d;$d' >"$T/copy.sh"
check "...setup-vps.sh exactly as it is in this copy" cmp "$T/copy.sh" "$HERE/tools/setup-vps.sh"
check "...run with the VM's user and key, no domain, both onion services, the test's client key, --yes" bash -c '
    grep -q "VPS_SSH_KEY=\$(head -n1 /home/vps/.ssh/authorized_keys) VPS_ADMIN=vps VPS_DOMAIN= VPS_ONION_SITE=yes VPS_ONION_SSH=yes VPS_ONION_SSH_CLIENT=$2 VPS_CONFIRM_MINUTES=30 bash /root/setup-vps.sh --yes" "$1"' _ "$T/p.sh" "$CLIENT"
check "the VM's SSH and site only on this computer's loopback (never -k, no other address)" bash -c '
    ! grep -qE -- "(^|[[:space:]])(-k|--ip)([[:space:]]|$)" "$1" && grep -q "vps@127.0.0.1" "$1"' _ "$HERE/tools/try-vps.sh"
check "without the mockvps-kvm extra it says to set that up first" bash -c '
    [ ! -e /dev/kvm ] && exit 0; out=$(HOME=$1 bash "$2/tools/try-vps.sh" 2>&1); grep -q "wrenctl install mockvps-kvm" <<<"$out"' _ "$T/home" "$HERE"
check "...and runs the VM through that command (the vendored script refuses to run directly)" grep -q '^MOCK=$HOME/.local/bin/mockvps-kvm$' "$HERE/tools/try-vps.sh"
check "the extra doesn't chmod a script it can't change (the package's copy is root's)" grep -q '^\[ -x "\$SCRIPT" \] || chmod +x "\$SCRIPT"$' "$HERE/extras/mockvps-kvm.sh"
check "it confirms the change from a second login, as you would" grep -q 'wren-vps --confirm' "$HERE/tools/try-vps.sh"

[ "$fails" -eq 0 ]
