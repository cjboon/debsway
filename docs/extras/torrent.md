# BitTorrent as its own locked-down user (`extras/torrent.sh`)

BitTorrent from the terminal: Debian's Transmission runs in the background as its own user, and a `torrent` command adds, lists, copies out and removes downloads. The client never runs as you, can't see your home folder, and can't reach your local network.

## The problem it solves

A BitTorrent client is riskier than most programs, in several ways at once:

- **Strangers talk to it.** It swaps data directly with hundreds of unknown computers (peers) for hours at a time, and every message from them is untrusted input. Popular clients have had serious bugs.
- **Its remote control can be a door.** Clients are usually driven through a small web server. Transmission's had a flaw that let a website you visited drive it, and Debian's default password for it is the well-known `transmission`.
- **It likes to open your router.** Clients ask your router to forward a port to them (UPnP, NAT-PMP), so the internet can reach in.
- **Your IP address is public.** Everyone sharing the same torrent sees it, and copyright firms watch popular torrents for exactly that.
- **The files.** Torrents are a common way to spread malware, especially programs and "cracked" software.

## The ideas behind it

**A user of its own.** Debian's Transmission package runs the client as a system user, `debian-transmission`, with no password and no login. It can't read your private files.

**systemd's locks.** Debian's service already takes away what the client doesn't need: no special privileges, no way to gain any, a private `/tmp`, no devices, no changing the kernel or clock, and only the system calls an ordinary service uses. debsway adds a drop-in on top: `/home` is invisible to it, the rest of the system is read-only except its own folders, its files are private, and it can't leave memory dumps.

**A remote control for you only.** It listens on this computer only (127.0.0.1), answers only requests that come from this computer and name it, which stops a website from reaching it through tricks with domain names (DNS rebinding), and asks for a password made at random when you install. The password is kept in `~/.config/debsway/torrent-rpc`, readable by you only, and the `torrent` command passes it in the environment, never on a command line where other programs could see it.

**Out, never in.** Port opening on your router and local-network peer discovery are off. debsway's firewall (ufw) already refuses incoming connections, so the client only connects out. Some torrents are slower that way, but nothing on the internet can start a conversation with it.

**Off your network.** A firewall rule on the `debian-transmission` user, the same rules as the sandboxed Firefox's, rejects anything it sends to this computer's own services, your router, printers or other machines on your network. It can still reach peers on the internet, and DNS.

**Files you can read, not change.** Downloads go to `/var/lib/debsway-torrent`: unfinished ones in `incomplete`, finished ones in `downloads`. Both folders give what is made in them your group (with the *setgid* bit), so you can read the files; only the client can write there. `torrent get` copies a finished download into `~/Downloads`, as you: regular files only (a link, which could point at one of your files, is left behind), never overwriting a file you have.

## Working with the Mullvad VPN

You don't have to decide now. Each firewall on the computer is a table of its own, and a packet must pass all of them:

- debsway's rule for Transmission only ever *rejects* traffic to your local network and this computer. It never allows anything another firewall blocks.
- With the Mullvad app connected, the client's traffic goes through the VPN to peers on the internet, which debsway's rule allows. DNS is let through before local addresses are rejected, so Mullvad's DNS server inside the tunnel (10.64.0.1) still works.
- With Mullvad's lockdown mode on, the client simply stops while the VPN is off, which is the kill switch you'd want for BitTorrent.

The same holds for debsway's other sandboxes with a firewall rule (the sandboxed Firefox, yt-dlp, Claude Code). A VPN hides your IP address from the other peers; nothing else in this extra does. Don't use Tor for BitTorrent: it still leaks your address, and it slows Tor down for everyone.

## How it works, step by step

1. It installs `transmission-daemon`, `transmission-cli` (for `transmission-remote`), `python3` and `nftables`, through a marker package, so `--remove` takes out exactly those.
2. It stops the client: Debian starts it with its defaults on install, and it writes its settings back when it stops.
3. It makes `/var/lib/debsway-torrent/downloads` and `incomplete`.
4. It makes a random remote-control password (once; kept on later runs) and changes the settings: download folders, the remote control, no port opening, no local discovery, private files (`data/torrent-settings.py`, which gets the password on standard input).
5. It writes the systemd drop-in `/etc/systemd/system/transmission-daemon.service.d/50-debsway.conf`.
6. It installs the firewall rule `/etc/debsway/torrent.nft` and a service that loads it at every boot, then starts the client, only if the rule loaded.
7. It installs the `torrent` command in `~/.local/bin`.

## What it changes on your computer

- The packages `transmission-daemon`, `transmission-cli`, `python3` (usually there already), `nftables`, and the user `debian-transmission` that Debian's package makes.
- `/etc/transmission-daemon/settings.json` (Debian's file), the drop-in, `/var/lib/debsway-torrent`.
- `/etc/debsway/torrent.nft`, `debsway-torrent-firewall.service`.
- `~/.config/debsway/torrent-rpc`, `~/.local/bin/torrent`.

## Using it

- `torrent add 'magnet:?xt=...'` (quote magnet links: they contain `&`), or `torrent add FILE.torrent`.
- `torrent` (or `torrent list`): what is downloading, with numbers.
- `torrent get N` copies a finished one into `~/Downloads`; `torrent get all` every finished one.
- `torrent pause N` and `torrent resume N` (or `all`); `torrent info N`; `torrent files N`.
- `torrent remove N` removes it and its files in the client's folder. Copies you made with `get` stay.
- It keeps sharing what it downloaded until you pause or remove it.
- Play videos with mpv from the media extra (`extras/media.sh`), which opens them in a sandbox. Never run a program that came from a torrent.

## What it protects against

- A peer, a booby-trapped torrent or a bug in Transmission: the damage stays inside `debian-transmission` and its two folders. It can't read your home, change the system, or gain privileges.
- A website or another program on this computer driving the client: the remote control needs a password that isn't Debian's default, and answers only this computer.
- The internet reaching in through your router: no port is opened, and incoming connections are refused.
- Reaching your router, printers or services on this computer.

## What it doesn't protect against

- **Your IP address.** Everyone sharing a torrent sees it. Only a VPN changes that.
- **What you download.** Files are untrusted. A video is fairly safe in the sandboxed mpv; a program is not safe anywhere.
- **The law.** What you may share depends on where you live.
- **The internet.** The client can send whatever it likes to peers on the internet; the firewall only keeps it off your local network.
- **Your kernel.** It shares the kernel with you. A kernel bug could let something escape the user boundary.
- **Filling your disk.** A torrent can be large; the client writes until the disk is full.

## Removing it

`bash ~/debsway/extras/torrent.sh --remove` stops the client, takes out the drop-in, the firewall rule and its service, the `torrent` command, the password file, and the packages it installed that nothing else needs. If downloads are still in `/var/lib/debsway-torrent`, it asks before deleting them. Your copies in `~/Downloads` stay. Debian's `debian-transmission` user stays, as Debian leaves it.
