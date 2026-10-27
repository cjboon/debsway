#!/bin/bash
# Kernel and network hardening settings (data/sysctl-hardening.conf), in the
# spirit of Kicksecure: hide kernel addresses, only trace your own child
# programs, no kexec, Magic SysRq limited to the secure attention key,
# stricter file and network defaults. They apply now and at every boot.
# Side effects: gdb and strace can't attach to a running program without
# sudo; the SysRq REISUB rescue sequence needs kernel.sysrq = 438 again.
# Edit /etc/sysctl.d/60-debsway-hardening.conf to change one.
# Usage: bash sysctl-hardening.sh [--remove]
# status: file:/etc/sysctl.d/60-debsway-hardening.conf
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
need_user

CONF=/etc/sysctl.d/60-debsway-hardening.conf

if [ "${1:-}" = --remove ]; then
    sudo rm -f "$CONF"
    note "The settings go back to Debian's defaults at the next boot."
    exit
fi

say "Kernel and network hardening"
sudo install -o root -g root -m 0644 "$DEBSWAY_DIR/data/sysctl-hardening.conf" "$CONF"
# Applies the file now; a setting this kernel lacks is reported, not fatal
if sudo sysctl -p "$CONF" >/dev/null; then
    note "Applied $CONF (and at every boot)."
else
    warn "Some settings couldn't be applied now; the others were. See: sudo sysctl -p $CONF"
fi
