# Firefox as its own locked-down user (`extras/firefox-sandbox.sh`)

You get a `firefox` command that opens Firefox as a normal window on your desktop, but the program runs as a different Linux user that has no password and none of your files. Your logins, history and bookmarks are kept, in that user's own home. If a web page takes over the browser, it reaches that user and not your documents, ssh keys or passwords.

## The problem it solves

When you run `firefox-esr` the ordinary way, it runs as you. Anything that takes over the browser can then do what you can do: read your files, your ssh keys, your password database, and the saved logins of other programs. Browsers are big and have bugs, so an exploit is not far-fetched, and a browser is the program that visits the most strangers' code.

This extra does not make Firefox bug-free. It limits what a taken-over Firefox can reach.

## The ideas behind it

**A Linux user.** Every account on a Linux computer is a user. Files have owners, and by default one user cannot read another user's private files. Normally you only have one user, and every program you start runs as you.

**A locked system user.** A user can be made with no password and no login shell, so nobody can sign in as it. It exists only to own things and to run one program. Here that user is called `firefox`. Its home folder is `/var/lib/debsway-firefox`, which only it can enter.

**sudo and a sudoers rule.** `sudo` lets one user run a command as another. A sudoers rule (a line in a file under `/etc/sudoers.d/`) says who may run what. The rule here lets your user run exactly one helper script as `firefox`, without a password, and nothing else. It is checked with `visudo` before it is installed, because a broken sudoers file can lock you out of sudo.

**A sandbox.** A box around a program that limits what it can touch. Here the box is a separate user plus the limits below. Think of a visitor in a room: they can use what is in the room and what you pass through the hatch, but not wander the house.

**Wayland and a socket.** Wayland is how programs draw windows on your sway desktop. A socket is a special file a program opens to talk to another program, here the window system. Whoever can open your real socket can also ask for screenshots or send keystrokes as if you typed them. The sandboxed Firefox is given a second, restricted socket instead.

**A firewall rule.** An instruction to the network layer to allow or refuse certain connections. Here it applies only to the sandboxed Firefox users.

**An ACL.** An access-control list adds a permission for one named user to a file or folder. It lets the `firefox` user reach a few things of yours without opening them to everyone.

## How it works, step by step

When you run `bash extras/firefox-sandbox.sh` (as your normal user, which uses sudo where needed):

1. It installs `firefox-esr`, `libavcodec61`, `webext-ublock-origin-firefox`, `acl`, `nftables`, `python3`, `dbus-daemon`, and PipeWire's pieces (`pipewire-bin`, `pipewire-pulse`, `wireplumber`), then runs `parts/firefox-hardening.sh` (see `docs/extras/firefox.md`). That gives every Firefox uBlock Origin in medium mode, HTTPS-Only Mode and no JavaScript JIT.
2. It creates the system user `firefox` (using `lib/firefox-sandbox.sh`): no password, shell `/usr/sbin/nologin`, home `/var/lib/debsway-firefox` mode 700, primary group `debsway-fx`, plus the `render` group so Firefox can open the graphics card's render node.
3. It installs `/usr/local/bin/firefox`, `/usr/local/libexec/firefox-session`, `wayland-restrict`, `debsway-no-abstract-sockets`, and the settings file `/usr/local/share/debsway/firefox-user.js`.
4. It writes `/etc/sudoers.d/debsway-firefox` and a limits file that caps processes at 4096 and switches off core dumps for everyone in `debsway-fx`.
5. It installs the firewall rule `/etc/debsway/firefox.nft` and a service `debsway-firefox-firewall`, loaded at every boot before the network. The rule matches the group `debsway-fx`. Those users may answer connections and do DNS lookups and reach the internet, but connections to this computer itself (any of its addresses), your router, private address ranges, and the local network are rejected.
6. It installs `~/.local/share/applications/debsway-firefox.desktop` and makes it your default handler for `http` and `https` links in `~/.config/mimeapps.list`. Links from a terminal or file manager now open in the sandboxed Firefox.

When you later run `firefox`:

