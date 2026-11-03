#!/bin/bash
# GRUB's boot menu in Wren Linux's colours: white text on red, the chosen entry
# yellow. A small script in /etc/grub.d that update-grub runs (as root, like
# the others there) when it builds the menu; it comes after Debian's own
# colours (05_debian_theme), so these win. Colours only: what boots, and how,
# doesn't change. It needs GRUB.
# Usage: bash grub-colors.sh [--remove]
# status: file:/etc/grub.d/06_wren_colors
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
need_user

# WREN_GRUB_D: where /etc/grub.d is, for tests
SCRIPT=${WREN_GRUB_D:-/etc/grub.d}/06_wren_colors

if [ "${1:-}" = --remove ]; then
    sudo rm -f "$SCRIPT"
    if command -v update-grub >/dev/null; then sudo update-grub; fi
    note "GRUB has Debian's colours again."
    exit
fi

if ! command -v update-grub >/dev/null || [ ! -d "${SCRIPT%/*}" ]; then
    note "This system doesn't boot with GRUB, so nothing was changed."
    exit 0
fi

say "GRUB's colours"
printf '%s\n' '#!/bin/sh' '# Written by Wren Linux parts/grub-colors.sh' \
    "echo 'set color_normal=white/red'" \
    "echo 'set color_highlight=yellow/red'" \
    "echo 'set menu_color_normal=white/red'" \
    "echo 'set menu_color_highlight=yellow/red'" |
    sudo tee "$SCRIPT" >/dev/null
sudo chmod 755 "$SCRIPT"
# If GRUB can't build its menu with it, take it out again
if ! sudo update-grub; then
    sudo rm -f "$SCRIPT"
    sudo update-grub || true
    die "update-grub failed with the new colours, so they were removed."
fi
note "GRUB shows them from the next boot on."
