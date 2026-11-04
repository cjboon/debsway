# Your first time with Wren Linux

This takes about an hour, most of it waiting. You need a computer you can erase, a
USB stick, and an internet connection (a cable or a phone's USB tethering is easiest).

**This erases the whole disk.** Copy what you want to keep somewhere else first.

Wren Linux makes common attacks harder. It doesn't make you anonymous or untouchable:
[THREAT-MODEL.md](../THREAT-MODEL.md) says what it does and doesn't do.

## 1. Install Debian

First, in the computer's BIOS: UEFI only, Secure Boot on, storage mode AHCI.
[bios.md](bios.md) says how, and what to set after the install.

Get Debian 13's installer from [debian.org](https://www.debian.org/distrib/), and
choose these when it asks:

- **Root password:** leave it empty. Your own user gets `sudo` instead.
- **Partitioning:** "Guided - use entire disk and set up encrypted LVM". You type
  its passphrase at every boot, so use five or six random words. It can't be added later.
- **Software selection:** only "standard system utilities". Untick the desktops.

(Someone with Wren Linux can also build you an install stick that answers most of
this: `bash prep/make-install-iso.sh`. Boot it, choose "Automatic install with Wren
Linux", and at your first login answer yes to "Set it up now?". Then go to step 4.)

## 2. Get Wren Linux

Restart, type the passphrase, and log in. Then:

```bash
wget -qO- https://github.com/cjboon/wren-linux/archive/refs/heads/main.tar.gz | tar xz
mv wren-linux-main wren
```

If you aren't online yet, get these files on another computer, or see
[After the first boot](../README.md#after-the-first-boot).

## 3. Check it, then start

Look at the key your copy trusts:

```bash
grep '^WREN_SIGNING_FPR=' ~/wren/pins.sh
```

It should be the fingerprint in [SECURITY.md](../SECURITY.md). Compare it on another
device if you can. If it differs, stop.

Then start the install:

```bash
bash ~/wren/start.sh
```

Run it as yourself, not as root. It explains what it will do and asks before it
changes anything.

## 4. Answer its questions

It asks for your password, then shows a list of optional programs: arrow keys to
move, Space to tick, Enter to go on. You can change all of this later, so if unsure,
these are a good start:

| Pick | For |
|---|---|
| `firefox-sandbox` | a web browser, walled off from your files. Without a browser you have no web. |
| `pipewire-audio` | sound |
| `keepassxc` | a password manager |
| `backup` | encrypted backups |

It then installs for a while. When it's done, log out by typing `exit`, and log in
again: the desktop starts.

## 5. Use the desktop

Super is the Windows or Cmd key.

| Keys | Does |
|---|---|
| Super+Enter | a terminal |
| Super+d | start a program: type its name, then Enter |
| Super+Shift+q | close the window |
| Super+Escape | lock the screen |
| Super+m | the Wren menu: install apps, update, status |
| Super+? | every key |

Click the Wi-Fi name in the bar to connect. If a café's sign-in page won't load, use
**Wi-Fi sign-in** in the Wren menu.

## 6. Check it, and keep it healthy

```bash
wrenctl --status
```

The first lines are "Security at a glance": `[x]` is done, `[~]` partly, `[ ]` not,
each with what to run.

- **Add or remove a program:** `wrenctl --apps`, or `wrenctl --remove NAME`
- **Updates:** Debian's security fixes install themselves. For Wren Linux's own,
  run `wrenctl --update`. If your copy has no git yet, first run
  `bash ~/wren/git-init.sh`.
- **Something broke:** run its script again, which repairs it: `wrenctl --install NAME`
  for a program, `wrenctl --part NAME` for a piece of the desktop. `wrenctl --test`
  checks that it all still works.
- **The desktop won't start:** press Ctrl+Alt+F2 for a text login.

## Habits that matter most

- **Shut down, don't just lock,** when you leave the computer somewhere or cross a
  border. Disk encryption only protects a computer that's off.
- **Keep your disk passphrase safe.** Nobody can get your files back without it.
- **Back up,** and try restoring once. A backup you've never restored isn't one yet.

## Going further

- [docs/extras/](extras/README.md): one page for each optional program
- [docs/opsec.md](opsec.md): laptops, USB drives, networks and passwords
- [SECURITY.md](../SECURITY.md): how to report a problem
