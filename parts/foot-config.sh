#!/bin/bash
# The terminal's look: DejaVu Sans Mono at size 14 (foot's own default is
# small), a black background and readable colours (data/foot.ini). It goes
# to ~/.config/foot/foot.ini, which only affects terminals you open after
# this. A foot.ini you wrote yourself is kept as foot.ini.bak.
# Usage: bash foot-config.sh [--remove]
# status: file:~/.config/foot/foot.ini
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
need_user

CONF="$HOME/.config/foot/foot.ini"
MARK='Written by debsway parts/foot-config.sh'

if [ "${1:-}" = --remove ]; then
    if grep -qs "$MARK" "$CONF"; then
        rm -f "$CONF"
        if [ -f "$CONF.bak" ]; then
            mv "$CONF.bak" "$CONF"
            note "Put your earlier foot.ini back."
        fi
    fi
    apt_purge fonts-dejavu-mono
    exit
fi

say "Installing the terminal font"
apt_install fonts-dejavu-mono

say "foot config"
mkdir -p "${CONF%/*}"
if [ -f "$CONF" ] && ! grep -qs "$MARK" "$CONF" && ! cmp -s "$DEBSWAY_DIR/data/foot.ini" "$CONF"; then
    cp "$CONF" "$CONF.bak"
    note "Your foot.ini is kept as $CONF.bak"
fi
cp "$DEBSWAY_DIR/data/foot.ini" "$CONF"
foot -C -c "$CONF" || warn "foot reports a problem in $CONF"
note "Installed $CONF. New terminals use it (Super+Enter)."
