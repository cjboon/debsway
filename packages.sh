# shellcheck shell=bash
# packages.sh: what install-base.sh installs; status.sh and test.sh read it too.

# The core: sway and a terminal. Apps people may not want are in extras/
# (Firefox, git, KeePassXC, Claude Code, ...).
# gpg: checks the signatures of everything Wren Linux downloads
# age: encrypts a file to a password or a key (age -p file > file.age)
# diceware: makes passphrases from random words (diceware -n 6)
PKGS=(sway foot libgl1-mesa-dri gpg age diceware)

# Each parts/ script installs its own packages and sets them up; this is
# the order install-base.sh runs them in. network-manager goes near the
# end: moving Wi-Fi over to it briefly drops the connection. random-mac
# needs it.
PARTS=(core-commands home-private clock no-live-extras unattended-upgrades wmenu swaylock swayidle brightnessctl
    wl-clipboard mako foot-config wallpaper theme ufw power-profiles-daemon
    power-menu wren-menu command-hints console-tmux needrestart sysctl-hardening module-blacklist boot-hardening grub-colors
    network-manager secure-dns random-mac usb)
