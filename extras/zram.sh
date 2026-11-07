#!/bin/bash
# Compressed swap kept in memory (zram), for a computer short of memory: what hasn't been used for
# a while is squeezed, which leaves room, often twice as much for what is squeezed. It covers
# everything here, your VMs' memory too. Nothing goes to disk, and it is gone at power off, unlike a
# swap file, which would leave passwords and keys on the disk for a while.
#  - systemd-zram-generator, Debian's package, set to half of memory (data/zram-generator.conf).
#  - Set it up on this computer, not inside a VM: the same memory would be squeezed twice.
#  - It isn't free memory: it takes some CPU, and video or encrypted data hardly squeezes. When
#    memory really runs out, things get slow before anything is killed. The bar still warns.
# Usage: bash zram.sh [--remove | --manual]
# summary: Compressed memory, for more room, nothing on disk
# security: some
# status: file:/etc/systemd/zram-generator.conf
# files: data/zram-generator.conf
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
if [ "${1:-}" = --manual ]; then print_manual; exit; fi
need_user

CONF=/etc/systemd/zram-generator.conf

if [ "${1:-}" = --remove ]; then
    if grep -qs '^/dev/zram0 ' /proc/swaps; then
        # Its contents go back to memory: refused, and nothing is lost, if they don't fit
        sudo swapoff /dev/zram0 || die "There isn't room in memory for what it holds. Close something and run this again."
    fi
    sudo systemctl stop systemd-zram-setup@zram0.service 2>/dev/null || true
    sudo rm -f "$CONF"
    apt_purge systemd-zram-generator
    sudo systemctl daemon-reload
    note "zram is off."
    exit
fi

say "Compressed memory"
apt_install systemd-zram-generator
sudo install -o root -g root -m 0644 "$WREN_DIR/data/zram-generator.conf" "$CONF"
sudo systemctl daemon-reload
sudo systemctl restart systemd-zram-setup@zram0.service ||
    die "It didn't start. This says why: systemctl status systemd-zram-setup@zram0"
# (swap comes on just after the device is ready: the generator's own unit)
sudo systemctl start dev-zram0.swap 2>/dev/null || true
grep -qs '^/dev/zram0 ' /proc/swaps || die "It started but isn't in use. This says why: systemctl status systemd-zram-setup@zram0"
note "On, now and at every boot. To see it: zramctl"
