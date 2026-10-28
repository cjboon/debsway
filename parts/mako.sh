#!/bin/bash
# Desktop notifications. mako starts by itself the first time an app
# sends one, so the sway config only gets keys to dismiss them.
# Usage: bash mako.sh [--remove]
# status: apt:mako-notifier
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
need_user

CONF="$HOME/.config/mako/config"
MARK="# Written by debsway parts/mako.sh"

if [ "${1:-}" = --remove ]; then
    remove_snippet notifications
    if grep -qxF "$MARK" "$CONF" 2>/dev/null; then rm -f "$CONF"; fi
    pkill -x mako || true
    apt_purge mako-notifier libnotify-bin
    exit
fi

# notify-send (libnotify-bin) comes too: the status bar uses it for the
# battery popup, and it's handy for testing and your own scripts.
PKGS=(mako-notifier libnotify-bin)
say "Installing ${PKGS[*]}"
apt_install "${PKGS[@]}"

# mako's default keeps every notification until you click it
if [ -f "$CONF" ]; then
    note "Keeping existing $CONF"
else
    mkdir -p "${CONF%/*}"
    cat >"$CONF" <<EOF
$MARK
# All settings: man 5 mako
default-timeout=5000
EOF
    note "Wrote $CONF (notifications close after 5 seconds)"
fi
if pgrep -x mako >/dev/null; then makoctl reload || true; fi

put_snippet notifications <<'EOF'
# Notifications (debsway parts/mako.sh)
bindsym $mod+n exec makoctl dismiss
bindsym $mod+Shift+n exec makoctl dismiss --all
EOF

note "Super+n dismisses one, Super+Shift+n dismisses all."
if command -v notify-send >/dev/null; then
    note "Test it: notify-send 'Hello' 'mako works'"
fi
