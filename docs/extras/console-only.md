# Console-only: tmux instead of sway (`extras/console-only.sh`)

## SYNOPSIS

```
bash ~/debsway/extras/console-only.sh            log in to tmux from now on (from sway, it leaves sway)
bash ~/debsway/extras/console-only.sh --remove   log in to sway again (from tmux, it starts sway)
bash ~/debsway/extras/console-only.sh --manual   print the manual steps below

Alt+1 ... Alt+0      workspace 1 ... 10 (Alt+Shift+1 ... sends the pane)
Alt+Enter / Alt+v    split beside / below     Alt+h j k l or arrows: move
Alt+f fullscreen the pane   Alt+Shift+q close it   Alt+m the debsway menu
Alt+t timers   Alt+? keys   Alt+w Wi-Fi   Alt+- Alt+= volume   Alt+, Alt+. brightness
sway                 start the desktop by hand
```

A login on a text console then goes straight into tmux, with the bar and keys
of the sway desktop (Alt where sway uses Super), instead of starting sway.
Only the login changes: sway stays installed. The tmux look comes with the
base install (`parts/console-tmux.sh`), and the login loop debsway put in
`~/.profile` starts whatever `~/.config/debsway/login` names: `sway` or
`console`. When that file changes while one is running, the loop starts the
other.

## LIMITS

- A text console has no mouse (over ssh, the bar's items still click).
- Programs that need a graphical window won't open until you start sway.

## MANUAL INSTALL

```
# The tmux look, if it isn't there yet (the base install has it):
# tmux, the bar's helpers and the config
sudo apt install --no-install-recommends tmux
for c in sway-status console-click console-font; do install -D -m 0755 @DEBSWAY_DIR@/bin/$c ~/.local/bin/$c; done
mkdir -p ~/.config/tmux ~/.local/share/debsway
cp @DEBSWAY_DIR@/data/tmux.conf ~/.config/tmux/tmux.conf
cp @DEBSWAY_DIR@/data/tmux-console.conf ~/.config/tmux/console.conf
install -m 0644 @DEBSWAY_DIR@/data/keys-console.txt ~/.local/share/debsway/keys-console.txt

# Log in to tmux: the login loop in ~/.profile reads this file
# (it must have the "debsway autostart" block: grep shows it)
grep -n 'debsway autostart' ~/.profile
mkdir -p ~/.config/debsway
echo console >~/.config/debsway/login
# From inside sway, leaving it now starts tmux
swaymsg exit
```

To undo:

```
# Log in to sway again; from inside tmux, detaching starts it
echo sway >~/.config/debsway/login
tmux detach-client
```
