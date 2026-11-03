# zathura PDF viewer, in a sandbox (`extras/pdf-viewer.sh`)

## SYNOPSIS

```
wrenctl install pdf-viewer                     install it
wrenctl remove pdf-viewer                      remove it
wrenctl manual pdf-viewer                      print the manual steps below

zathura paper.pdf              open a PDF, in its sandbox
zathura -P 5 paper.pdf         open at page 5
  j/k scroll   Space/b page down/up   gg/G first/last page   5G page 5
  +/- zoom   a fit page   s fit width   / search (n next)   Tab contents   q quit
WREN_NO_SANDBOX=1 zathura paper.pdf    without the sandbox
```

zathura is a small, keyboard-driven PDF viewer from Debian, made the default
for PDFs. A PDF is a complicated file that the viewer has to interpret, and
crafted ones are a common way in, so the `zathura` command Wren Linux installs
(`bin/zathura`) starts it inside bubblewrap (`bin/media-sandbox`, the same
sandbox as imv and mpv): it sees only the files you name, read-only, its own
empty home, no network, and a restricted Wayland socket (`bin/wayland-restrict`)
without sway's screen-reading or typing protocols.

## LIMITS

- `/usr/bin/zathura`, or a launcher that uses that path, skips the sandbox; so does `WREN_NO_SANDBOX=1`.
- The sandbox shares your kernel: a kernel bug could still get out.
- It can still show you a misleading page; a link you follow opens outside the sandbox.

## MANUAL INSTALL

```
# zathura with its PDF plugin, bubblewrap for the sandbox, python3 for wayland-restrict
sudo apt install --no-install-recommends zathura zathura-pdf-poppler bubblewrap python3
# The restricted Wayland socket, the sandbox, and the zathura command that uses it
install -D -m 0755 @WREN_DIR@/bin/wayland-restrict ~/.local/bin/wayland-restrict
install -D -m 0755 @WREN_DIR@/bin/media-sandbox ~/.local/bin/media-sandbox
install -D -m 0755 @WREN_DIR@/bin/zathura ~/.local/bin/zathura
# Make it the default for PDFs (in ~/.config/mimeapps.list, under
# [Default Applications], replacing an older default)
mkdir -p ~/.config && touch ~/.config/mimeapps.list
grep -qx '\[Default Applications\]' ~/.config/mimeapps.list || echo '[Default Applications]' >>~/.config/mimeapps.list
sed -i '/^application\/pdf=/d; /^\[Default Applications\]$/a application/pdf=org.pwmt.zathura.desktop' ~/.config/mimeapps.list
```

To undo:

```
# The zathura command, and the default for PDFs
rm ~/.local/bin/zathura
sed -i '/=org\.pwmt\.zathura\.desktop$/d' ~/.config/mimeapps.list
# Only if neither the media extra (imv, mpv) nor incognito uses them: the sandbox and the socket
rm ~/.local/bin/media-sandbox ~/.local/bin/wayland-restrict
# zathura; bubblewrap is marked "automatic" instead of purged, since other
# programs can need it: autoremove takes it out only if nothing does
sudo apt purge zathura zathura-pdf-poppler
sudo apt-mark auto bubblewrap
sudo apt autoremove --purge
```
