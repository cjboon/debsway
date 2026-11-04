#!/bin/bash
# mockvps-kvm: spin up a disposable Debian "VPS" on this machine with
# QEMU/KVM, log in with ssh, throw it away with one command. The script
# itself is vendor/mockvps-kvm/mockvps-kvm.sh (see its README.md); this
# installs what it needs and a mockvps-kvm command.
# Usage: bash mockvps-kvm.sh [--remove | --manual]
# summary: Disposable Debian VM for trying out server setups
# security: some
# status: bin:mockvps-kvm
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
if [ "${1:-}" = --manual ]; then print_manual; exit; fi
need_user

SCRIPT="$WREN_DIR/vendor/mockvps-kvm/mockvps-kvm.sh"
CMD="$HOME/.local/bin/mockvps-kvm"
# ours_link: the command is a link to a Wren Linux copy's script (this one, the
# package's in /usr/share/wren, or another; an earlier version's place too):
# that copy has extras/mockvps-kvm.sh beside it
ours_link() {
    local t
    t=$(readlink -- "$CMD") || return 1
    case $t in
        */vendor/mockvps-kvm/mockvps-kvm.sh | */extras/mockvps-kvm/mockvps-kvm.sh) [ -f "${t%/*/*/*}/extras/mockvps-kvm.sh" ] ;;
        *) return 1 ;;
    esac
}

if [ "${1:-}" = --remove ]; then
    if ours_link; then rm -f "$CMD"; fi
    note "Removed the mockvps-kvm command. VMs you made are untouched;"
    note "remove one first with: mockvps-kvm --uninstall   (add -n NAME for others)"
    # QEMU goes too, unless Whonix or another script needs it
    apt_purge
    exit
fi

[ -e /dev/kvm ] || die "No /dev/kvm: turn on virtualization (VT-x / AMD-V) in the firmware settings."

say "Installing QEMU and the tools mockvps-kvm uses"
# gpgv + debian-archive-keyring: it checks Debian's netboot files against
# Debian's signed release file. socat: clean shutdowns. iproute2: ss.
apt_install qemu-system-x86 qemu-utils wget cpio gzip openssh-client \
    gpgv debian-archive-keyring socat iproute2
# (id -nG NAME: your account's groups; plain id -nG: this session's, which
# take a new group only at the next login)
if ! id -nG "$(id -un)" | grep -qw kvm; then
    sudo adduser "$(id -un)" kvm >/dev/null
    warn "Added you to the kvm group. Log out and back in once (mockvps-kvm also works until then)."
elif ! id -nG | grep -qw kvm; then
    note "You are in the kvm group; it takes effect at your next login (mockvps-kvm also works until then)."
fi

mkdir -p "$(dirname -- "$CMD")"
if { [ -e "$CMD" ] || [ -L "$CMD" ]; } && ! ours_link; then
    die "$CMD already exists and isn't Wren Linux's; leaving it."
fi
ln -sfn "$SCRIPT" "$CMD"
# (the Wren Linux package's copy is root's, and executable already)
[ -x "$SCRIPT" ] || chmod +x "$SCRIPT"

cat <<'EOF'

    How to use mockvps-kvm (full guide: vendor/mockvps-kvm/README.md):
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
