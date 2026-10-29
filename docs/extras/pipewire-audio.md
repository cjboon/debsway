# Sound and the microphone switch (`extras/pipewire-audio.sh`)

You get working sound through PipeWire, volume keys that do what they should, and a microphone that is off until you switch it on. The `timer` and its alarm also need this to make a noise.

## The problem it solves

A minimal install has no sound server, so nothing plays. A microphone left open can also be listened to by a program, so debsway starts it muted.

## The ideas behind it

**PipeWire** is the program that sits between applications and your speakers and microphone, so several can share them. **WirePlumber** is its helper, and `pipewire-pulse` lets older sound programs talk to it. `pw-play` plays a sound file, and `wpctl` is PipeWire's control command. **Muting in software** means the system is told to ignore the microphone, which is not the same as the hardware being off.

## How it works, step by step

1. `apt_install pipewire-audio`, under the marker package `debsway-pipewire-audio`.
2. It starts the user services `pipewire.socket`, `pipewire-pulse.socket` and `wireplumber.service`. If that fails it warns, and they start at your next login.
3. It installs `volume` and `radios` into `~/.local/bin`.
4. It writes `~/.config/sway/config.d/audio.conf`, checked by sway. It binds the keys below and runs `radios mic off --wait` when sway starts, waiting for the sound system to appear first.
5. It mutes the microphone now, too.

`volume up` and `down` change the volume by 5% (never above 100%), unmute if you were muted, and nudge the status bar to redraw. `volume mute` and `micmute` toggle.

## What it changes on your computer

- Package `pipewire-audio` and its dependencies.
- `~/.local/bin/volume` and `~/.local/bin/radios`.
- `~/.config/sway/config.d/audio.conf`.
- Keys: the volume up, volume down, mute and microphone-mute keys, plus Super+F10 (mute), Super+F11 (down), Super+F12 (up) for keyboards without them. The old stock keys using `pactl` are removed from the sway config.

## Using it

- `volume up|down|mute|micmute [STEP]`: change sound from a terminal.
- `debsway --mic on` or `debsway --mic off`, or the debsway menu: switch the microphone.
- `wpctl status`: check what the sound system sees.

## What it protects against

- **A program listening through the microphone at startup.** It is muted at every login and stays muted until you unmute (`THREAT-MODEL.md`).

## What it doesn't protect against

- **A program running as you.** The mute is software, so it can unmute the microphone again. `THREAT-MODEL.md` says unplugging or a hardware switch is stronger.
- **mpv's sandbox.** It can use your audio server, which could also record the microphone. `incognito` and sandboxed `firefox` never get it.

## Removing it

`bash extras/pipewire-audio.sh --remove` removes the sway snippet, `~/.local/bin/volume` and the `pipewire-audio` package. It does not remove `~/.local/bin/radios`, which the debsway menu also uses.
