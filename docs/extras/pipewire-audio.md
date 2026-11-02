# Sound (`extras/pipewire-audio.sh`)

## SYNOPSIS

```
bash ~/debsway/extras/pipewire-audio.sh            install it
bash ~/debsway/extras/pipewire-audio.sh --remove   remove it
bash ~/debsway/extras/pipewire-audio.sh --manual   print the manual steps below

volume up|down|mute|micmute [STEP]    5% steps, never above 100%
  the volume and mute keys, or Super+F10 (mute), Super+F11 (down), Super+F12 (up)
debsway --mic on|off                  the microphone (or the debsway menu > Microphone)
```

Sound through PipeWire, from Debian, started as your user's services. The
`volume` command (`bin/volume`) changes the volume in 5% steps, never above
100%, unmutes on a change and refreshes the bar at once; sway's volume keys
use it, and Super+F10 to F12 do for keyboards without them. The microphone is
muted at every login (by `bin/radios`), so it stays off until you switch it
on. `timer` and the alarm clock ring with PipeWire's `pw-play`.

## LIMITS

- The microphone switch is muting in software: a program running as you could unmute it. A hardware switch is stronger.
- Programs running as you can record from the microphone while it is on.

## MANUAL INSTALL

```
# PipeWire for sound (with its PulseAudio replacement and WirePlumber)
sudo apt install --no-install-recommends pipewire-audio
# Start it now, as your user (it starts at each login after that)
systemctl --user enable --now pipewire.socket pipewire-pulse.socket wireplumber.service

# The volume command, and the microphone switch
install -D -m 0755 @DEBSWAY_DIR@/bin/volume ~/.local/bin/volume
install -D -m 0755 @DEBSWAY_DIR@/bin/radios ~/.local/bin/radios
# The keys, and the microphone muted at every login
mkdir -p ~/.config/sway/config.d
cat >~/.config/sway/config.d/audio.conf <<'EOF'
bindsym --locked XF86AudioRaiseVolume exec ~/.local/bin/volume up
bindsym --locked XF86AudioLowerVolume exec ~/.local/bin/volume down
bindsym --locked XF86AudioMute exec ~/.local/bin/volume mute
bindsym --locked XF86AudioMicMute exec ~/.local/bin/volume micmute
bindsym $mod+F10 exec ~/.local/bin/volume mute
bindsym $mod+F11 exec ~/.local/bin/volume down
bindsym $mod+F12 exec ~/.local/bin/volume up
exec ~/.local/bin/radios mic off --wait
EOF
# sway must accept it (this prints no [ERROR] lines), then reads it
sway -C -c ~/.config/sway/config 2>&1 | grep ERROR
swaymsg reload
# The microphone off now, too
~/.local/bin/radios mic off
```

To undo:

```
# The keys and the volume command (keep radios if the debsway menu or Bluetooth uses it)
rm ~/.config/sway/config.d/audio.conf ~/.local/bin/volume
swaymsg reload
# PipeWire
sudo apt purge pipewire-audio
sudo apt autoremove --purge
```
