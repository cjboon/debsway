# The lid locks, but doesn't suspend (`extras/lid-awake.sh`)

## SYNOPSIS

```
debsway install lid-awake                     set it up
debsway remove lid-awake                      closing the lid suspends again
debsway manual lid-awake                      print the manual steps below

close the lid     the screen locks and the laptop's panel goes off; everything keeps running
open the lid      the panel comes back on (unlock as usual)
Super+Shift+Escape   power it off before you pack it in a bag
```

Debian suspends a laptop when its lid closes. With this, closing the lid
locks the screen (swaylock, part of the base install) and turns the laptop's
own panel off, while the network, downloads and the timer's alarms keep going;
an external screen stays on. systemd-logind is told to ignore the lid, also
when plugged in or docked (`data/lid-logind.conf`), and sway reacts to it
instead, through `bin/lid`.

## LIMITS

- A laptop left on in a closed bag gets warm and empties its battery.
- It's still on, so the disk's key is in memory: shut it down before leaving it anywhere.
- The screen lock is only as good as your password.

## MANUAL INSTALL

```
# systemd-logind ignores the lid (on battery, plugged in and docked)
sudo install -D -o root -g root -m 0644 @DEBSWAY_DIR@/data/lid-logind.conf /etc/systemd/logind.conf.d/60-debsway-lid.conf
# logind reads it again on a HUP signal (a restart could end your session)
sudo systemctl kill -s HUP systemd-logind

# The lid command sway runs: lock and panel off, or panel on
install -D -m 0755 @DEBSWAY_DIR@/bin/lid ~/.local/bin/lid
# sway runs it when the lid closes or opens, also while locked
mkdir -p ~/.config/sway/config.d
cat >~/.config/sway/config.d/lid.conf <<'EOF'
bindswitch --reload --locked lid:on exec ~/.local/bin/lid close
bindswitch --reload --locked lid:off exec ~/.local/bin/lid open
EOF
# sway must accept it (this prints no [ERROR] lines), then reads it
sway -C -c ~/.config/sway/config 2>&1 | grep ERROR
swaymsg reload
```

To undo:

```
# logind suspends on the lid again
sudo rm /etc/systemd/logind.conf.d/60-debsway-lid.conf
sudo systemctl kill -s HUP systemd-logind
# sway no longer reacts to the lid
rm ~/.config/sway/config.d/lid.conf ~/.local/bin/lid
swaymsg reload
```
