#!/bin/bash
# Screen brightness keys. Installs ~/.local/bin/brightness, which never
# goes below 5% (so the screen can't go black) and refreshes the status
# bar right away. Keys: the brightness keys, or Super+F1 / Super+F2.
# Writing to the backlight needs a group that owns the brightness file and a
# udev rule that makes it group-writable (the file is root-only by default,
# and Debian's brightnessctl sets up neither). We use a dedicated "backlight"
# group, NOT the broad "video" group (which would also grant the webcam and
# more), so you get brightness control and nothing else.
# install-base.sh runs this. Usage: bash brightnessctl.sh [--remove]
# status: apt:brightnessctl
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
need_user

RULE=/etc/udev/rules.d/90-debsway-backlight.rules

if [ "${1:-}" = --remove ]; then
    remove_snippet brightness
    remove_bin brightness
    sudo rm -f "$RULE"
    sudo udevadm control --reload-rules 2>/dev/null || true
    # The dedicated group existed only for this; remove it if it's still around
    if getent group backlight >/dev/null; then sudo groupdel backlight 2>/dev/null || true; fi
    apt_purge brightnessctl
    exit
fi

say "Installing brightnessctl"
apt_install brightnessctl

# A dedicated group just for the backlight, so you get brightness control
# without the broad "video" group (which would also grant the webcam, the
# GPU card node and the framebuffer to anything running as you).
getent group backlight >/dev/null || sudo groupadd -r backlight
if id -nG | tr ' ' '\n' | grep -qx backlight; then
    note "You're in the backlight group."
else
    sudo adduser "$(id -un)" backlight >/dev/null
    warn "Added you to the backlight group. Log out and back in for brightness to work."
fi

say "Letting the backlight group change the backlight"
# The brightness file in /sys is root-only by default. This rule hands each
# backlight's brightness file to the backlight group, group-writable, whenever
# it appears at boot.
printf '%s\n' \
    '# Written by debsway parts/brightnessctl.sh. Let the backlight group change' \
    '# screen brightness (the sysfs file is owned by root, read-only, otherwise).' \
    'ACTION=="add", SUBSYSTEM=="backlight", RUN+="/bin/chgrp backlight /sys/class/backlight/%k/brightness", RUN+="/bin/chmod g+w /sys/class/backlight/%k/brightness"' |
    sudo tee "$RULE" >/dev/null
sudo udevadm control --reload-rules 2>/dev/null || true
sudo udevadm trigger --subsystem-match=backlight --action=add 2>/dev/null || true
# Apply to the backlight that's already present, so it works without a reboot
for b in /sys/class/backlight/*/brightness; do
    [ -e "$b" ] || continue
    sudo chgrp backlight "$b" && sudo chmod g+w "$b" || true
done
note "The backlight is writable by the backlight group (rule: $RULE)."

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
