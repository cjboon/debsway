# Tor Browser (`extras/tor-browser.sh`)

Tor Browser is a web browser that sends your traffic through the Tor network, so the sites you visit do not see your real internet address. This extra installs it the Debian way, through `torbrowser-launcher`, and starts it in its strictest mode with JavaScript off. If your network blocks Tor, it can also set up a bridge before the first connection.

## The problem it solves

Every website you visit sees the internet address (IP address) your connection comes from, and your internet provider sees which sites you go to. An address is a bit like the return address on a letter: it points back to your home or to the network you are on.

Tor Browser is for the times you do not want a site to learn that, or do not want your provider to see where you go. It also helps if you are somewhere that blocks Tor itself: the bridge options exist for that.

## The ideas behind it

**Tor.** Tor is a network of relays run by volunteers. Your traffic is wrapped in layers and passed through three relays. The first knows who you are but not where you are going. The last knows where you are going but not who you are. No single relay knows both. It is like passing a sealed letter through three people, each of whom can only open one layer of the envelope.

**Tor Browser.** Tor Browser is Firefox with Tor built in and many settings changed so that all its users look alike. That matters because a site can often recognise a browser by small details (screen size, fonts, plug-ins). If every Tor Browser looks the same, you are harder to pick out.

**Security level.** Tor Browser has a slider with three levels. Safest is the strictest: it switches off the web features that are most often used to attack browsers. This extra sets Safest and also turns JavaScript off completely. Many sites will look broken or refuse to work. That is the price of the setting.

**A bridge.** The list of Tor relays is public, so a network can block them. A bridge is a relay that is not on the public list. You need one if your network blocks Tor, or if you do not want it to see that you use Tor. Most people on a home connection do not need one. See "Bridges" in `docs/install-base.md` for the kinds. Tor Browser can use all of them: obfs4 (Tor's built-in list, or lines you get yourself), webtunnel, Snowflake and meek.

**A signature check.** A download can be swapped on the way. A signature is a mathematical stamp made with the developers' secret key; anyone can check it with their public key, and it fails if even one byte changed. `torbrowser-launcher` checks Tor Browser's signature when it downloads it.

## How it works, step by step

1. **Turns on Debian's `contrib` section.** `torbrowser-launcher` lives there, not in the main section. The script edits your apt sources (`/etc/apt/sources.list` and any deb822 `*.sources` files that point at debian.org). If it changed anything, it creates `/etc/apt/debsway-enabled-contrib` as a note to itself, so `--remove` knows to undo it.
2. **Installs `torbrowser-launcher` and `xz-utils`**, plus XWayland. Tor Browser runs on X11 on purpose (the script's comment says it is less fingerprintable), and XWayland lets X11 programs run under sway. Log out and back in once after the first X11 app, because sway only notices XWayland when it starts.
3. **Fixes Tor's AppArmor profile.** AppArmor is a Linux feature that limits which files a program may read. The package's profile lets Tor read `/etc/resolv.conf`, but that file is usually a link, and AppArmor checks the real file. Bridges given as host names (webtunnel) would then fail with "Temporary failure in name resolution". The script adds a few lines to `/etc/apparmor.d/local/torbrowser.Tor.tor` and reloads the profile.
4. **Installs a saved copy, if you have one.** If `prep/fetch-tor-browser.sh` saved Tor Browser into `offline/torbrowser`, the script checks its signature against the developers' key and unpacks it. Then torproject.org is never contacted.
5. **Asks about a bridge** (unless Tor Browser is running, in which case it asks you to quit it and run the script again). If you ran it before, it offers to keep the earlier bridge.
6. **Writes `user.js`** into Tor Browser's profile (`~/.local/share/torbrowser/tbb/<arch>/tor-browser/Browser/TorBrowser/Data/Browser/profile.default/`). A `user.js` file is a list of settings that Firefox-based browsers apply at every start. Yours contains the Safest settings from `data/tor-browser-safest.js` and, if you chose one, the bridge. Because it is re-applied each start, changing these in the browser's own menus does not last. Run the script again to change them.

Later, the first time you run `torbrowser-launcher`, it downloads Tor Browser from torproject.org and checks its signature. That first download does not go through Tor, so your network can see that you fetched it (not what you do with it). The launcher also keeps Tor Browser updated.

## What it changes on your computer

- Packages: `torbrowser-launcher`, `xz-utils`, XWayland.
- Debian's `contrib` section turned on in your apt sources, with the note file `/etc/apt/debsway-enabled-contrib`.
- A block of lines added to `/etc/apparmor.d/local/torbrowser.Tor.tor`.
- `user.js` in Tor Browser's profile folder, with the debsway lines between `// >>> debsway extras/tor-browser.sh >>>` and `// <<< debsway <<<`.
- If a bridge was chosen, any older bridge lines saved in `prefs.js` are removed so only yours are used.
- If you used a saved copy: `~/.config/torbrowser/settings.json` and the unpacked browser under `~/.local/share/torbrowser`.
- Nothing is added to `~/.local/bin`.

## Using it

- `torbrowser-launcher` starts Tor Browser (or press Super+d and type the name). The first run downloads it.
- Run `bash extras/tor-browser.sh` again to change the bridge or to repair the settings.

## What it protects against

- **Sites and your network learning where you connect from or where you go**, for what you do inside Tor Browser. Sites see a Tor relay's address. Your provider sees only that you talk to Tor.
- **Being told apart from other Tor users by browser details**, because Tor Browser is built to look the same for everyone.
- **A network that blocks or watches Tor**, if you choose a bridge. The bridge is set before the very first connection.
- **Many attacks through web pages**, because of the Safest level and JavaScript being off. This makes attacks harder, not impossible.
- **Name look-ups leaking.** Tor Browser looks up site names through Tor (`THREAT-MODEL.md`).

## What it doesn't protect against

- **Anything outside Tor Browser.** Other programs on your computer do not use Tor.
- **Telling a site who you are.** If you log in, the site knows who you are. Tor hides your address, not your identity.
- **The first download.** Your network sees you fetch Tor Browser from torproject.org, unless you used a saved copy.
- **A hacked browser finding your real address.** Tor Browser runs as you, on your computer. If an attack escapes it, it can read your files and see your real address. For that, use Whonix (`extras/whonix.sh`), where the browser sits in a VM whose only way out is Tor.
- **Writing style, habits and mistakes.** Opening a downloaded file outside Tor Browser, for example, can leak your address.
- **A determined, well-funded attacker** (`THREAT-MODEL.md`).
- **The Snowflake lines for Debian's client are untested** by the project. If a bridge fails, try another kind. (Tor Browser itself has Snowflake built in.)

## Removing it

`bash extras/tor-browser.sh --remove`:

- takes out the AppArmor lines it added, and reloads the profile so they stop applying at once;
- uninstalls `torbrowser-launcher` (and `xz-utils`, unless something else needs it);
- turns `contrib` off again, but only if this script was what turned it on;
- asks whether to delete the downloaded Tor Browser and its bookmarks (`~/.local/share/torbrowser`, `~/.cache/torbrowser`, `~/.config/torbrowser`). The default is no. If you say no, it removes only the debsway lines from `user.js`; the browser keeps those settings' last values.
