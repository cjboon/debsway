# Firefox's hardening, and a throwaway window (part of `extras/firefox-sandbox.sh`)

This is what the sandboxed Firefox extra (`extras/firefox-sandbox.sh`, see [firefox-sandbox.md](firefox-sandbox.md)) sets up besides the sandbox itself. You get Firefox ESR with a few safer defaults for every profile: a blocker for scripts from other sites, no JavaScript JIT, and a refusal to load plain unencrypted pages without asking. You also get a notice when an update is waiting for a restart. If you say yes, you also get `incognito`, a separate Firefox that runs as a locked-down user and keeps nothing.

## The problem it solves

Most attacks on a normal computer arrive through the web browser. A page, or an advertisement on a page, runs code on your machine, and the browser has to decide what that code may do. Browsers have bugs, and some bugs let a page do more than it should.

Two more things go wrong quietly. Firefox is fixed by updates, but a copy that is already open keeps running the old, unfixed version until you close it. And when you open a site you do not trust, whatever it learns about you, or leaves behind in cookies, stays in your normal browser.

## The ideas behind it

**A browser exploit.** A bug that lets a web page make the browser do something its makers did not intend, such as running a program. Reducing what a page can do shrinks what an exploit can reach.

**JavaScript and the JIT.** Websites run small programs written in JavaScript. To make them fast, Firefox contains a JIT ("just in time" compiler) that turns JavaScript into machine code while you browse. It is complicated, and a large share of serious Firefox exploits aim at it. Turning it off makes JavaScript slower but removes a big target.

