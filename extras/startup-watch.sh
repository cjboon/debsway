#!/bin/bash
# The startup watch: a program running as you that wants to start again at
# every login has to change one of a few files (your shell's startup files,
# sway's config, autostart, systemd user units, ~/.local/bin, tmux's and vim's,
# curl's and wget's settings, ...). This keeps
# their fingerprints where it can't change them (root's, /var/lib/wren-watch),
# compares them at boot and every 15 minutes (a root timer), and shows what
# changed: "startup changed" in the bar, with a notification, and wren-watch.
#  - wren-watch lists what changed; sudo wren-watch diff shows the changes;
#    sudo wren-watch accept takes them as yours (it asks your password: a
#    program running as you can't accept its own change without it).
#  - wrenctl install, part, remove and update accept what their run changed,
#    so Wren Linux's own changes don't show (a file that had changed before
#    the run is left for you to look at).
#  - It notices, it doesn't prevent; and it can't see what runs from memory,
#    or a file outside the ones it watches (bin/wren-watch lists them).
# Usage: bash startup-watch.sh [--remove | --manual]
# summary: Notices changes to what starts at your login
# security: most
# files: bin/wren-watch
# status: file:/usr/local/bin/wren-watch
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
if [ "${1:-}" = --manual ]; then print_manual; exit; fi
need_user

CMD=/usr/local/bin/wren-watch
SERVICE=/etc/systemd/system/wren-watch.service
TIMER=/etc/systemd/system/wren-watch.timer

if [ "${1:-}" = --remove ]; then
    sudo systemctl disable --now wren-watch.timer >/dev/null 2>&1 || true
    sudo rm -f "$SERVICE" "$TIMER"
    sudo systemctl daemon-reload
    sudo rm -rf "/var/lib/wren-watch/$(id -un)" "/run/wren-watch/$(id -un)"
    sudo rmdir /var/lib/wren-watch 2>/dev/null || true
    # the command stays while another user is still watched
    [ -d /var/lib/wren-watch ] || sudo rm -f "$CMD"
    note "Your startup files are no longer watched."
    exit
fi

say "The startup watch"
apt_install python3 diffutils
sudo install -o root -g root -m 0755 "$WREN_DIR/bin/wren-watch" "$CMD"
# Root's, as it reads every watched home; it may write only its record and
# its list of changes, and has no network
printf '%s\n' '# Written by Wren Linux extras/startup-watch.sh' '[Unit]' \
    'Description=Wren Linux: compare the startup files with their record' '' \
    '[Service]' 'Type=oneshot' "ExecStart=$CMD check-all" \
    'ProtectSystem=strict' 'ReadWritePaths=/var/lib/wren-watch /run/wren-watch' 'ProtectHome=read-only' \
    'PrivateTmp=yes' 'PrivateNetwork=yes' 'NoNewPrivileges=yes' 'RuntimeDirectory=wren-watch' \
    'RuntimeDirectoryPreserve=yes' 'StateDirectory=wren-watch' |
    sudo tee "$SERVICE" >/dev/null
printf '%s\n' '# Written by Wren Linux extras/startup-watch.sh: at boot, then every 15 minutes' '[Unit]' \
    'Description=Wren Linux: compare the startup files every 15 minutes' '' \
    '[Timer]' 'OnBootSec=1min' 'OnUnitActiveSec=15min' '' '[Install]' 'WantedBy=timers.target' |
    sudo tee "$TIMER" >/dev/null
sudo systemctl daemon-reload
sudo systemctl enable --now wren-watch.timer >/dev/null
say "Their record, as they are now"
note "From now on a change to them shows in the bar until you accept it."
sudo "$CMD" accept >/dev/null
note "Watched: your shell's startup files, sway's config, autostart, systemd user units,"
note "your ~/.local/bin and a few more (wren-watch --help). See a change: wren-watch"
