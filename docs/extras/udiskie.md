# USB drives mount by themselves (`extras/udiskie.sh`)

## SYNOPSIS

```
wrenctl install udiskie                     install it
wrenctl remove udiskie                      remove it (cryptsetup stays: the system disk needs it)
wrenctl manual udiskie                      print the manual steps below

plug in a stick          it appears in /media/$USER/NAME (an encrypted one asks for its passphrase)
udiskie-umount -a        unmount every drive before you pull it out
```

USB drives mount by themselves when you plug them in, under
`/media/$USER/`, and LUKS-encrypted ones ask for their passphrase: udiskie
and udisks2 from Debian, with polkitd so your user may mount without sudo.
udiskie's own prompt needs GTK, so Wren Linux gives it a small one,
`bin/luks-askpass` (wmenu in password mode, or a floating foot window).
A stranger's stick is mounted the moment it is plugged in, so every drive is
mounted `nosuid,nodev,noexec`: nothing on it can run as a program (the Wren Linux
stick still works, since its scripts run as `bash x.sh`).

## LIMITS

- Mounting reads the stick's file system, so a stick crafted against the kernel's file system code can still do harm the moment it is plugged in: don't plug in sticks you don't trust.
- A USB device can pretend to be a keyboard; that has nothing to do with mounting.
- noexec doesn't stop you running a script on it with `bash` yourself.

## MANUAL INSTALL

```
# udiskie, udisks2, cryptsetup for encrypted sticks, polkitd so you may mount
# without sudo, and notifications for it
sudo apt install --no-install-recommends udiskie udisks2 cryptsetup polkitd gir1.2-notify-0.7
# The passphrase prompt
install -D -m 0755 @WREN_DIR@/bin/luks-askpass ~/.local/bin/luks-askpass
# Every drive mounts so that nothing on it can run
mkdir -p ~/.config/udiskie
printf '%s\n' 'mount_options:' '  - options: [nosuid, nodev, noexec]' >~/.config/udiskie/config.yml
# sway starts udiskie at login, with that prompt (the path must be absolute)
mkdir -p ~/.config/sway/config.d
cat >~/.config/sway/config.d/automount.conf <<EOF
exec udiskie --no-tray --no-file-manager --password-prompt '$HOME/.local/bin/luks-askpass {device_presentation}'
for_window [app_id="luks-askpass"] floating enable
EOF
# sway must accept it (this prints no [ERROR] lines), then reads it
sway -C -c ~/.config/sway/config 2>&1 | grep ERROR
swaymsg reload
# Start it now too (exec lines run only when sway starts)
swaymsg exec "udiskie --no-tray --no-file-manager --password-prompt '$HOME/.local/bin/luks-askpass {device_presentation}'"
```

To undo:

```
# Stop it, and sway no longer starts it
rm ~/.config/sway/config.d/automount.conf
swaymsg reload
pkill -x udiskie
# The prompt and the mount options
rm ~/.local/bin/luks-askpass ~/.config/udiskie/config.yml
# cryptsetup must stay (the encrypted system disk needs it)
sudo apt-mark manual cryptsetup
# udiskie; udisks2 and the notification library are marked "automatic" instead
# of purged, since other programs can need them: autoremove takes them out
# only if nothing does
sudo apt purge udiskie
sudo apt-mark auto udisks2 gir1.2-notify-0.7
sudo apt autoremove --purge
```
