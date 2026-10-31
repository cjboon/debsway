# Closing the lid locks but doesn't suspend (`extras/lid-awake.sh`)

Normally, closing a laptop's lid puts it to sleep (suspend). This extra changes that: closing the lid locks the screen and turns the laptop's own panel off, but the computer keeps running, so downloads, the network and the timer's alarms carry on. Opening the lid turns the panel back on.

## The problem it solves

Debian's default is to suspend when you close the lid. That stops downloads, drops the network and silences alarms set with `timer`. If you want a laptop to keep working with the lid shut, for example while it downloads something or runs an alarm, you need to tell the system not to sleep.

## The ideas behind it

**Suspend.** Sleep mode: the computer powers down almost everything but keeps your session in memory. Nothing runs while it sleeps.

**systemd-logind.** The part of the system that watches the lid switch, the power button and logins. It decides what happens when the lid closes. `HandleLidSwitch` is its setting for that.

**A lid switch in sway.** sway can react to the lid by itself. Here it runs the `lid` command.

**Locking.** `swaylock` (from the base) covers the screen and asks for your password. It is the base's lock program.

**Panel.** The laptop's own screen (named `eDP`, `LVDS` or `DSI` by sway). An external screen is not touched.

## How it works, step by step

1. **Warns if there is no battery,** since this is meant for laptops, then goes on.
2. **Tells logind to ignore the lid.** It installs `data/lid-logind.conf` as `/etc/systemd/logind.conf.d/60-debsway-lid.conf`, with `HandleLidSwitch=ignore`, `HandleLidSwitchExternalPower=ignore` and `HandleLidSwitchDocked=ignore`: on battery, plugged in or docked. logind reads it again after a hang-up signal (`SIGHUP`), because a restart could end your session.
3. **Installs the `lid` command** in `~/.local/bin` and adds two lines to sway's config (`~/.config/sway/config.d/lid.conf`): when the lid closes, run `lid close`; when it opens, run `lid open`. The `--locked` flag makes it work while the screen is already locked, and `--reload` right after a sway reload.
4. **Warns if `swaylock` is missing,** since then closing the lid only turns the panel off.

What `lid close` does: if `swaylock` is installed and not already running, it starts it (`swaylock -f -c 000000`, a black screen), then turns off every panel. `lid open` turns the panels on again.

## What it changes on your computer

- `/etc/systemd/logind.conf.d/60-debsway-lid.conf`.
- `~/.local/bin/lid`.
- `~/.config/sway/config.d/lid.conf` (a snippet; the script calls it `lid`).
- No packages, no firewall rules, no users.

## Using it

- Close the lid: the screen locks and the panel goes dark. The laptop keeps running.
- Open it: the panel comes back (you still need your password).
- `lid close` and `lid open` do the same by hand.
- Before putting the laptop in a bag, power it off: Super+Shift+Escape opens the power menu.

## What it protects against

- **Someone opening the lid and using your session.** It is locked.
- **Losing work and alarms to sleep.** The computer stays awake.

## What it doesn't protect against

- **A running laptop being treated as asleep.** It is on, not asleep: the disk key is in memory (`THREAT-MODEL.md`). Shut down before leaving it somewhere or crossing a border.
- **Heat and battery drain** in a closed bag. A closed, running laptop gets warm and its battery runs down.
- **Physical access.** The lock screen is not a defence against someone with the laptop and time.
- **The screen being locked only if `swaylock` is installed.**
- **An external screen,** which stays on and unlocked-visible until the lock covers it (the lock applies to the session).

## Removing it

`bash extras/lid-awake.sh --remove` deletes the logind file, tells logind to reload, removes the sway snippet and the `lid` command. Closing the lid suspends again, which is Debian's default.
