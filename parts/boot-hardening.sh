#!/bin/bash
# Kernel boot parameters from Kicksecure's list, added to GRUB:
#   slab_nomerge init_on_alloc=1 init_on_free=1 page_alloc.shuffle=1
#   randomize_kstack_offset=on vsyscall=none debugfs=off
# Memory is cleared when it is handed out and freed (init_on_free costs a
# few percent of speed, and leaves less behind in RAM), allocator layouts are
# harder to predict, the old vsyscall page is gone, and debugfs is off (so
# tools that read it, like powertop and perf probes, stop working).
# It needs GRUB and a reboot; check afterwards with: cat /proc/cmdline
# Usage: bash boot-hardening.sh [--remove]
# status: file:/etc/default/grub.d/60-debsway-hardening.cfg
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
need_user

CONF=/etc/default/grub.d/60-debsway-hardening.cfg
PARAMS='slab_nomerge init_on_alloc=1 init_on_free=1 page_alloc.shuffle=1 randomize_kstack_offset=on vsyscall=none debugfs=off'

if [ "${1:-}" = --remove ]; then
    sudo rm -f "$CONF"
    if command -v update-grub >/dev/null; then sudo update-grub; fi
    note "The parameters are gone from the next boot on."
    exit
fi

if ! command -v update-grub >/dev/null || [ ! -d /etc/default/grub.d ]; then
    note "This system doesn't boot with GRUB, so nothing was changed. To get the same"
    note "hardening, add these to your kernel command line yourself:"
    note "  $PARAMS"
    exit 0
fi

say "Boot parameters"
printf '%s\n' "# Written by debsway parts/boot-hardening.sh" \
    "GRUB_CMDLINE_LINUX_DEFAULT=\"\$GRUB_CMDLINE_LINUX_DEFAULT $PARAMS\"" |
    sudo tee "$CONF" >/dev/null
# If GRUB can't build its menu with it, take it out again
if ! sudo update-grub; then
    sudo rm -f "$CONF"
    sudo update-grub || true
    die "update-grub failed with the new parameters, so they were removed."
fi
note "Added to $CONF. They apply after a reboot."
warn "Reboot to use them. If the system doesn't start, pick the entry and press e in GRUB to"
warn "delete them from the command line once, then run: bash parts/boot-hardening.sh --remove"
