#!/bin/bash
# imv (image viewer) and mpv (video and music player), from Debian. Both
# run natively on Wayland. Images and videos are what attackers hide things
# in, so imv and mpv start inside bubblewrap (bin/media-sandbox): they see
# only the files you open, read-only, have no network (except mpv for a
# URL) and an empty home. DEBSWAY_NO_SANDBOX=1 runs one without it.
# Usage: bash media.sh [--remove]
# summary: imv and mpv, each in a sandbox
# status: apt:imv apt:mpv apt:bubblewrap bin:imv bin:mpv bin:media-sandbox
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
need_user

if [ "${1:-}" = --remove ]; then
    remove_bin imv
    remove_bin mpv
    remove_bin media-sandbox
    # incognito needs it too
    [ -x /usr/local/bin/incognito ] || remove_bin wayland-restrict
    apt_purge imv mpv bubblewrap
    exit
fi

say "Installing imv and mpv"
apt_install imv mpv bubblewrap python3
install_bin wayland-restrict
install_bin media-sandbox
install_bin imv
install_bin mpv

cat <<'EOF'

    imv and mpv run in a sandbox: they see only the files and folders you
    name when you start them, read-only. A subtitle file next to a video is
    not seen unless you name it: mpv --sub-file=subs.srt movie.mp4
    Starting one by its full path (/usr/bin/mpv), or from a launcher that
    does, skips the sandbox; so does DEBSWAY_NO_SANDBOX=1.

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
