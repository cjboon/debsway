# Share files over Tor with OnionShare (`extras/onionshare.sh`)

OnionShare lets you send files, receive files, host a small website or run a chat room straight from your computer, with no account and no company server in between. The other person opens a long `.onion` address in Tor Browser. This extra installs it and, if you need one, sets up a Tor bridge before its first connection.

## The problem it solves

Normally, to send someone a big file you upload it to a company's server (email, a file-sharing site), and that company, and anyone watching your network, can see it. You also need an account and the other person needs to trust the service.

OnionShare skips the middle. Your computer becomes the server for a short time, and Tor hides where it is.

## The ideas behind it

**Tor.** A network of volunteer relays that passes traffic through three hops, so no single relay knows both who you are and where you are going. See `docs/extras/tor-browser.md`.

**An onion address.** A name ending in `.onion` that exists only inside Tor. A visitor reaches it without ever learning your real internet address, and you do not need to open anything on your router: your computer makes an outgoing connection to Tor, and visitors come in through it. It is like a mailbox in a building whose street address nobody is told.

**A private key.** By default OnionShare also makes a key. Without the key, the address alone does not open the share. You send both to the other person. With `--public`, there is no key and anyone who has the address can open it.

**A bridge.** A Tor relay that is not on the public list, for networks that block Tor or when you do not want your network to see you use Tor. See "Bridges" in `docs/install-base.md`. OnionShare can use Tor's built-in obfs4 bridges, obfs4 lines you get yourself, or Snowflake. It cannot use webtunnel or meek on Debian.

**The system tor service.** Debian's `onionshare-cli` package depends on `tor`, which starts a system-wide Tor the moment it is installed, connecting directly with no bridge. OnionShare does not use it; it starts its own private tor.

## How it works, step by step

1. **Asks about bridges first,** before anything is installed. If OnionShare already has custom bridge lines, it offers to keep them.
2. **Blocks the system tor service.** The script runs `systemctl mask tor.service tor@default.service`, which means it cannot start. The exception: if apt over Tor, remote access or the onion site already uses the system tor, it leaves it on, because those have their own bridge set up.
3. **Installs `onionshare-cli` and `obfs4proxy`**, plus `snowflake-client` if you chose Snowflake. It asks whether you also want the graphical app, and if yes installs `onionshare` and `qt6-wayland` (which lets the app run on Wayland without XWayland). If the system tor is running anyway, it warns you.
4. **Writes OnionShare's settings** (`~/.config/onionshare/onionshare.json`, mode 600) before its first start: it uses its own bundled tor, and your bridge choice. Only these settings are written; OnionShare fills in the rest. Its first connection therefore goes through the bridge.
5. **Prints examples** of `onionshare-cli` commands.

If you say you need a bridge but set none up, the script warns that OnionShare will connect directly, and suggests running it again.

## What it changes on your computer

- Packages: `onionshare-cli`, `obfs4proxy`; optionally `snowflake-client`, `onionshare` and `qt6-wayland`; and whatever they pull in, including Debian's `tor`.
- `tor.service` and `tor@default.service` masked (unless another debsway extra needs the system tor).
- `~/.config/onionshare/onionshare.json`.
- No firewall rules, no new users, nothing in `~/.local/bin`.

## Using it

- `onionshare-cli report.pdf photos/` shares files and folders; it stops after the first download.
- `onionshare-cli --no-autostop-sharing report.pdf` keeps sharing after downloads.
- `onionshare-cli --auto-stop-timer 3600 report.pdf` stops sharing after an hour.
- `onionshare-cli --receive` lets people send you files, saved in `~/OnionShare`.
- `onionshare-cli --website ~/site/` hosts a static website.
- `onionshare-cli --chat` starts a private chat room.
- `onionshare-cli --public report.pdf` makes it public: no key.
- `onionshare-cli --qr report.pdf` also shows the address as a QR code.
- Press Ctrl+C to stop sharing.
- `onionshare` (or Super+d) opens the graphical app, if installed.

The other person opens the address in Tor Browser.

## What it protects against

- **Your files passing through a company's server.** There is none.
- **The other side learning your real address,** because the service is an onion address.
- **Your network seeing that you use Tor,** if you chose a bridge, since the bridge is set up before the first connection.
- **A stray tor connecting without your bridge,** because the system tor service is masked.

## What it doesn't protect against

- **The share's address and key leaking.** Whoever holds them (or just the address, with `--public`) can get the files. Send them over a channel you trust.
- **What is in the files.** Documents and photos often carry hidden data such as names and locations. `extras/metadata-cleaner.sh` can clean them first.
- **Being online only while sharing.** The share exists only while your computer and OnionShare are running, and when it is up can hint at you.
- **Programs that run as you.** OnionShare is not sandboxed from your files beyond what you give it. Receive mode writes files to your computer; open what arrives with care.
- **Identity.** It hides your address, not who you are if the files or messages say so.
- **A determined, well-funded attacker** (`THREAT-MODEL.md`).

## Removing it

`bash extras/onionshare.sh --remove` uninstalls `onionshare` and `onionshare-cli` (and what only they needed, like `obfs4proxy`, unless another script uses it). Your settings stay in `~/.config/onionshare` and received files stay in `~/OnionShare`. The system tor service stays masked; the script prints the command to undo that: `sudo systemctl unmask tor.service tor@default.service`.
