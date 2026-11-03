# imv and mpv, in a sandbox (`extras/media.sh`)

## SYNOPSIS

```
wrenctl install media                     install them
wrenctl remove media                      remove them
wrenctl manual media                      print the manual steps below

imv photo.jpg | imv ~/Pictures | imv -r ~/Pictures | imv -t 5 ~/Pictures (slideshow)
  Left/Right previous/next   i/o zoom   a actual size   f fullscreen   q quit
mpv video.mp4 | mpv ~/Music | mpv --shuffle ~/Music | mpv --no-video song.mp3
mpv --sub-file=subs.srt movie.mp4   a subtitle file is only seen when you name it
  Space pause   Left/Right 5 s   Up/Down 1 minute   9/0 volume   m mute   f fullscreen   q quit
WREN_NO_SANDBOX=1 mpv video.mp4  without the sandbox
```

imv shows images and mpv plays video and music, both from Debian and both
native on Wayland. Images and videos are where attackers hide things, so the
`imv` and `mpv` commands Wren Linux installs (`bin/imv`, `bin/mpv`) start them
inside bubblewrap (`bin/media-sandbox`): each sees only the files and folders
you name, read-only, its own empty home, no network (except mpv for a URL),
and a restricted Wayland socket (`bin/wayland-restrict`) without sway's
screen-reading or typing protocols. mpv also gets your sound. The first time
mpv starts with no sound set up, it says so once.

## LIMITS

- `/usr/bin/mpv` or `/usr/bin/imv`, or a launcher that uses those paths, skips the sandbox; so does `WREN_NO_SANDBOX=1`.
- The sandbox shares your kernel: a kernel bug could still get out.
- mpv given a URL has the network, so the site sees your address.

## MANUAL INSTALL

```
# imv, mpv, bubblewrap for the sandbox, python3 for wayland-restrict
sudo apt install --no-install-recommends imv mpv bubblewrap python3
# The restricted Wayland socket, the sandbox, and the commands that use it
for c in wayland-restrict media-sandbox imv mpv; do install -D -m 0755 @WREN_DIR@/bin/$c ~/.local/bin/$c; done
# ~/.local/bin must come before /usr/bin, so "mpv" is the sandboxed one:
# this must print ~/.local/bin/mpv
command -v mpv
```

To undo:

```
# The commands
rm ~/.local/bin/imv ~/.local/bin/mpv
# Only if neither the PDF viewer nor incognito uses them: the sandbox and the socket
rm ~/.local/bin/media-sandbox ~/.local/bin/wayland-restrict
# imv and mpv; bubblewrap is marked "automatic" instead of purged, since other
# programs can need it: autoremove takes it out only if nothing does
sudo apt purge imv mpv
sudo apt-mark auto bubblewrap
sudo apt autoremove --purge
```
