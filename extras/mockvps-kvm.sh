#!/bin/bash
# mockvps-kvm: spin up a disposable Debian "VPS" on this machine with
# QEMU/KVM, log in with ssh, throw it away with one command. The script
# itself is extras/mockvps-kvm/mockvps-kvm.sh (see its README.md); this
# installs what it needs and a mockvps-kvm command.
# Usage: bash mockvps-kvm.sh [--remove]
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
need_user

SCRIPT="$DEBSWAY_DIR/extras/mockvps-kvm/mockvps-kvm.sh"
CMD="$HOME/.local/bin/mockvps-kvm"

if [ "${1:-}" = --remove ]; then
    if [ "$(readlink -- "$CMD")" = "$SCRIPT" ]; then rm -f "$CMD"; fi
    note "Removed the mockvps-kvm command. VMs you made are untouched;"
    note "remove one first with: mockvps-kvm --uninstall   (add -n NAME for others)"
    note "QEMU is kept, since other VMs (e.g. Whonix) may use it."
    exit
fi

[ -e /dev/kvm ] || die "No /dev/kvm: turn on virtualization (VT-x / AMD-V) in the firmware settings."

say "Installing QEMU and the tools mockvps-kvm uses"
# gpgv + debian-archive-keyring: it checks Debian's netboot files against
# Debian's signed release file. socat: clean shutdowns. iproute2: ss.
apt_install qemu-system-x86 qemu-utils wget cpio gzip openssh-client \
    gpgv debian-archive-keyring socat iproute2
if ! id -nG | grep -qw kvm; then
    sudo adduser "$(id -un)" kvm >/dev/null
    warn "Added you to the kvm group. Log out and back in once (mockvps-kvm also works until then)."
fi

mkdir -p "$(dirname -- "$CMD")"
if [ -e "$CMD" ] && [ "$(readlink -- "$CMD")" != "$SCRIPT" ]; then
    die "$CMD already exists and isn't debsway's; leaving it."
fi
ln -sfn "$SCRIPT" "$CMD"
chmod +x "$SCRIPT"

cat <<'EOF'

    How to use mockvps-kvm (full guide: extras/mockvps-kvm/README.md):
      mockvps-kvm                    install a fresh Debian VM (5-15 min)
      ssh mockvps-kvm                log in to it (key only)
      mockvps-kvm --status | --stop | --start
      mockvps-kvm --snapshot clean   save the disk; --restore clean goes back
      mockvps-kvm -P nginx --provision setup.sh
                                     extra packages, then your script as root
      mockvps-kvm --uninstall        delete the VM and every trace of it
    While "ssh mockvps-kvm" is open, http://localhost:8080 shows the VM's
    port 80. Nothing is reachable from your network.
EOF
