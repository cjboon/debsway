# One Firefox profile per site (`extras/firefox-profiles/new-profile.sh`)

## SYNOPSIS

```
firefox --profiles                        the profiles there are: command, address, choices
firefox --choose-profiles                 check boxes for the ready-made ones: tick to make, untick to remove
firefox --new-profile NAME                a ready-made one: github, tutamail, chess, youtube... (34)
firefox --new-profile --list              the ready-made ones, by kind, with what each is
firefox --new-profile [NAME URL [...]]    your own (asks, without NAME and URL); Tab completes
firefox --remove-profile NAME             remove one (asks before deleting its logins and user)
firefox --profile NAME [URL]              open one (its own command, below, does the same)

bash ~/wren/extras/firefox-profiles/new-profile.sh                      the same, by the script: asks (a ready-made one, or yours)
bash ~/wren/extras/firefox-profiles/new-profile.sh NAME                 a ready-made one
bash ~/wren/extras/firefox-profiles/new-profile.sh --list               the ready-made ones
bash ~/wren/extras/firefox-profiles/new-profile.sh --choose             their check boxes
bash ~/wren/extras/firefox-profiles/new-profile.sh NAME URL [--fast-js] [--show-toolbars] [--no-sound] [--delete-cookies]
bash ~/wren/extras/firefox-profiles/new-profile.sh --remove NAME        asks before deleting its logins and user
bash ~/wren/extras/firefox-profiles/new-profile.sh --manual             print the manual steps below

NAME                open that site in its own profile (Super+d finds it too);
                    firefox-NAME when a program is called NAME already
  the window shows only the page: Alt+Left back, Alt+Right forward, F5 reload, Ctrl+W close
```

For a site you stay logged in to (a bank, email, shopping), a Firefox of its own with a command
named after it (`github`; `firefox-NAME` when a program has that name already, since `~/.local/bin`
comes first and the command would stand in for it): its own cookies, logins and history, run as its
own locked-down Linux user, `fx-NAME`, like the sandboxed Firefox's (`extras/firefox-sandbox.sh`,
which it needs), so a hacked page in one profile reaches neither your files nor the other profiles.

Only the clipboard and `~/Downloads/NAME` are shared with you. Its address and choices are in
`/etc/wren/firefox-profiles/NAME.conf`, a file only root can write. The window shows only the page,
without tabs, address bar or bookmarks bar (`--show-toolbars` keeps them).

`--no-sound` keeps it silent (a bank needs no sound). Its cookies and site data are kept, so you
stay logged in; `--delete-cookies` deletes them when it closes (run without NAME and URL it asks,
fast JavaScript and sound too).

`--fast-js` turns the JavaScript JIT back on for that profile only, for heavy web apps.

Ready-made ones (`data/firefox-profiles.list`, 34 of them: mail, AI chat, code, video, adult, chess,
social, chat, shopping, reference) come with settings chosen for their site: mail and code keep you
logged in; video, adult and chess sites forget everything when they close; video, chess and chat
apps get fast JavaScript; code and shopping show the address bar.

Sites that load their own code from a second domain (GitHub from githubassets.com, YouTube from
ytimg.com) would break in uBlock's medium mode, so making one of those also runs `ublock-allow` for
that site only; removing the profile leaves that exception.

None is made until you ask for it: each is a Linux user of its own. `firefox --choose-profiles`
shows them as check boxes, the ones you have ticked: tick to make, untick to remove (it asks before
deleting a profile's logins); your own profiles aren't listed.

Installing the sandboxed Firefox asks once whether to open it (default no).

## LIMITS

- Everything in the sandboxed Firefox's LIMITS applies to each profile.
- Without an address bar you can't see which page you're on: follow only links you expect.
- `--fast-js` brings back what most serious Firefox exploits target, for that site.
- A profile's command takes a name no program has when it is made. A package installed later with
  the same name is hidden behind it until you remove the profile (`type -a NAME` shows both).
- Kept cookies (the default) let the site recognise you on every visit; that is how you stay logged
  in.

## MANUAL INSTALL

Set up the sandboxed Firefox first ([firefox-sandbox.md](firefox-sandbox.md)). These steps make a
profile called `bank`; use your own name (lowercase letters, digits and dashes) and address.

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
# JIT, toolbars=shown for tabs and the address bar, sound=no for silence,
# cookies=delete to delete cookies and site data when it closes)
sudo install -d -o root -g root -m 0755 /etc/wren/firefox-profiles
printf 'url=%s\nfast_js=no\ntoolbars=hidden\nsound=yes\ncookies=keep\n' "$URL" | sudo tee /etc/wren/firefox-profiles/$NAME.conf

# Your user may run the session script, and nothing else, as fx-NAME. visudo
# checks the rule first: never put a rule in /etc/sudoers.d it hasn't passed.
printf '%s ALL=(fx-%s) NOPASSWD: /usr/local/libexec/firefox-session\n' "$(id -un)" "$NAME" >/tmp/wren-fx-$NAME
sudo visudo -cf /tmp/wren-fx-$NAME
sudo install -o root -g root -m 0440 /tmp/wren-fx-$NAME /etc/sudoers.d/wren-fx-$NAME
rm /tmp/wren-fx-$NAME

# The command, named NAME: first check no program has that name (this must
# print nothing; if it prints anything, call the command firefox-$NAME instead)
type -a $NAME
mkdir -p ~/.local/bin
printf '#!/bin/sh\n# Written by Wren Linux extras/firefox-profiles/new-profile.sh\nexec /usr/local/bin/firefox --profile %s "$@"\n' "$NAME" >~/.local/bin/$NAME
chmod +x ~/.local/bin/$NAME
$NAME
```

To undo (files it downloaded stay in `~/Downloads/NAME`):

```
NAME=bank
# The command (NAME or firefox-NAME: only the one Wren Linux wrote), the
# sudo rule and its settings
for c in ~/.local/bin/$NAME ~/.local/bin/firefox-$NAME; do grep -qs 'Written by Wren Linux extras/firefox-profiles' "$c" && rm "$c"; done
sudo rm /etc/sudoers.d/wren-fx-$NAME /etc/wren/firefox-profiles/$NAME.conf
# Its user, and its logins and history
sudo pkill -KILL -u fx-$NAME
sudo userdel fx-$NAME
sudo rm -rf /var/lib/wren-fx/$NAME /dev/shm/fx-$NAME-run
```
