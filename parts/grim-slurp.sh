#!/bin/bash
# Screenshots. Installs a small ~/.local/bin/screenshot helper and binds:
#   Print / Super+Shift+p   whole screen to ~/Pictures
#   Shift+Print / Super+Shift+s   drag a region to ~/Pictures
#   Ctrl+Print / Super+Shift+x    drag a region to the clipboard
#                                 (needs parts/wl-clipboard.sh, else saves a file)
# Usage: bash grim-slurp.sh [--remove]
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
need_user

HELPER="$HOME/.local/bin/screenshot"

if [ "${1:-}" = --remove ]; then
    remove_snippet screenshots
    rm -f "$HELPER"
    apt_purge grim slurp
    exit
fi

say "Installing grim and slurp"
apt_install grim slurp

mkdir -p "${HELPER%/*}"
cat >"$HELPER" <<'EOF'
#!/bin/sh
# screenshot [full|region|clip]: written by debsway parts/grim-slurp.sh
dir=$HOME/Pictures
mkdir -p "$dir"
file=$dir/screenshot-$(date +%F_%H-%M-%S).png

case ${1:-full} in
    full) grim "$file" ;;
    region)
        geo=$(slurp) || exit 0
        grim -g "$geo" "$file" ;;
    clip)
        geo=$(slurp) || exit 0
        if command -v wl-copy >/dev/null; then
            grim -g "$geo" - | wl-copy -t image/png
        else
            grim -g "$geo" "$file"
        fi ;;
    *) echo "usage: screenshot [full|region|clip]" >&2; exit 2 ;;
esac
EOF
chmod +x "$HELPER"
note "Wrote $HELPER"

# Keyboards without a Print key (Apple, many laptops) get the Super+Shift ones
put_snippet screenshots <<'EOF'
# Screenshots (debsway parts/grim-slurp.sh)
bindsym Print exec ~/.local/bin/screenshot full
bindsym Shift+Print exec ~/.local/bin/screenshot region
bindsym Ctrl+Print exec ~/.local/bin/screenshot clip
bindsym $mod+Shift+p exec ~/.local/bin/screenshot full
bindsym $mod+Shift+s exec ~/.local/bin/screenshot region
bindsym $mod+Shift+x exec ~/.local/bin/screenshot clip
EOF
