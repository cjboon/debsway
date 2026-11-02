# Firefox as you (`extras/firefox-regular.sh`)

## SYNOPSIS

```
bash ~/debsway/extras/firefox-regular.sh            install it (asks about uBlock Origin, and links from other programs)
bash ~/debsway/extras/firefox-regular.sh --remove   remove it (asks before deleting its profile)
bash ~/debsway/extras/firefox-regular.sh --manual   print the manual steps below

firefox-regular [URL]     Firefox as you, with friendly defaults (or Super+d)
ublock-allow example.com  with uBlock and Firefox's hardening, if a site breaks
```

The easy everyday browser, for when the sandboxed Firefox's walls get in the
way: Firefox ESR from Debian, run as your own user in a profile of its own,
`~/.mozilla/firefox/debsway-regular`. Its `user.js` (`data/firefox-regular-user.js`)
keeps sites fast (the JavaScript JIT on), HTTPS-Only Mode on (one click to go
past it), Firefox's standard tracking protection, and nothing sent to Mozilla:
no telemetry, studies, sponsored tiles or Pocket. uBlock Origin, which blocks
ads and trackers, is your choice (default no): without it, this profile
doesn't load Debian's copy, which is shared by every Firefox profile and stays
in the others. It writes nothing system-wide, only that profile, a
`firefox-regular` command and a menu entry, so the sandboxed Firefox,
incognito and the per-site profiles are untouched and keep their own rules.
With uBlock, where Firefox's hardening is set up (it comes with the sandboxed
Firefox), uBlock's medium mode applies here too.

## LIMITS

- It runs as you: a hacked page can reach your files, keys and passwords. Use the sandboxed `firefox` for sites you don't trust.
- Its downloads land where you choose, with your rights: be careful what you open.
- It's your network and your address, as with any browser.
- Without uBlock, ads and the trackers in them load (Firefox's own tracking protection still blocks the known ones).
- `firefox-esr` with no `--profile` still opens Firefox's default profile, without these defaults.

## MANUAL INSTALL

```
# Firefox ESR and video codecs, from Debian (add webext-ublock-origin-firefox for uBlock Origin)
sudo apt install --no-install-recommends firefox-esr libavcodec61
# Its profile, readable only by you, with the friendly defaults
mkdir -p ~/.mozilla/firefox/debsway-regular
chmod 700 ~/.mozilla/firefox/debsway-regular
install -m 0600 @DEBSWAY_DIR@/data/firefox-regular-user.js ~/.mozilla/firefox/debsway-regular/user.js
# Without uBlock: this profile doesn't load add-ons from the system's folder,
# where Debian puts its copy for every profile (leave this out to have uBlock)
echo 'user_pref("extensions.enabledScopes", 5);' >>~/.mozilla/firefox/debsway-regular/user.js
# The command, and the menu entry Super+d and links use
install -D -m 0755 @DEBSWAY_DIR@/bin/firefox-regular ~/.local/bin/firefox-regular
install -D -m 0644 @DEBSWAY_DIR@/data/debsway-firefox-regular.desktop ~/.local/share/applications/debsway-firefox-regular.desktop
# Open links from other programs in it (in ~/.config/mimeapps.list, under
# [Default Applications], replacing an older default)
mkdir -p ~/.config && touch ~/.config/mimeapps.list
grep -qx '\[Default Applications\]' ~/.config/mimeapps.list || echo '[Default Applications]' >>~/.config/mimeapps.list
for t in x-scheme-handler/http x-scheme-handler/https text/html; do
    sed -i "\\|^$t=|d; /^\\[Default Applications\\]\$/a $t=debsway-firefox-regular.desktop" ~/.config/mimeapps.list
done
firefox-regular
```

To undo:

```
# Links no longer open in it, and its command and menu entry go
sed -i '/=debsway-firefox-regular\.desktop$/d' ~/.config/mimeapps.list
rm ~/.local/bin/firefox-regular ~/.local/share/applications/debsway-firefox-regular.desktop
# Its profile: your logins, history and bookmarks in it (only if you want them gone)
rm -rf ~/.mozilla/firefox/debsway-regular
# Firefox, if nothing else (the sandboxed Firefox, incognito) uses it: marked
# "automatic", autoremove takes it out only if nothing needs it
sudo apt-mark auto firefox-esr libavcodec61 webext-ublock-origin-firefox
sudo apt autoremove --purge
```
