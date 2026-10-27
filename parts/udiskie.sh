#!/bin/bash
# Automount USB drives, including LUKS-encrypted ones. udiskie's own
# password prompt needs GTK, so this installs a small one of its own:
# wmenu in password mode if wmenu is installed, else a floating foot window.
# Usage: bash udiskie.sh [--remove]
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
need_user

ASKPASS="$HOME/.local/bin/luks-askpass"
# udiskie runs the prompt without a shell, so the path must be absolute
UDISKIE_CMD="udiskie --no-tray --no-file-manager --password-prompt '$ASKPASS {device_presentation}'"

if [ "${1:-}" = --remove ]; then
    remove_snippet automount
    pkill -x udiskie || true
    rm -f "$ASKPASS"
    # cryptsetup stays: an encrypted system disk needs it to boot
    apt_purge udiskie udisks2 gir1.2-notify-0.7
    exit
fi

# polkitd lets your user mount without sudo; gir1.2-notify-0.7 lets
# udiskie show mount notifications when mako is installed
say "Installing udiskie, udisks2 and cryptsetup"
apt_install udiskie udisks2 cryptsetup polkitd gir1.2-notify-0.7

mkdir -p "${ASKPASS%/*}"
cat >"$ASKPASS" <<'EOF'
#!/bin/sh
# luks-askpass DEVICE: asks for a LUKS password and prints it for udiskie.
# Written by debsway parts/udiskie.sh
prompt="Password for $1:"
if command -v wmenu >/dev/null; then
    exec wmenu -P -p "$prompt" </dev/null
fi
# No wmenu: ask in a foot window, pass the answer back in a private file
f=$(mktemp) || exit 1
trap 'rm -f "$f"' EXIT
foot --app-id=luks-askpass --title="Unlock $1" sh -c '
    printf "%s " "$1"
    stty -echo; read -r p; stty echo
    printf "%s" "$p" >"$2"' sh "$prompt" "$f"
[ -s "$f" ] || exit 1
cat "$f"
EOF
chmod +x "$ASKPASS"
note "Wrote $ASKPASS"

put_snippet automount <<EOF
# USB automount (debsway parts/udiskie.sh)
exec $UDISKIE_CMD
for_window [app_id="luks-askpass"] floating enable
EOF

# exec lines only run when sway starts, so start it now if sway is up
if [ -n "${SWAYSOCK:-}" ] && ! pgrep -x udiskie >/dev/null; then
    swaymsg exec "$UDISKIE_CMD" >/dev/null && note "Started udiskie."
fi
note "Drives mount under /media/$(id -un)/. Unmount: udiskie-umount /media/$(id -un)/NAME"
note "Or all at once: udiskie-umount -a"
