#!/bin/bash
# Sound through PipeWire. Installs ~/.local/bin/volume, which changes the
# volume by 5%, never above 100%, unmutes on a change and refreshes the status
# bar right away. Keys: the volume and mute keys, or Super+F10 (mute), Super+F11
# (down) and Super+F12 (up) for keyboards without them.
# The microphone is muted at every login (bin/radios), so it is off until you
# switch it on: Wren menu > Microphone, wrenctl --mic on, or the mic key.
# That is muting in software; see man wrenctl.
# Usage: bash pipewire-audio.sh [--remove | --manual]
# summary: Sound: PipeWire, volume keys, microphone mute
# security: some
# status: apt:pipewire-audio
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
if [ "${1:-}" = --manual ]; then print_manual; exit; fi
need_user

if [ "${1:-}" = --remove ]; then
    remove_snippet audio
    remove_bin volume
    apt_purge pipewire-audio
    exit
fi

say "Installing pipewire-audio"
# (PipeWire brings pw-play, which the timer and alarm clock ring with; the sound
# they play is Wren Linux's own, data/alarm.wav)
apt_install pipewire-audio

say "Starting the user audio services"
systemctl --user enable --now pipewire.socket pipewire-pulse.socket wireplumber.service ||
    warn "Couldn't start them now; they start at your next login."

install_bin volume
# the microphone switch (the Wren menu uses it too)
install_bin radios

# The stock config binds the media keys to pactl, which isn't installed
put_snippet audio <<'EOF'
# Volume (Wren Linux extras/pipewire-audio.sh)
bindsym --locked XF86AudioRaiseVolume exec ~/.local/bin/volume up
bindsym --locked XF86AudioLowerVolume exec ~/.local/bin/volume down
bindsym --locked XF86AudioMute exec ~/.local/bin/volume mute
bindsym --locked XF86AudioMicMute exec ~/.local/bin/volume micmute
bindsym $mod+F10 exec ~/.local/bin/volume mute
bindsym $mod+F11 exec ~/.local/bin/volume down
bindsym $mod+F12 exec ~/.local/bin/volume up
# The microphone starts muted. Sound is still starting at login, so it waits for it.
exec ~/.local/bin/radios mic off --wait
EOF
# Muted now too, not only at the next login
~/.local/bin/radios mic off >/dev/null 2>&1 || true
note "The microphone is off until you switch it on (wrenctl --mic on, or the Wren menu)."
note "Check the sound with: wpctl status"
