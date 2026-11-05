#!/bin/bash
# Checks tools/try-vps.sh without starting a VM: what it runs in the VM is
# setup-vps.sh exactly as it is here, with the test's choices, and valid bash;
# the VM is reachable from this computer only. Changes nothing outside a temp
# folder. Run by test.sh, or:  bash tools/test-try-vps.sh
# shellcheck disable=SC2016  # the inner shells expand their own variables
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
T=$(mktemp -d) || { echo "  FAIL  couldn't make a temp folder (is /tmp full?)"; exit 1; }
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
check "the VM counts as there by its disk, and one switched off is started first (--status succeeds without one)" bash -c '
    grep -qF "if [ -f \"\$WORK/\$VM.qcow2\" ]; then" "$1" && grep -qF "grep -q '"'"'Running (pid'"'"'" "$1" && grep -q "mock --start" "$1"' _ "$HERE/tools/try-vps.sh"
check "the site is forwarded from this computer's loopback, by QEMU: setup-vps.sh's sshd allows no tunnels" bash -c '
    grep -q "HOST_FORWARDS=127.0.0.1:8080:80" "$1" && grep -q "WEB_TUNNEL=0" "$1" && ! grep -q "SSH tunnel" "$1"' _ "$HERE/tools/try-vps.sh"
check "it confirms the change from a second login, as you would" grep -q 'wren-vps --confirm' "$HERE/tools/try-vps.sh"

# The mockvps-kvm extra: its command may point at another Wren Linux copy's
# script (the package's, after an update): that is its own, and is pointed at
# this copy; a file of yours is left alone
if [ -e /dev/kvm ]; then
    mkdir -p "$T/fake" "$T/mh/.local/bin" "$T/pkg/vendor/mockvps-kvm" "$T/pkg/extras"
    : >"$T/pkg/vendor/mockvps-kvm/mockvps-kvm.sh"; : >"$T/pkg/extras/mockvps-kvm.sh"
    printf '#!/bin/sh\n[ "$1" = -v ] && exit 0\nexit 0\n' >"$T/fake/sudo"
    printf '#!/bin/sh\ncase "$*" in *Status*) echo "install ok installed" ;; *Depends*) echo "qemu-system-x86, qemu-utils, wget, cpio, gzip, openssh-client, gpgv, debian-archive-keyring, socat, iproute2" ;; esac\n' >"$T/fake/dpkg-query"
    chmod +x "$T/fake/"*
    MR=$T/mr
    mkdir -p "$MR/extras" "$MR/lib" "$MR/vendor/mockvps-kvm"
    sed 's|^export PATH=.*|export PATH="$MV_TEST_PATH"|' "$HERE/lib.sh" >"$MR/lib.sh"
    for f in pins.sh packages.sh data bin docs; do ln -s "$HERE/$f" "$MR/$f"; done
    for f in "$HERE"/lib/*; do ln -s "$f" "$MR/lib/${f##*/}"; done
    cp "$HERE/extras/mockvps-kvm.sh" "$MR/extras/"
    cp "$HERE/vendor/mockvps-kvm/mockvps-kvm.sh" "$MR/vendor/mockvps-kvm/"
    mk() { MV_TEST_PATH="$T/fake:$PATH" HOME=$T/mh bash "$MR/extras/mockvps-kvm.sh" >/dev/null 2>&1; }
    ln -sfn "$T/pkg/vendor/mockvps-kvm/mockvps-kvm.sh" "$T/mh/.local/bin/mockvps-kvm"
    mk
    check "mockvps-kvm extra: a command pointing at another Wren Linux copy (the package's) is its own: pointed at this copy" \
        test "$(readlink "$T/mh/.local/bin/mockvps-kvm")" = "$MR/vendor/mockvps-kvm/mockvps-kvm.sh"
    mkdir -p "$T/pkg/extras/mockvps-kvm"; : >"$T/pkg/extras/mockvps-kvm/mockvps-kvm.sh"
    ln -sfn "$T/pkg/extras/mockvps-kvm/mockvps-kvm.sh" "$T/mh/.local/bin/mockvps-kvm"
    mk
    check "...and one at a Wren Linux copy's old place too" test "$(readlink "$T/mh/.local/bin/mockvps-kvm")" = "$MR/vendor/mockvps-kvm/mockvps-kvm.sh"
    rm -f "$T/mh/.local/bin/mockvps-kvm"; printf '#!/bin/sh\necho mine\n' >"$T/mh/.local/bin/mockvps-kvm"
    mk; rc=$?
    check "...a file of yours by that name: refused, and left as it was" bash -c '[ "$1" -ne 0 ] && grep -qx "echo mine" "$2"' _ "$rc" "$T/mh/.local/bin/mockvps-kvm"
    rm -f "$T/mh/.local/bin/mockvps-kvm"; ln -s /bin/true "$T/mh/.local/bin/mockvps-kvm"
    mk; rc=$?
    check "...and so is a link to anything else" bash -c '[ "$1" -ne 0 ] && [ "$(readlink "$2")" = /bin/true ]' _ "$rc" "$T/mh/.local/bin/mockvps-kvm"
fi

[ "$fails" -eq 0 ]
