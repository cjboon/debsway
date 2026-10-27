#!/bin/bash
# Screen brightness keys. Installs ~/.local/bin/brightness, which never
# goes below 5% (so the screen can't go black) and refreshes the status
# bar right away. Keys: the brightness keys, or Super+F1 / Super+F2.
# Writing to the backlight needs the video group.
# install-base.sh runs this. Usage: bash brightnessctl.sh [--remove]
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
need_user

HELPER="$HOME/.local/bin/brightness"

if [ "${1:-}" = --remove ]; then
    remove_snippet brightness
    rm -f "$HELPER"
    apt_purge brightnessctl
    exit
fi

say "Installing brightnessctl"
apt_install brightnessctl

if id -nG | tr ' ' '\n' | grep -qx video; then
    note "You're in the video group."
else
    sudo adduser "$(id -un)" video
    warn "Added you to the video group. Log out and back in for the keys to work."
fi

mkdir -p "${HELPER%/*}"
cat >"$HELPER" <<'EOF'
#!/bin/sh
# brightness up|down [STEP]: written by debsway parts/brightnessctl.sh
# Changes screen brightness by STEP percent (default 5), never below 5%,
# then tells sway-status to redraw the bar.
step=${2:-5}
cur=$(brightnessctl -m | cut -d, -f4 | tr -d %)
case $1 in
    up) new=$((cur + step)); [ "$new" -le 100 ] || new=100 ;;
    down) new=$((cur - step)); [ "$new" -ge 5 ] || new=5 ;;
    *) echo "usage: brightness up|down [STEP]" >&2; exit 2 ;;
esac
brightnessctl -q set "$new%"
# Only signal it if that PID really is sway-status (a stale file could
# point at an unrelated process, which SIGUSR1 would kill)
pid=$(cat "${XDG_RUNTIME_DIR:-/tmp}/sway-status.pid" 2>/dev/null)
if [ -n "$pid" ] && tr '\0' ' ' <"/proc/$pid/cmdline" 2>/dev/null | grep -q sway-status; then
    kill -USR1 "$pid" 2>/dev/null
fi
exit 0
EOF
chmod +x "$HELPER"
note "Wrote $HELPER"

# Super+F1/F2 for keyboards without brightness keys (Apple F1/F2 send them)
put_snippet brightness <<'EOF'
# Brightness (debsway parts/brightnessctl.sh)
bindsym --locked XF86MonBrightnessDown exec ~/.local/bin/brightness down
bindsym --locked XF86MonBrightnessUp exec ~/.local/bin/brightness up
bindsym $mod+F1 exec ~/.local/bin/brightness down
bindsym $mod+F2 exec ~/.local/bin/brightness up
EOF
note "Brightness keys, or Super+F1 / Super+F2. From a terminal: brightness up 10"