1. It checks that you are in your sway session and that you may run the helper. If a sandboxed Firefox is already open (a lock file in your runtime folder), it only hands the link to it through the helper's `open` command and stops. Only `http://` and `https://` addresses are accepted.
2. Otherwise it starts `wayland-restrict`, which makes a second Wayland socket that sway marks as "sandboxed". Windows work through it, but sway does not offer the protocols that read the screen, type for you, or lock the session.
3. Using ACLs, it lets the `firefox` user pass through your home folder to `~/Downloads` (pass through only; it cannot list or read your home), reach the new socket, and read and write `~/Downloads`. These are taken back when the window closes. Anything it saves there is made readable and writable for you, and for nobody else, as it lands: Firefox may save a download as private, which would leave your ACL entry with no effect (the file's ACL *mask* would be empty), so the session sets the mask on what its user saved, every few seconds while it runs.
4. If PipeWire is running for you, it makes a named pipe (a one-way channel) and starts `pw-cat` as you to play whatever arrives in it.
5. It runs `firefox-session start` as `firefox` through sudo. The helper rewrites the profile's `user.js` at every start (a clean start page, tracking protection on, no telemetry, geolocation/camera/microphone/notification prompts refused, no prefetching, no hardware video decoding), keeps its runtime files in memory under `/dev/shm/firefox-run`, starts a private message bus, a small PipeWire of its own whose only output is the pipe, and then `firefox-esr`, through `debsway-no-abstract-sockets`. That program uses the kernel's Landlock feature so the browser cannot connect to X11's "abstract" sockets, which any user could otherwise reach.
6. When the window closes, the runtime folder, socket, pipe and ACLs are cleaned up. The profile in `/var/lib/debsway-firefox/profile` stays.

The private message bus is how a second `firefox URL` finds the running browser: `firefox-session open` sends the address there and opens a new tab.

## What it changes on your computer

- Packages: `firefox-esr`, `libavcodec61`, `webext-ublock-origin-firefox`, `acl`, `nftables`, `python3`, `dbus-daemon`, `pipewire-bin`, `pipewire-pulse`, `wireplumber`, and what the hardening part adds.
- Everything the Firefox hardening part writes (`/etc/firefox-esr/debsway-hardening.js`, `policies.json`, `ublock-allow`, the restart-notice timer).
- The user `firefox`, the group `debsway-fx`, the folder `/var/lib/debsway-firefox`.
- `/usr/local/bin/firefox`, `/usr/local/libexec/firefox-session` and `debsway-no-abstract-sockets`, `~/.local/bin/wayland-restrict`, `/usr/local/share/debsway/firefox-user.js`.
- `/etc/sudoers.d/debsway-firefox`, `/etc/security/limits.d/50-debsway-firefox.conf`.
- `/etc/debsway/firefox.nft` and the service `/etc/systemd/system/debsway-firefox-firewall.service`.
- `~/.local/share/applications/debsway-firefox.desktop` and `http`/`https` defaults in `~/.config/mimeapps.list`.
- While it runs: temporary access for the `firefox` user on `$XDG_RUNTIME_DIR`, `~/` and `~/Downloads`, and full access to `~/Downloads`.

## Using it

- `firefox` or Super+d: open the sandboxed Firefox. `firefox https://example.org/` opens a page, in the running window if there is one.
- `firefox --no-audio`: no sound pipe.
- `firefox-esr`: Firefox as you, with no sandbox. It stays installed.
- `sudo systemctl stop debsway-firefox-firewall`: lift the network rule for a while, for example to reach your router's page or a server on this computer. `sudo systemctl start debsway-firefox-firewall` puts it back.
- Copy and paste work while the Firefox window has focus. There is no KeePassXC browser add-on in debsway's build, so copy a password out of KeePassXC and paste it.
- To give a site its own sandboxed profile, see `docs/extras/firefox-profiles.md`.

## What it protects against

- **A browser exploit reaching your files.** The browser runs as a user with no password, login or home access of yours. Only `~/Downloads` is shared.
- **Reading your screen or typing for you.** The restricted socket does not offer those protocols.
- **Listening in.** It never gets your audio server, so it cannot hear your microphone or other programs. Sound leaves through one pipe in one direction.
- **Reaching your local network.** A hacked browser cannot connect to your router, printers, other computers, or programs listening on this machine.
- **X11 snooping.** Landlock stops it connecting to XWayland's abstract socket.
- **Your own programs reading the browser's logins.** The profile folder is mode 700, owned by `firefox`.

## What it doesn't protect against

- **A kernel bug.** The browser shares your kernel, so a bug there could still let it out.
- **An exploit that stays in the browser.** It can still use the logins and cookies kept in that profile, and send them anywhere on the internet.
- **What lands in `~/Downloads`.** It is shared both ways, so treat it as untrusted and do not run it unread.
- **The clipboard.** It is shared while the Firefox window has focus. Anything you copy then, including a password, is visible to the page's scripts if the browser is compromised.
- **Your identity on the network.** It uses your network and your IP address. Use a VPN or Tor Browser for that.
- **Anything you run as yourself**, including `firefox-esr` and links opened by programs that do not use the default browser setting.
- **Readable files elsewhere.** The `firefox` user is an ordinary user: files on the computer that any user can read are still readable by it.

## Removing it

If you made profiles with `firefox-profiles/new-profile.sh`, they run through this sandbox, so `--remove` first refuses, names them and tells you to remove each one (`bash extras/firefox-profiles/new-profile.sh --remove NAME`); nothing is changed until they are gone.

`bash extras/firefox-sandbox.sh --remove` stops and deletes the firewall service and rule, the sudoers rule, the limits file, the commands, the helper, the settings file, and the default-browser entry (links open in `firefox-esr` again). It removes the user `firefox` and the group `debsway-fx`, then asks whether to delete its profile in `/var/lib/debsway-firefox`; the default is no, so your logins and history stay. Firefox itself stays installed, as the Firefox extra's.