**uBlock Origin and "medium mode".** uBlock Origin is a content blocker. In medium mode it blocks scripts and frames (boxes that show another site's content) that come from a different site than the one you are looking at. Ad networks and trackers work this way, so this stops most of them. The cost is that some sites break.

**HTTPS.** The padlock kind of web address. It encrypts what travels between you and the site, so people on the same café Wi-Fi cannot read or change it. HTTPS-Only Mode makes Firefox ask before it opens a page that is not encrypted.

**A separate Linux user.** Linux keeps each person's files apart by giving every account its own user. A program running as another user cannot read your files. `incognito` uses this: Firefox runs as a user that owns nothing and has no password.

**A sandbox.** A box around a program that limits what it can touch. Here the box is made of a separate user, its own display, and a firewall rule. Think of a visitor given a room with no connecting doors, rather than the run of your house.

**Wayland and a socket.** Wayland is how programs draw windows on your sway desktop. A socket is a special file a program opens to talk to another program, here the window system. Whoever can open your real socket can also ask it to take screenshots or type keys for you. So `incognito` is given a second, restricted socket.

## How it works, step by step

When you run `bash extras/firefox-sandbox.sh`, besides the sandbox:

1. It installs `firefox-esr`, `libavcodec61` (video codecs), `webext-ublock-origin-firefox` (uBlock Origin from Debian) and `libnotify-bin` (for notifications).
2. It runs `parts/firefox-hardening.sh`, which:
   - Writes `/etc/firefox-esr/debsway-hardening.js`, a file of default settings for every profile. It turns on HTTPS-Only Mode and turns off the JIT parts (`javascript.options.ion`, `baselinejit`, `native_regexp`, `asmjs`). It also stops the Mozilla welcome and first-run pages and the "make Firefox your default browser" question, and makes a blank new-tab page with a dark fox wallpaper. A profile can still change these at `about:config`.
   - Installs `ublock-allow` to `/usr/local/bin` and runs it with `--refresh`. That writes `/usr/share/firefox-esr/distribution/policies.json`, the file Firefox reads for administrator settings. It holds uBlock's medium-mode rules, DuckDuckGo as the default search engine (also in private windows), no first-run or update pages, Firefox's own DNS over HTTPS switched off and locked, and uBlock allowed in private windows. A checksum in `.debsway-written` next to it marks the file as debsway's. If a `policies.json` that is not debsway's already exists, the script stops and leaves it alone.
   - Installs `firefox-restart-check` into `~/.local/bin` and a systemd user timer. The timer runs the check 2 minutes after you log in and every 10 minutes after that.
3. It asks whether to set up `incognito`. If you agree, it runs `parts/incognito.sh` (described next). If not, you can run `bash parts/incognito.sh` later.

**The restart notice.** When apt replaces Firefox's program file while a copy is open, the open copy's file shows as "(deleted)". `firefox-restart-check` looks for your `firefox-esr` processes in that state and shows one critical notification per process: "Firefox was updated. Restart Firefox". It only looks at processes owned by you.

**When a site breaks.** `ublock-allow example.com` adds the site to `/etc/firefox-esr/debsway-ublock-allow` and rewrites the policy; restart Firefox afterwards. `ublock-allow --list` shows the list and `ublock-allow --remove example.com` takes a site off. Changes made by clicking in uBlock's popup last only until Firefox restarts, because uBlock re-reads debsway's rules at every start.

### incognito

`parts/incognito.sh` installs `cage`, `acl`, PipeWire's pieces (`pipewire-bin`, `pipewire-pulse`, `wireplumber`), `nftables` and `python3`, then:

- Creates the system user `incognito`: locked password, shell `/usr/sbin/nologin`, no home folder, and no groups except its own and `render` (so it can open the graphics card's render node, which `cage` needs to start, but not take over the screen). A file in `/etc/security/limits.d/` caps its processes at 4096 and switches off core dumps.
- Installs the `incognito` command (`/usr/local/bin/incognito`), the helper `/usr/local/libexec/incognito-session`, `wayland-restrict` and `debsway-no-abstract-sockets`, and the settings file `/usr/local/share/debsway/incognito-user.js`.
- Writes a sudoers rule, `/etc/sudoers.d/debsway-incognito`. Sudo lets one user run commands as another; a sudoers rule says who may run what. This rule lets only your user run that one helper as `incognito`, with no password. It is checked with `visudo` before it is installed, because a broken sudoers file can lock you out of sudo.
- Installs a firewall rule (`data/incognito-firewall.nft`, a systemd service `debsway-incognito-firewall`, loaded at every boot). A firewall rule is an instruction to the network layer to refuse certain connections. This one applies only to the `incognito` user. It still allows DNS lookups and the internet, but rejects connections to the computer itself, your router, printers and other private-network addresses.

When you run `incognito`:

1. It starts `wayland-restrict`, which asks sway for a second socket marked "sandboxed" (sway's security-context feature, sway 1.9 or newer). Windows work through it, but sway does not offer it the protocols that read the screen, type for you or lock the session.
2. It gives the `incognito` user access to that socket only, using an access-control list (ACL: a per-user permission added to a file), and only while the window is open.
3. If PipeWire is running for you, it creates a named pipe (a one-way channel) and starts `pw-cat` as you to play whatever comes out of it.
4. It runs the helper as `incognito` through sudo. The helper makes a folder in `/dev/shm` (memory, not disk), writes the profile there, and starts `cage` (a tiny window system shown as one window in sway) running Firefox with `--no-remote`. It also starts a small PipeWire of its own whose only output is the pipe. The program is started through `debsway-no-abstract-sockets`, which uses the kernel's Landlock feature to stop it from connecting to X11's "abstract" sockets, which any user could otherwise reach.
5. The profile is always in private browsing (`data/incognito-user.js`): no history, form data, saved logins or disk cache, cookies deleted at close, tracking protection and fingerprint resistance on, and geolocation, camera, microphone, notifications and WebGL refused.
6. When you close the window, the memory folder is deleted and the access it was given is taken back.

Only `http://` and `https://` addresses are accepted: `incognito https://example.org/`. `incognito --no-audio` leaves the sound pipe out.

## What it changes on your computer

- Packages: `firefox-esr`, `libavcodec61`, `webext-ublock-origin-firefox`, `libnotify-bin`; for incognito also `cage`, `acl`, `pipewire-bin`, `pipewire-pulse`, `wireplumber`, `nftables`, `python3`.
- `/etc/firefox-esr/debsway-hardening.js` and `/etc/firefox-esr/debsway-ublock-allow`.
- `/usr/share/firefox-esr/distribution/policies.json` and `.debsway-written`.
- `/usr/local/bin/ublock-allow`; `~/.local/bin/firefox-restart-check`; user units `firefox-restart-check.service` and `.timer` in `~/.config/systemd/user/`.
- For incognito: the user `incognito`; `/usr/local/bin/incognito`; `/usr/local/libexec/incognito-session` and `debsway-no-abstract-sockets`; `~/.local/bin/wayland-restrict`; `/usr/local/share/debsway/incognito-user.js`; `/etc/sudoers.d/debsway-incognito`; `/etc/security/limits.d/50-debsway-incognito.conf`; `/etc/debsway/incognito.nft`; the service `debsway-incognito-firewall`.

## Using it

- `firefox-esr` (or Super+d): Firefox as you, hardened.
- `ublock-allow example.com`: let a broken site load other sites' scripts. Restart Firefox afterwards.
- `ublock-allow --list` and `ublock-allow --remove example.com`: see and undo.
- `incognito`: a throwaway window. `incognito https://example.org/` opens a page.
- `incognito --no-audio`: no sound.
- If uBlock breaks a video player in incognito, `ublock-allow site.com` applies there too. If fingerprint resistance breaks a site, you can set `privacy.resistFingerprinting` to false in `data/incognito-user.js` before installing.

## What it protects against

- **Drive-by attacks and malicious ads.** Scripts and frames from other sites are blocked, and the JIT, a favourite exploit target, is off.
- **Tampering on café or hotel Wi-Fi.** HTTPS-Only Mode refuses plain pages unless you agree.
- **Running an old, unfixed Firefox** without knowing it, because of the restart notice. It watches the Firefox you run as yourself (`firefox-esr`); the sandboxed `firefox`, its profiles and `incognito` run as other users and get no notice, so close and reopen those after an update.
- **Firefox choosing a DNS provider for you.** Its own DNS over HTTPS is off and locked. (Only when debsway wrote `policies.json`: if one of someone else's is already there, none of debsway's policy is applied, and the script warns.)
- **A risky site reaching the rest of your session** (`incognito`). A hacked Firefox there is a user that owns nothing, with no clipboard sharing, no shared folder and no screen reading. Nothing is kept after you close it. It cannot hear your microphone or your other programs, and the firewall rule keeps it off your local network.

## What it doesn't protect against

- Anything in the ordinary `firefox-esr`: it still runs as you, with all your files. For a stronger wall, use `extras/firefox-sandbox.sh`.
- Your network address. `incognito` uses your network and your IP address; use Tor Browser or a VPN for that.
- The kernel. `incognito` shares your computer's kernel, so a kernel bug could get out.
- Being seen by yourself and your tools: the `incognito` window is visible to you and to your screenshots like any window.
- Weaknesses of the web itself. Logging into a site identifies you to that site, and the hardening does not make sites you trust safe.
- The notice only watches Firefox started as you. It does not watch the sandboxed `firefox` or profile users, which run as other users.
- Pages are drawn by software in `incognito`, so heavy sites are slower, 1080p video may stutter, and protected (DRM) video does not play. The keyboard layout there is the US one.

## Removing it

`bash extras/firefox-sandbox.sh --remove` asks whether incognito goes too; if so it runs `parts/incognito.sh --remove` (stops and deletes the firewall rule and service, the sudoers rule, the limits file, the commands, the helper, and the `incognito` user), then `parts/firefox-hardening.sh --remove` (the timer, the check, the default settings, the allow list, and `policies.json` if it is still debsway's own), then removes the packages it installed unless another extra needs them. If you keep incognito, Firefox and its hardening stay with it. Your Firefox profiles, with bookmarks and logins, stay in `~/.mozilla` and `~/.config/mozilla`.
