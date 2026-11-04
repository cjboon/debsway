# The startup watch (`extras/startup-watch.sh`)

## SYNOPSIS

```
wrenctl install startup-watch      set it up (takes a record of your startup files as they are)
wrenctl remove startup-watch       take it out
wrenctl manual startup-watch       print the manual steps below

wren-watch                         what changed since you last accepted
sudo wren-watch diff               the changes themselves
sudo wren-watch accept [FILE...]   take them as yours (all, or those files)
```

A program running as you that wants to start again at every login has to
change one of a few files: your shell's startup files (`~/.profile`,
`~/.bashrc`, ...), sway's config, `~/.config/autostart`, systemd user units,
`~/.local/bin`, mako's config, `.desktop` files and default apps, Wren Linux's
on-lock programs, `~/.ssh/config`, `rc` and `authorized_keys`, and git's and
gpg-agent's settings (`wren-watch --help` lists them). This keeps their
fingerprints, and a copy of each text file, where nothing running as you can
change them: root's, in `/var/lib/wren-watch`. A root timer compares them at
boot and every 15 minutes, following no link and reading regular files only,
and writes what changed where you can read it but not change it. The bar then
shows "startup changed", with a notification; a click shows the list and the
changes. `sudo wren-watch accept` takes them as yours, with your password, so
a program running as you can't accept its own change without it. `wrenctl
install`, `part`, `remove` and `update` take what their own run changed as Wren
Linux's, except a file that had changed before the run, which is left for you.

## LIMITS

- It notices, it doesn't prevent: the change is made, and works, until you see it and undo it.
- It sees only the files it watches. A program can also start from a file it doesn't watch, or run on in memory until you log out.
- Up to 15 minutes pass before a change shows (and until the next login, if you log out first).
- What a change made while `wrenctl` runs, to a file that run also changes, is taken with it.

## MANUAL INSTALL

```
sudo apt install --no-install-recommends python3 diffutils
sudo install -o root -g root -m 0755 @WREN_DIR@/bin/wren-watch /usr/local/bin/wren-watch
# root's check, at boot and every 15 minutes: it may write only its record and list
printf '%s\n' '[Unit]' 'Description=Wren Linux: compare the startup files with their record' '' \
    '[Service]' 'Type=oneshot' 'ExecStart=/usr/local/bin/wren-watch check-all' \
    'ProtectSystem=strict' 'ReadWritePaths=/var/lib/wren-watch /run/wren-watch' 'ProtectHome=read-only' \
    'PrivateTmp=yes' 'PrivateNetwork=yes' 'NoNewPrivileges=yes' 'RuntimeDirectory=wren-watch' \
    'RuntimeDirectoryPreserve=yes' 'StateDirectory=wren-watch' | sudo tee /etc/systemd/system/wren-watch.service
printf '%s\n' '[Unit]' 'Description=Wren Linux: compare the startup files every 15 minutes' '' \
    '[Timer]' 'OnBootSec=1min' 'OnUnitActiveSec=15min' '' '[Install]' 'WantedBy=timers.target' |
    sudo tee /etc/systemd/system/wren-watch.timer
sudo systemctl daemon-reload
sudo systemctl enable --now wren-watch.timer
# The record, as your files are now
sudo wren-watch accept
```

To undo:

```
sudo systemctl disable --now wren-watch.timer
sudo rm /etc/systemd/system/wren-watch.service /etc/systemd/system/wren-watch.timer /usr/local/bin/wren-watch
sudo rm -rf /var/lib/wren-watch /run/wren-watch
sudo systemctl daemon-reload
```
