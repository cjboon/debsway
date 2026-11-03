# One Firefox profile per site (`extras/firefox-profiles/new-profile.sh`)

## SYNOPSIS

```
bash ~/wren/extras/firefox-profiles/new-profile.sh                      asks for the name and address
bash ~/wren/extras/firefox-profiles/new-profile.sh NAME URL [--fast-js] [--show-toolbars] [--no-sound]
bash ~/wren/extras/firefox-profiles/new-profile.sh --remove NAME        asks before deleting its logins and user
bash ~/wren/extras/firefox-profiles/new-profile.sh --manual             print the manual steps below

firefox-NAME        open that site in its own profile (Super+d finds it too)
  the window shows only the page: Alt+Left back, Alt+Right forward, F5 reload, Ctrl+W close
```

For a site you stay logged in to (a bank, email, shopping), a Firefox of its
own with a `firefox-NAME` command: its own cookies, logins and history, run as
its own locked-down Linux user, `fx-NAME`, like the sandboxed Firefox's
(`extras/firefox-sandbox.sh`, which it needs), so a hacked page in one profile
reaches neither your files nor the other profiles. Only the clipboard and
`~/Downloads/NAME` are shared with you. Its address and choices are in
`/etc/wren/firefox-profiles/NAME.conf`, a file only root can write. The
window shows only the page, without tabs, address bar or bookmarks bar
(`--show-toolbars` keeps them). `--no-sound` keeps it silent (a bank needs no
sound; run without NAME and URL it asks, fast JavaScript too). `--fast-js` turns the JavaScript JIT back on
for that profile only, for heavy web apps.

## LIMITS

- Everything in the sandboxed Firefox's LIMITS applies to each profile.
- Without an address bar you can't see which page you're on: follow only links you expect.
- `--fast-js` brings back what most serious Firefox exploits target, for that site.

## MANUAL INSTALL

Set up the sandboxed Firefox first ([firefox-sandbox.md](firefox-sandbox.md)).
These steps make a profile called `bank`; use your own name (lowercase
letters, digits and dashes) and address.

```
NAME=bank URL=https://mybank.example
# Its user: in the sandboxed Firefox's group, no password, no login shell,
# a home only it can enter; render for the GPU's render node
sudo mkdir -p /var/lib/wren-fx
sudo useradd --system --gid wren-fx --create-home --home-dir /var/lib/wren-fx/$NAME --shell /usr/sbin/nologin --comment "Wren Linux Firefox profile $NAME" fx-$NAME
sudo usermod --lock --shell /usr/sbin/nologin fx-$NAME
sudo chmod 0700 /var/lib/wren-fx/$NAME
sudo usermod -aG render fx-$NAME

# Its address and choices, in a file only root can write (fast_js=yes for the
# JIT, toolbars=shown for tabs and the address bar, sound=no for silence)
sudo install -d -o root -g root -m 0755 /etc/wren/firefox-profiles
printf 'url=%s\nfast_js=no\ntoolbars=hidden\nsound=yes\n' "$URL" | sudo tee /etc/wren/firefox-profiles/$NAME.conf

# Your user may run the session script, and nothing else, as fx-NAME. visudo
# checks the rule first: never put a rule in /etc/sudoers.d it hasn't passed.
printf '%s ALL=(fx-%s) NOPASSWD: /usr/local/libexec/firefox-session\n' "$(id -un)" "$NAME" >/tmp/wren-fx-$NAME
sudo visudo -cf /tmp/wren-fx-$NAME
sudo install -o root -g root -m 0440 /tmp/wren-fx-$NAME /etc/sudoers.d/wren-fx-$NAME
rm /tmp/wren-fx-$NAME

# The firefox-NAME command
mkdir -p ~/.local/bin
printf '#!/bin/sh\n# Written by Wren Linux extras/firefox-profiles/new-profile.sh\nexec /usr/local/bin/firefox --profile %s "$@"\n' "$NAME" >~/.local/bin/firefox-$NAME
chmod +x ~/.local/bin/firefox-$NAME
firefox-$NAME
```

To undo (files it downloaded stay in `~/Downloads/NAME`):

```
NAME=bank
# The command, the sudo rule and its settings
rm ~/.local/bin/firefox-$NAME
sudo rm /etc/sudoers.d/wren-fx-$NAME /etc/wren/firefox-profiles/$NAME.conf
# Its user, and its logins and history
sudo pkill -KILL -u fx-$NAME
sudo userdel fx-$NAME
sudo rm -rf /var/lib/wren-fx/$NAME /dev/shm/fx-$NAME-run
```
