#!/bin/bash
# imv (image viewer) and mpv (video and music player), from Debian. Both
# run natively on Wayland. Debian names the viewer imv-wayland, so an
# "imv" command is added for it.
# Usage: bash media.sh [--remove]
# summary: imv image viewer and mpv video and music player
# status: apt:imv apt:mpv
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
need_user

if [ "${1:-}" = --remove ]; then
    remove_bin imv
    apt_purge imv mpv
    exit
fi

say "Installing imv and mpv"
apt_install imv mpv
if [ ! -e /usr/bin/imv ]; then
    install_bin imv
fi

cat <<'EOF'

    How to use imv (images):
      imv photo.jpg                  open one image
      imv ~/Pictures                 every image in a folder
      imv -r ~/Pictures              ... and its subfolders
      imv -t 5 ~/Pictures            slideshow, 5 seconds each
    Keys: Left/Right previous/next, Up/Down or i/o zoom, a actual size,
          r reset, f fullscreen, d show file name, x close image, q quit

    How to use mpv (video and music):
      mpv video.mp4                  play a video
      mpv ~/Music                    play a whole folder
      mpv --shuffle ~/Music          ... in random order
      mpv --no-video song.mp3        just the sound, no window
      mpv --start=1:30 video.mp4     start 1 minute 30 in
    Keys: Space pause, Left/Right 5 s back/forward, Up/Down 1 minute,
          9/0 volume, m mute, f fullscreen, s screenshot, q quit
EOF
