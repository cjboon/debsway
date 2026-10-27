#!/bin/bash
# Sound through PipeWire, with the volume keys bound to wpctl.
# Usage: bash pipewire-audio.sh [--remove]
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
need_user

if [ "${1:-}" = --remove ]; then
    remove_snippet audio
    apt_purge pipewire-audio
    exit
fi

say "Installing pipewire-audio"
apt_install pipewire-audio

say "Starting the user audio services"
systemctl --user enable --now pipewire.socket pipewire-pulse.socket wireplumber.service ||
    warn "Couldn't start them now; they start at your next login."

# The stock config binds these keys to pactl, which isn't installed
put_snippet audio <<'EOF'
# Volume keys (debsway parts/pipewire-audio.sh)
bindsym --locked XF86AudioRaiseVolume exec wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+
bindsym --locked XF86AudioLowerVolume exec wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-
bindsym --locked XF86AudioMute exec wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
bindsym --locked XF86AudioMicMute exec wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle
EOF
note "Check it with: wpctl status"
