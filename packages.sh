# shellcheck shell=bash
# packages.sh: what install-base.sh installs; status.sh and test.sh read it too.

# The core: sway, a terminal and a browser. Apps people may not want are
# in extras/ (git and gh, KeePassXC, Claude Code, ...).
# libavcodec61: Firefox's H.264/video codecs, normally a recommended package
# webext-ublock-origin-firefox: uBlock Origin from Debian, on in every profile
# gpg: checks the signatures of everything debsway downloads
PKGS=(sway foot libgl1-mesa-dri firefox-esr libavcodec61 webext-ublock-origin-firefox gpg)

# Each parts/ script installs its own packages and sets them up. They're
# listed here too so everything comes in one apt run; the scripts then
# find them already installed. network-manager goes near the end: moving
# Wi-Fi over to it briefly drops the connection. random-mac needs it.
PARTS=(unattended-upgrades pipewire-audio wmenu swaylock swayidle brightnessctl grim-slurp
    wl-clipboard mako udiskie emoji-font ufw power-profiles-daemon firefox-hardening
    network-manager random-mac)
PARTS_PKGS=(unattended-upgrades pipewire-audio wmenu swaylock swayidle brightnessctl grim slurp
    wl-clipboard mako-notifier udiskie udisks2 cryptsetup polkitd gir1.2-notify-0.7
    fonts-noto-color-emoji ufw power-profiles-daemon libnotify-bin
    network-manager wpasupplicant wireless-regdb)
