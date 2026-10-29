# Images and video in a sandbox (`extras/media.sh`)

You get `imv`, an image viewer, and `mpv`, a video and music player. Each is started inside a small sandbox that lets it see only the files you name, read-only, with an empty home folder and no network (except when you give mpv a web address).

## The problem it solves

Images and videos are files that a program has to decode, and decoders are complicated. Attackers hide things in them: a crafted picture or film can exploit a bug in the viewer. If the viewer runs as you with all your files, a successful attack can read your ssh keys or password files.

## The ideas behind it

**A sandbox.** A box around a program that limits what it can touch. A viewer needs one file, so it is given one file and nothing else.

**bubblewrap (`bwrap`).** A small tool that starts a program in a restricted view of the computer. It can show the program only chosen folders, give it a blank temporary home, and cut it off from the network and from other programs.

**Read-only.** The program can look at a file but not change it.

**Wayland and a socket.** Wayland is how programs draw windows on sway. A socket is a special file for talking to another program. Whoever opens your real window socket could ask for screenshots or send key presses. `wayland-restrict` makes a second socket that sway marks as "sandboxed", which allows windows but not those powers.

**A network namespace.** Part of what bubblewrap can separate. A program in its own network space sees no network at all.

## How it works, step by step

When you run `bash extras/media.sh`, it installs `imv`, `mpv`, `bubblewrap` and `python3`, and puts four commands in `~/.local/bin`: `imv`, `mpv`, `media-sandbox` and `wayland-restrict`. The `imv` and `mpv` commands are short wrappers around `media-sandbox`. It prints key hints.

When you start `imv photo.jpg` or `mpv video.mp4`, `media-sandbox`:

1. Starts `wayland-restrict` to make the restricted window socket for this run.
2. Builds a `bwrap` command that unshares everything (`--unshare-all`, which includes the network), dies with its parent, and clears the environment. It shows the program the system folders `/usr` and `/etc` and `/sys` read-only, a blank temporary `/tmp`, and an empty temporary home folder and runtime folder. It also hands over the restricted Wayland socket and, if present, the graphics device folder `/dev/dri`.
3. Looks at each thing on the command line. A file or folder that exists is shown read-only at its real path. An option such as `--sub-file=subs.srt` that names a file works the same way. A subtitle next to a video is not seen unless you name it.
4. If you give an address like `https://...` (not `file://`), it allows network access and shows `/etc/ssl` so certificates work. Otherwise there is no network.
5. For `mpv` only, it also shows your sound server's socket, so sound works. Your `~/.config/mpv` or `~/.config/imv` is shown read-only if it exists.

The `mpv` wrapper says once if no sound system is installed, and points you to the `pipewire-audio` extra.

## What it changes on your computer

- Packages: `imv`, `mpv`, `bubblewrap`, `python3`.
- `~/.local/bin/imv`, `mpv`, `media-sandbox` and `wayland-restrict`.
- Per run: a temporary socket in `$XDG_RUNTIME_DIR`, removed afterwards.
- A small marker file under `~/.local/state/debsway/` the first time mpv says there is no sound.

No user is created, no sudo rule, no firewall rule.

## Using it

- `imv photo.jpg`, `imv ~/Pictures`, `imv -r ~/Pictures`, `imv -t 5 ~/Pictures` (slideshow). Keys: Left/Right, Up/Down or i/o to zoom, a actual size, r reset, f fullscreen, d file name, x close image, q quit.
- `mpv video.mp4`, `mpv ~/Music`, `mpv --shuffle ~/Music`, `mpv --no-video song.mp3`, `mpv --start=1:30 video.mp4`. Keys: Space pause, Left/Right 5 s, Up/Down 1 minute, 9/0 volume, m mute, f fullscreen, s screenshot, q quit.
- `mpv --sub-file=subs.srt movie.mp4`: name subtitles explicitly.
- `DEBSWAY_NO_SANDBOX=1 mpv video.mp4`: run without the sandbox.

## What it protects against

- **A booby-trapped image or video reading your files.** The program sees only what you named, read-only, plus system folders. It has an empty home.
- **Writing to your files.** Everything shown is read-only.
- **Phoning home.** No network unless you give mpv a web address.
- **Screen reading or typing for you.** The restricted socket does not offer those.

## What it doesn't protect against

- **A kernel bug.** The sandbox shares your kernel.
- **mpv and your audio server.** It gets the socket, which could also be used to record the microphone.
- **A web address you give mpv.** That program then has network access.
- **Folders you name.** The whole folder is visible, read-only, so a folder of sensitive files is readable.
- **System files.** `/etc` and `/usr` are visible, so whatever any user can read there, it can.
- **Starting it another way.** `/usr/bin/mpv` by full path, a launcher that does that, or `DEBSWAY_NO_SANDBOX=1` runs without protection.
- **Tricks of this kind of tool.** bubblewrap is a convenience, not a guarantee; there is no extra filtering of system calls here.

## Removing it

`bash extras/media.sh --remove` deletes the `imv`, `mpv` and `media-sandbox` commands, and `wayland-restrict` unless `incognito` is installed. It then removes `imv`, `mpv` and `bubblewrap` unless another extra needs them. Your pictures and music are untouched.
