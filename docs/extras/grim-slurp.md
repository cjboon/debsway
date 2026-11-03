# Screenshots (`extras/grim-slurp.sh`)

## SYNOPSIS

```
wrenctl install grim-slurp                     install it
wrenctl remove grim-slurp                      remove it
wrenctl manual grim-slurp                      print the manual steps below

Print        or Super+Shift+p   the whole screen, to ~/Pictures
Shift+Print  or Super+Shift+s   drag a region, to ~/Pictures
Ctrl+Print   or Super+Shift+x   drag a region, to the clipboard
screenshot full|region|clip     the same from a terminal
```

Screenshots for sway: grim takes them and slurp lets you drag a region, both
from Debian. A small `screenshot` command (`bin/screenshot`, in
`~/.local/bin`) names the file by date in `~/Pictures`, or puts the picture on
the clipboard (that needs `parts/wl-clipboard.sh`, which the base install
has). sway gets the keys above, with Super+Shift ones for keyboards without a
Print key.

## LIMITS

- A screenshot of a seed, a password or a chat stays in `~/Pictures` until you delete it.
- Any window can be captured, `incognito` included.
- Anything running as you can read `~/Pictures`.

## MANUAL INSTALL

```
# grim takes the picture, slurp picks the region
sudo apt install --no-install-recommends grim slurp
# The screenshot command
install -D -m 0755 @WREN_DIR@/bin/screenshot ~/.local/bin/screenshot
# The keys, in a file sway's config includes (~/.config/sway/config.d/*.conf)
mkdir -p ~/.config/sway/config.d
cat >~/.config/sway/config.d/screenshots.conf <<'EOF'
bindsym Print exec ~/.local/bin/screenshot full
bindsym Shift+Print exec ~/.local/bin/screenshot region
bindsym Ctrl+Print exec ~/.local/bin/screenshot clip
bindsym $mod+Shift+p exec ~/.local/bin/screenshot full
bindsym $mod+Shift+s exec ~/.local/bin/screenshot region
bindsym $mod+Shift+x exec ~/.local/bin/screenshot clip
EOF
# sway must accept it (this prints no [ERROR] lines), then reads it
sway -C -c ~/.config/sway/config 2>&1 | grep ERROR
swaymsg reload
```

To undo:

```
# The keys
rm ~/.config/sway/config.d/screenshots.conf
swaymsg reload
# The command
rm ~/.local/bin/screenshot
# grim and slurp
sudo apt purge grim slurp
```
