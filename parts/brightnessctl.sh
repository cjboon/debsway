#!/bin/bash
# Screen brightness keys. Installs ~/.local/bin/brightness, which never
# goes below 5% (so the screen can't go black) and refreshes the status
# bar right away. Keys: the brightness keys, or Super+F1 / Super+F2.
# Writing to the backlight needs the video group.
# install-base.sh runs this. Usage: bash brightnessctl.sh [--remove]
# status: apt:brightnessctl
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
need_user

if [ "${1:-}" = --remove ]; then
    remove_snippet brightness
    remove_bin brightness
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

install_bin brightness

# Super+F1/F2 for keyboards without brightness keys (Apple F1/F2 send them)
put_snippet brightness <<'EOF'
# Brightness (debsway parts/brightnessctl.sh)
bindsym --locked XF86MonBrightnessDown exec ~/.local/bin/brightness down
bindsym --locked XF86MonBrightnessUp exec ~/.local/bin/brightness up
bindsym $mod+F1 exec ~/.local/bin/brightness down
bindsym $mod+F2 exec ~/.local/bin/brightness up
EOF
note "Brightness keys, or Super+F1 / Super+F2. From a terminal: brightness up 10"
