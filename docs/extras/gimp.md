# GIMP, in a sandbox (`extras/gimp.sh`)

## SYNOPSIS

```
wrenctl install gimp                     install it
wrenctl remove gimp                      remove it (~/.config/GIMP and ~/Pictures stay)
wrenctl manual gimp                      print the manual steps below

gimp                           start GIMP, in its sandbox (Super+d too)
gimp ~/Pictures/photo.jpg      open a picture
WREN_NO_SANDBOX=1 gimp      without the sandbox
```

GIMP, the image editor, from Debian. It reads dozens of picture formats, and
a crafted picture from the web is a common way in, so the `gimp` command
Wren Linux installs (`bin/gimp`) starts it inside bubblewrap (`bin/media-sandbox`,
the same sandbox as imv, mpv and zathura): it sees `~/Pictures` to open and
save in, `~/Downloads` to open from (read-only), its own settings
(`~/.config/GIMP`) and the files you name, read-only; not the rest of your
files, and never the network. It gets a restricted Wayland socket
(`bin/wayland-restrict`) without sway's screen-reading or typing protocols.
Its menu entry (`~/.local/share/applications/gimp.desktop`) starts the
sandboxed one too.

## LIMITS

- Save into `~/Pictures`: it can't write anywhere else, and a picture opened from elsewhere is read-only.
- `/usr/bin/gimp-3.0`, or a launcher that uses that path, skips the sandbox; so does `WREN_NO_SANDBOX=1`.
- Plug-ins and scripts you add run inside the same sandbox, but can read and change everything in `~/Pictures`.
- The sandbox shares your kernel: a kernel bug could still get out.

## MANUAL INSTALL

```
# GIMP, bubblewrap for the sandbox, python3 for wayland-restrict
sudo apt install --no-install-recommends gimp bubblewrap python3
# The restricted Wayland socket, the sandbox, and the gimp command that uses it
install -D -m 0755 @WREN_DIR@/bin/wayland-restrict ~/.local/bin/wayland-restrict
install -D -m 0755 @WREN_DIR@/bin/media-sandbox ~/.local/bin/media-sandbox
# With a web address, the sandbox keeps the program off X11 with this wrapper
sudo install -d -o root -g root -m 0755 /usr/local/libexec
sudo install -o root -g root -m 0755 @WREN_DIR@/bin/no-abstract-sockets /usr/local/libexec/wren-no-abstract-sockets
install -D -m 0755 @WREN_DIR@/bin/gimp ~/.local/bin/gimp
mkdir -p ~/Pictures ~/.config/GIMP
# Its menu entry, starting the sandboxed gimp
mkdir -p ~/.local/share/applications
sed -e "s|^Exec=gimp-3.0|Exec=$HOME/.local/bin/gimp|" -e "s|^TryExec=.*|TryExec=$HOME/.local/bin/gimp|" \
    /usr/share/applications/gimp.desktop >~/.local/share/applications/gimp.desktop
```

To undo:

```
rm ~/.local/bin/gimp ~/.local/share/applications/gimp.desktop
# Only if neither the media extra (imv, mpv), the PDF viewer nor incognito uses them
rm ~/.local/bin/media-sandbox ~/.local/bin/wayland-restrict
# (the no-abstract-sockets wrapper only if no other sandbox uses it)
sudo rm /usr/local/libexec/wren-no-abstract-sockets
# GIMP; bubblewrap is marked "automatic" instead of purged, since other
# programs can need it: autoremove takes it out only if nothing does
sudo apt purge gimp
sudo apt-mark auto bubblewrap
sudo apt autoremove --purge
```
