#!/bin/bash
# Closing the lid no longer suspends the laptop: it locks the screen (with
# swaylock, part of the base) and turns the laptop's own panel off, while the
# network, downloads and the timer's alarms keep going. An external screen stays
# on. Opening the lid turns the panel back on.
#  - systemd-logind is told to ignore the lid (data/lid-logind.conf, also when
#    plugged in or docked); sway reacts to the lid instead (bin/lid).
#  - A laptop that stays on in a closed bag gets warm and empties its battery:
#    power it off (Super+Shift+Escape) before you pack it.
#  - It is still on, so the disk key is in memory: shut down before leaving it
#    somewhere (see THREAT-MODEL.md).
# Usage: bash lid-awake.sh [--remove]
# summary: Closing the lid locks, but doesn't suspend
# status: file:/etc/systemd/logind.conf.d/60-debsway-lid.conf
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
need_user

CONF=/etc/systemd/logind.conf.d/60-debsway-lid.conf

# logind reads its settings again on SIGHUP; a restart could end the session
reload_logind() { sudo systemctl kill -s HUP systemd-logind >/dev/null 2>&1 || true; }

if [ "${1:-}" = --remove ]; then
    sudo rm -f "$CONF"
    sudo rmdir /etc/systemd/logind.conf.d 2>/dev/null || true
    reload_logind
    remove_snippet lid
    remove_bin lid
    note "Closing the lid suspends the laptop again (Debian's default)."
    exit
fi

has_battery || warn "No battery found: this is for laptops, where the lid suspends. Setting it up anyway."

say "The lid doesn't suspend"
sudo install -D -o root -g root -m 0644 "$DEBSWAY_DIR/data/lid-logind.conf" "$CONF"
reload_logind
note "Wrote $CONF"

say "Closing the lid locks the screen"
install_bin lid
# --locked: it also works while the screen is locked; --reload: right after a reload too
put_snippet lid <<'EOF'
# The lid: lock and panel off, no suspend (debsway extras/lid-awake.sh)
bindswitch --reload --locked lid:on exec ~/.local/bin/lid close
bindswitch --reload --locked lid:off exec ~/.local/bin/lid open
EOF
command -v swaylock >/dev/null ||
    warn "swaylock isn't installed, so closing the lid only turns the panel off: bash parts/swaylock.sh"
note "Closing the lid now locks the screen and turns the panel off; the laptop stays on."
note "Power it off before packing it in a bag (Super+Shift+Escape): it would get warm."
