# yt-dlp as its own locked-down user (`extras/yt-dlp.sh`)

yt-dlp downloads videos and sound from YouTube and many other sites. This extra installs it so that it never runs as you: the `yt-dlp` command works as usual, but yt-dlp itself runs as a separate user, `ytdlp`, that can't read your files and can't reach your local network. What it downloads is copied into your `~/Downloads` when it is done.

## The problem it solves

yt-dlp is a big program that talks to websites built by others, and it changes often because those sites change often. To download from YouTube it now also has to **run YouTube's own JavaScript**, code written by Google, on your computer. And the files it downloads are joined and converted by ffmpeg, which reads whatever the site sent.

Run as you, a bug in any of these, or a bad release, could read everything you can: your documents, ssh keys, password database and browser profiles.

Debian's own `yt-dlp` package doesn't help much: Debian's version is too old to keep working with YouTube.

## The ideas behind it

**A user of its own.** Linux keeps users apart: one user can't read another's private files. `ytdlp` is a *system* user with no password and no login shell, so nobody can log in as it, and a home folder only it can open. Your user may run exactly one script as `ytdlp`, through a sudo rule (`/etc/sudoers.d/debsway-ytdlp`), and nothing else.

**The real yt-dlp, checked.** It installs the official release, the "zipimport" file that Python runs. Every release comes with a list of checksums, signed with yt-dlp's signing key. That key's fingerprint is pinned in `pins.sh`, and the key is fetched from keys.openpgp.org rather than from GitHub, where the releases themselves live. The download is used only if the list carries a good signature from that key and the file has the checksum the list gives.

**A file it can't change.** yt-dlp is installed as root's file. `ytdlp` can run it but not modify it, so a run that went wrong can't plant something for the next one, and yt-dlp can't "update itself" from somewhere unchecked. You update it by running the extra again, which checks the new release the same way.

**JavaScript from Debian.** yt-dlp needs a separate JavaScript program to run YouTube's code. It recommends deno, which isn't in Debian; Debian's node is older than yt-dlp needs. This extra uses Debian's QuickJS (`qjs`), whose version (2025.04.26) is the first one yt-dlp calls fast enough. QuickJS doesn't sandbox the code itself; the `ytdlp` user is the sandbox.

**Files go one way.** For each run yt-dlp gets a new, empty folder of its own (in `/var/lib/debsway-ytdlp-out`), which only `ytdlp` and your user can open. When yt-dlp is done, the `yt-dlp` command, running as you, copies the finished files into `~/Downloads` and deletes that folder. `ytdlp` never gets into your home. Only regular files are copied: a link (which could point at one of your files) and unfinished `.part` downloads are left behind. A file you already have is never overwritten; the new one is saved as "name (2).ext".

**No settings left behind.** yt-dlp's config files are ignored, so even a run that went wrong can't change how the next run behaves. Give options on the command line instead.

**Off your network.** A firewall rule on the `ytdlp` user, the same rules as the sandboxed Firefox's, rejects anything it sends to this computer's own services, your router, printers or other machines on your network. It can still reach the internet, and DNS.

## How it works, step by step

1. It installs `python3`, `quickjs`, `ffmpeg` and `nftables` (through a marker package, so `--remove` takes out exactly those).
2. It finds yt-dlp's newest release on GitHub, downloads its `SHA2-256SUMS`, `SHA2-256SUMS.sig` and `yt-dlp`, checks the signature and the checksum, and installs `yt-dlp` as `/usr/local/lib/debsway/yt-dlp/yt-dlp`, owned by root. If that version is already installed, it skips the download.
3. It makes the `ytdlp` system user (home `/var/lib/debsway-ytdlp`) and the exchange folder `/var/lib/debsway-ytdlp-out`.
4. It installs the session script `/usr/local/libexec/yt-dlp-session` (run as `ytdlp`) and the `yt-dlp` command `/usr/local/bin/yt-dlp` (run as you), both owned by root.
5. It writes the sudoers rule, checked with `visudo` first, and a limit on how many processes `ytdlp` may start.
6. It installs the firewall rule `/etc/debsway/yt-dlp.nft` and a service that loads it at every boot, before the network comes up.

## What it changes on your computer

- The packages `python3` (usually there already), `quickjs`, `ffmpeg`, `nftables`.
- The user `ytdlp`, its home `/var/lib/debsway-ytdlp` (only yt-dlp's cache), `/var/lib/debsway-ytdlp-out`.
- `/usr/local/lib/debsway/yt-dlp/`, `/usr/local/bin/yt-dlp`, `/usr/local/libexec/yt-dlp-session`.
- `/etc/sudoers.d/debsway-ytdlp`, `/etc/security/limits.d/50-debsway-ytdlp.conf`, `/etc/debsway/yt-dlp.nft`, `debsway-ytdlp-firewall.service`.

## Using it

- `yt-dlp URL`: the video, in the best quality yt-dlp finds.
- `yt-dlp -x URL`: the sound only. `yt-dlp -F URL` lists the formats; `yt-dlp -f FORMAT URL` picks one.
- Files land in `~/Downloads` (or your Downloads folder, if you've set another).
- **Updating:** when a site stops working, a newer yt-dlp usually fixes it: `bash ~/debsway/extras/yt-dlp.sh` (or debsway → Install apps, then yt-dlp).
- Play what you download with mpv from the media extra (`extras/media.sh`), which opens it in a sandbox.

## What it protects against

- yt-dlp, the JavaScript it runs, or ffmpeg being exploited by a site, or a bad yt-dlp release: the damage stays inside `ytdlp`. It can't read your files, keys, passwords or browser profiles, and it can't change the system.
- A release that wasn't signed by yt-dlp's key, or was changed after signing: it isn't installed.
- A run leaving something behind for later: yt-dlp itself is root's file and its config files are ignored.
- Reaching your router, printers or services on this computer.

## What it doesn't protect against

- **The files themselves.** A video is still a file from the internet. Open it with the sandboxed mpv, not a plain player.
- **The internet.** `ytdlp` can still send whatever it likes to the internet; the firewall only keeps it off your local network.
- **Your kernel.** `ytdlp` shares the kernel with you. A kernel bug could let something escape the user boundary; that's rare, but a VM (like `extras/claude-vm.sh`) is a stronger wall.
- **Filling your disk.** A run that went wrong could download, and get copied, a lot of data.
- **Something yt-dlp's own developers sign.** The signature proves who made a release, not that it's harmless. That's why it runs as `ytdlp`.
- **What sites learn.** Sites see your IP address as with any download. Nothing here goes through Tor.

## Removing it

`bash ~/debsway/extras/yt-dlp.sh --remove` takes out the `ytdlp` user, its folders, yt-dlp, the commands, the sudoers rule, the limit, the firewall rule and its service, and the packages it installed that nothing else needs. Your files in `~/Downloads` are yours and stay.
