#!/bin/bash
# Automount USB drives, including LUKS-encrypted ones. udiskie's own
# password prompt needs GTK, so this installs a small one of its own:
# wmenu in password mode if wmenu is installed, else a floating foot window.
# Usage: bash udiskie.sh [--remove]
# summary: USB drives mount by themselves (noexec), LUKS too
# status: apt:udiskie
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
need_user

ASKPASS="$BIN/luks-askpass"
UCONF="$HOME/.config/udiskie/config.yml"
UMARK="# Written by debsway parts/udiskie.sh"
# udiskie runs the prompt without a shell, so the path must be absolute
UDISKIE_CMD="udiskie --no-tray --no-file-manager --password-prompt '$ASKPASS {device_presentation}'"

if [ "${1:-}" = --remove ]; then
    remove_snippet automount
    pkill -x udiskie || true
    remove_bin luks-askpass
    if grep -qxF "$UMARK" "$UCONF" 2>/dev/null; then rm -f "$UCONF"; fi
    # cryptsetup stays: an encrypted system disk needs it to boot
    sudo apt-mark manual cryptsetup >/dev/null
    apt_purge udiskie udisks2 gir1.2-notify-0.7
    exit
fi

# polkitd lets your user mount without sudo; gir1.2-notify-0.7 lets
# udiskie show mount notifications when mako is installed
say "Installing udiskie, udisks2 and cryptsetup"
apt_install udiskie udisks2 cryptsetup polkitd gir1.2-notify-0.7

install_bin luks-askpass

# A stranger's USB stick is mounted the moment it's plugged in, so nothing
# on it may run: no setuid files, no device files, no executables. The
# stick with debsway on it still works, since scripts run as "bash x.sh".
if [ -f "$UCONF" ]; then
    note "Keeping existing $UCONF"
else
    mkdir -p "${UCONF%/*}"
    cat >"$UCONF" <<EOF2
$UMARK
# Mount options for every drive. Delete noexec to run programs from a stick.
mount_options:
  - options: [nosuid, nodev, noexec]
EOF2
    note "Wrote $UCONF (drives mount with nosuid, nodev, noexec)"
fi

put_snippet automount <<EOF
# USB automount (debsway extras/udiskie.sh)
exec $UDISKIE_CMD
for_window [app_id="luks-askpass"] floating enable
EOF

# exec lines only run when sway starts, so start it now if sway is up
if [ -n "${SWAYSOCK:-}" ] && ! pgrep -x udiskie >/dev/null; then
    swaymsg exec "$UDISKIE_CMD" >/dev/null && note "Started udiskie."
fi
note "Drives mount under /media/$(id -un)/. Unmount: udiskie-umount /media/$(id -un)/NAME"
note "Or all at once: udiskie-umount -a"
