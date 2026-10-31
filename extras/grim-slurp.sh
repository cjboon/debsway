#!/bin/bash
# Screenshots. Installs a small ~/.local/bin/screenshot helper and binds:
#   Print / Super+Shift+p   whole screen to ~/Pictures
#   Shift+Print / Super+Shift+s   drag a region to ~/Pictures
#   Ctrl+Print / Super+Shift+x    drag a region to the clipboard
#                                 (needs parts/wl-clipboard.sh, else saves a file)
# Usage: bash grim-slurp.sh [--remove]
# summary: Screenshots: Print and Super+Shift+p keys
# status: apt:grim apt:slurp
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
need_user

if [ "${1:-}" = --remove ]; then
    remove_snippet screenshots
    remove_bin screenshot
    apt_purge grim slurp
    exit
fi

say "Installing grim and slurp"
apt_install grim slurp

install_bin screenshot

# Keyboards without a Print key (Apple, many laptops) get the Super+Shift ones
put_snippet screenshots <<'EOF'
# Screenshots (debsway extras/grim-slurp.sh)
bindsym Print exec ~/.local/bin/screenshot full
bindsym Shift+Print exec ~/.local/bin/screenshot region
bindsym Ctrl+Print exec ~/.local/bin/screenshot clip
bindsym $mod+Shift+p exec ~/.local/bin/screenshot full
bindsym $mod+Shift+s exec ~/.local/bin/screenshot region
bindsym $mod+Shift+x exec ~/.local/bin/screenshot clip
EOF
