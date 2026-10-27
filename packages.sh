# shellcheck shell=bash
# packages.sh: what install-base.sh installs; status.sh and test.sh read it too.

# The core: sway and a terminal. Apps people may not want are in extras/
# (Firefox, git and gh, KeePassXC, Claude Code, ...).
# gpg: checks the signatures of everything debsway downloads
PKGS=(sway foot libgl1-mesa-dri gpg)

# Each parts/ script installs its own packages and sets them up; this is
# the order install-base.sh runs them in. network-manager goes near the
# end: moving Wi-Fi over to it briefly drops the connection. random-mac
# needs it.
PARTS=(unattended-upgrades pipewire-audio wmenu swaylock swayidle brightnessctl grim-slurp
    wl-clipboard mako udiskie emoji-font foot-config ufw power-profiles-daemon
    power-menu needrestart sysctl-hardening module-blacklist boot-hardening
    network-manager random-mac)
