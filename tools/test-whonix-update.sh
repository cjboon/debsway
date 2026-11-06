#!/bin/bash
# Checks what `whonix update` runs inside the VMs: data/whonix-update (root's: apt) and
# data/whonix-update-browser (the user's: Tor Browser, keeping your profile), with pretend
# apt-get, curl, runuser and update-torbrowser. dpkg's version comparing and python are real.
# All of this was also run on a real Whonix 18 image, with a real update of Tor Browser,
# in QEMU: docs/extras/whonix.md says what was and wasn't. Run by test.sh, or:
#   bash tools/test-whonix-update.sh
# shellcheck disable=SC2016  # the inner shells and pretend programs expand their own variables
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
T=$(mktemp -d) || { echo "  FAIL  couldn't make a temp folder (is /tmp full?)"; exit 1; }
trap 'rm -rf "$T"' EXIT
fails=0
check() { # DESCRIPTION CONDITION-COMMAND...
    local what=$1
    shift
    if "$@" >/dev/null 2>&1; then printf '  ok    %s\n' "$what"; else printf '  FAIL  %s\n' "$what"; fails=$((fails + 1)); fi
}
not() { ! "$@"; }
mkdir -p "$T/bin"

# ---- Tor Browser (data/whonix-update-browser) ----
# curl: says $T/feed, or fails. update-torbrowser: as the real one, deletes the folder and
# puts a new one with a fresh profile there (at version $T/installs), or stops first ($T/tb-rc)
cat >"$T/bin/curl" <<PRETEND
#!/bin/sh
[ ! -e "$T/curl-fails" ] || exit 22
cat "$T/feed"
PRETEND
cat >"$T/bin/update-torbrowser" <<PRETEND
#!/bin/bash
echo ran >>"$T/tb-ran"
if [ -e "$T/tb-rc" ]; then exit "\$(cat "$T/tb-rc")"; fi
B=\$HOME/.tb/tor-browser
rm -rf "\$B"
mkdir -p "\$B/Browser/TorBrowser/Data/Browser/profile.default" "\$B/Browser/Downloads"
echo fresh >"\$B/Browser/TorBrowser/Data/Browser/profile.default/places.sqlite"
echo new-program >"\$B/Browser/firefox"
if [ ! -e "$T/no-version" ]; then
    printf '{"version":"%s","architecture":"linux-x86_64","channel":"release"}' "\$(cat "$T/installs")" >"\$B/Browser/tbb_version.json"
fi
exit 0
PRETEND
chmod +x "$T/bin/"*
H=$T/home
B=$H/.tb/tor-browser/Browser
P=$B/TorBrowser/Data/Browser/profile.default
KEEP=$H/.tb/tor-browser.wren-keep
yours() { # a browser at VERSION, with your things
    rm -rf "$H" "$T/tb-ran" "$T/tb-rc" "$T/curl-fails" "$T/no-version"
    mkdir -p "$P" "$B/Downloads"
    printf '{"version":"%s","architecture":"linux-x86_64","channel":"release"}' "$1" >"$B/tbb_version.json"
    echo my-bookmarks >"$P/places.sqlite"
    echo my-download >"$B/Downloads/a.pdf"
    echo old-program >"$B/firefox"
}
feed() { printf '{"version":"%s"}' "$1" >"$T/feed"; printf '%s' "$1" >"$T/installs"; }
tb() { env -i HOME="$H" PATH="$T/bin:/usr/bin:/bin" bash "$HERE/data/whonix-update-browser" >"$T/out" 2>&1; }
as_it_was() { # VERSION: everything there, nothing left over, nothing else run
    [ "$(cat "$P/places.sqlite")" = my-bookmarks ] && [ "$(cat "$B/Downloads/a.pdf")" = my-download ] &&
        [ "$(cat "$B/firefox")" = old-program ] && grep -q "\"$1\"" "$B/tbb_version.json" && [ ! -e "$KEEP" ]
}

yours 15.0.1; feed 16.0
tb; rc=$?
check "a newer version: it runs update-torbrowser, and says so" bash -c '[ "$1" = 0 ] && grep -q "15.0.1 to 16.0" "$2"' _ "$rc" "$T/out"
check "...your bookmarks and settings are there" test "$(cat "$P/places.sqlite")" = my-bookmarks
check "...your downloads too" test "$(cat "$B/Downloads/a.pdf")" = my-download
check "...in the new browser" bash -c '[ "$(cat "$1/firefox")" = new-program ] && grep -q "\"16.0\"" "$1/tbb_version.json"' _ "$B"
check "...and nothing of the old one is left" test ! -e "$KEEP"

yours 16.0; feed 16.0
tb; rc=$?
check "already the newest: update-torbrowser isn't run (it would delete your profile)" bash -c '[ "$1" = 0 ] && [ ! -e "$2" ]' _ "$rc" "$T/tb-ran"
check "...nothing changes" as_it_was 16.0

yours 16.0; feed 15.0.1
tb; rc=$?
check "the server offers an older version: refused, and it counts as a failure" bash -c '[ "$1" != 0 ] && [ ! -e "$2" ] && grep -q "could be an attack" "$3"' _ "$rc" "$T/tb-ran" "$T/out"
check "...nothing changes" as_it_was 16.0
# versions compared as versions, not as text
yours 9.5; feed 10.0
tb
check "10.0 is newer than 9.5 (compared as versions, not as text)" grep -q '"10.0"' "$B/tbb_version.json"

for bad in '{"version":"16.0; rm -rf ~"}' '{"version":"16.0.0.0.0.0.0.0.0.0.0.0"}' '{"version":16}' '{"other":"1"}' 'not json' ''; do
    yours 15.0.1
    printf '%s' "$bad" >"$T/feed"
    tb; rc=$?
    check "the server's answer isn't a version ($bad): a failure, nothing run" bash -c '[ "$1" != 0 ] && [ ! -e "$2" ]' _ "$rc" "$T/tb-ran"
    check "...nothing changes" as_it_was 15.0.1
done
yours 15.0.1; feed 16.0; : >"$T/curl-fails"
tb; rc=$?
check "no answer from the server: a failure, nothing changes" bash -c '[ "$1" != 0 ] && [ ! -e "$2" ]' _ "$rc" "$T/tb-ran"
check "...your things stay" as_it_was 15.0.1

yours 15.0.1; feed 16.0; echo 6 >"$T/tb-rc"
tb; rc=$?
check "update-torbrowser fails (Tor not up, a bad signature...): a failure" test "$rc" != 0
check "...the browser is back, whole, and your things" as_it_was 15.0.1

yours 15.0.1; feed 16.0; : >"$T/no-version"
tb; rc=$?
check "it says it worked, but no version can be read: a failure, and back as it was" bash -c '[ "$1" != 0 ]' _ "$rc"
check "...your things stay" as_it_was 15.0.1

# It asks the server again itself: the answer can change to an older one, and --noask installs that
yours 15.0.1; feed 16.0; printf '14.0' >"$T/installs"
tb; rc=$?
check "it installed an older one after all: a failure" test "$rc" != 0
check "...and the old browser is back" as_it_was 15.0.1
yours 15.0.1; feed 16.0; printf '15.0.1' >"$T/installs"
tb; rc=$?
check "...the same version (not higher): a failure too, and back" bash -c '[ "$1" != 0 ] && grep -q "\"15.0.1\"" "$2" && [ "$(cat "$3")" = old-program ]' _ "$rc" "$B/tbb_version.json" "$B/firefox"

rm -rf "$H" "$T/tb-ran" "$T/tb-rc"; mkdir -p "$H"; feed 16.0
tb; rc=$?
check "no browser in your home yet (before the first login): it installs one" bash -c '[ "$1" = 0 ] && grep -q "\"16.0\"" "$2"' _ "$rc" "$B/tbb_version.json"

# A power cut, at the worst places. The next run puts it right
yours 15.0.1; feed 15.0.1
mv "$H/.tb/tor-browser" "$KEEP"
tb; rc=$?
check "cut off after moving the old one aside, nothing new yet: all back" bash -c '[ "$1" = 0 ]' _ "$rc"
check "...your things are there" as_it_was 15.0.1
yours 15.0.1; feed 15.0.1
mv "$H/.tb/tor-browser" "$KEEP"
mkdir -p "$B"; echo half >"$B/firefox"
tb
check "cut off with a new browser half there: it goes, and all is back" as_it_was 15.0.1
# (the new one found good, one thing brought over and one not)
yours 15.0.1; feed 16.0
mv "$H/.tb/tor-browser" "$KEEP"
: >"$KEEP/.new-browser-ready"
mkdir -p "$B/TorBrowser/Data"
mv "$KEEP/Browser/TorBrowser/Data/Browser" "$B/TorBrowser/Data/Browser"
mkdir -p "$B/Downloads"
printf '{"version":"16.0"}' >"$B/tbb_version.json"
echo new-program >"$B/firefox"
tb; rc=$?
check "cut off while bringing your things over: it carries on, and loses nothing" bash -c '
    [ "$1" = 0 ] && [ "$(cat "$2/TorBrowser/Data/Browser/profile.default/places.sqlite")" = my-bookmarks ] &&
    [ "$(cat "$2/Downloads/a.pdf")" = my-download ] && [ "$(cat "$2/firefox")" = new-program ] && [ ! -e "$3" ]' _ "$rc" "$B" "$KEEP"

# The power goes while the old folder is being deleted, your things already in the new one.
# rm takes a folder's files in no fixed order, so the worst one: the "new browser is good"
# marker goes first, and then the script is dead (a pretend rm, killing it as a power cut would)
cat >"$T/bin/rm" <<PRETEND
#!/bin/bash
if [ -e "$T/cut-rm" ]; then
    for a; do
        if [ -e "\$a/.new-browser-ready" ]; then
            /bin/rm -f "$T/cut-rm" "\$a/.new-browser-ready"
            kill -9 "\$PPID"
            exit 137
        fi
    done
fi
exec /bin/rm "\$@"
PRETEND
chmod +x "$T/bin/rm"
yours 15.0.1; feed 16.0; : >"$T/cut-rm"
tb; rc=$?
check "the power goes while the old folder is deleted (the test really cut it off)" test "$rc" = 137
feed 16.0
tb; rc=$?
check "...the next run keeps the new browser: your bookmarks aren't deleted with a rollback" bash -c '
    [ "$1" = 0 ] && [ "$(cat "$2/TorBrowser/Data/Browser/profile.default/places.sqlite")" = my-bookmarks ] &&
    [ "$(cat "$2/Downloads/a.pdf")" = my-download ] && [ "$(cat "$2/firefox")" = new-program ]' _ "$rc" "$B"
check "...and what was left of the old folder is gone" bash -c '[ -z "$(ls -A "$1" | grep -v "^tor-browser$")" ]' _ "$H/.tb"
/bin/rm -f "$T/bin/rm"

# Files of yours elsewhere in the browser's folder (a page saved next to Downloads, a folder
# made in a save dialog): the old folder goes, so they are moved out first, not lost
L=$H/.tb/left-from-browser-15.0.1
yours 15.0.1; feed 16.0
echo my-page >"$B/saved-page.html"
mkdir "$B/.my-notes" && echo my-note >"$B/.my-notes/a"
mkdir -p "$B/.cache/x" "$B/.local/share" && echo trace >"$B/.cache/x/a" && echo recent >"$B/.local/share/recently-used.xbel"
tb; rc=$?
check "a file of yours elsewhere in the browser's folder isn't lost in an update" bash -c '[ "$1" = 0 ] && [ "$(cat "$2/saved-page.html")" = my-page ]' _ "$rc" "$L"
check "...a hidden folder neither" test "$(cat "$L/.my-notes/a" 2>/dev/null)" = my-note
check "...it says where they went" grep -q 'left-from-browser-15.0.1' "$T/out"
check "...but not the old browser's cache and recent files: those go with it" bash -c '[ ! -e "$1/.cache" ] && [ ! -e "$1/.local" ]' _ "$L"
check "...and the new browser's folder doesn't carry them (nothing old runs from there)" bash -c '[ ! -e "$1/saved-page.html" ] && [ ! -e "$1/.my-notes" ]' _ "$B"
yours 15.0.1; feed 16.0; echo 6 >"$T/tb-rc"
echo my-page >"$B/saved-page.html"
tb
check "a failed update leaves such a file where it was" test "$(cat "$B/saved-page.html" 2>/dev/null)" = my-page
yours 15.0.1; feed 16.0
tb
check "with nothing of the kind, no such folder is made" test ! -e "$L"

# ---- apt, as root (data/whonix-update) ----
# (a copy with its paths in the temp folder: nothing here is real, and no real apt is run)
mkdir -p "$T/root"
sed -e "s|^export PATH=.*|export PATH=$T/root:\$PATH|" -e "s|/usr/bin/update-torbrowser|$T/is-workstation|" \
    -e 's|WREN_UPDATE_PAUSE:-3|WREN_UPDATE_PAUSE:-0|' "$HERE/data/whonix-update" >"$T/update"
cat >"$T/root/apt-get" <<PRETEND
#!/bin/sh
echo "apt-get \$*" >>"$T/apt"
case " \$* " in
    *" update "*)
        if [ -s "$T/update-fails" ]; then sed -i 1d "$T/update-fails"; exit 100; fi
        [ ! -e "$T/never-online" ] || exit 100 ;;
    *" full-upgrade"*) [ ! -e "$T/upgrade-fails" ] || exit 100 ;;
esac
PRETEND
printf '#!/bin/sh\necho "dpkg $*" >>"%s/apt"\n' "$T" >"$T/root/dpkg"
printf '#!/bin/sh\necho "runuser $*" >>"%s/apt"\n[ ! -e "%s/browser-fails" ]\n' "$T" "$T" >"$T/root/runuser"
printf '#!/bin/sh\necho "mkhomedir_helper $*" >>"%s/apt"\n' "$T" >"$T/root/mkhomedir_helper"
chmod +x "$T/root/"*
vm() { # gateway|workstation
    rm -f "$T/apt" "$T/update-fails" "$T/never-online" "$T/upgrade-fails" "$T/browser-fails" "$T/is-workstation"
    if [ "$1" = workstation ]; then printf '#!/bin/sh\n' >"$T/is-workstation"; chmod +x "$T/is-workstation"; fi
}
up() { WREN_UPDATE_WAIT=0 WREN_UPDATE_TRIES=3 bash "$T/update" >"$T/out" 2>&1; sync; /bin/sleep 0.2; }
said() { grep -a '^WREN-RESULT: ' "$T/out" | tail -1; }

vm gateway; up
check "the Gateway: apt, and it says all went well" test "$(said)" = "WREN-RESULT: ok"
check "...nothing for Tor Browser" not grep -q '^runuser' "$T/apt"
check "...the lists, then the upgrade" bash -c 'grep -n "update\|full-upgrade" "$1" | cut -d" " -f2- | grep -q "" && [ "$(grep -n " update" "$1" | cut -d: -f1 | head -1)" -lt "$(grep -n "full-upgrade" "$1" | cut -d: -f1)" ]' _ "$T/apt"
check "...your config files kept (bridges depend on them), never the package's" bash -c '
    grep "full-upgrade" "$1" | grep -q "Dpkg::Options::=--force-confold" && grep "full-upgrade" "$1" | grep -q "Dpkg::Options::=--force-confdef" &&
    ! grep -q "confnew\|confmiss" "$1" && ! grep -v "^#" "$2" | grep -q "apt-get-noninteractive"' _ "$T/apt" "$HERE/data/whonix-update"
check "...a server out of reach is a failure (apt-get update exits 0 without this)" grep -q 'APT::Update::Error-Mode=any' "$T/apt"
check "...and what an earlier cut-off update left is finished first" bash -c 'head -1 "$1" | grep -q "^dpkg --force-confdef --force-confold --configure -a"' _ "$T/apt"
check "it never downgrades or removes what is essential by force" bash -c '! grep -q -- "--allow-\|--force-yes" "$1"' _ "$T/apt"

vm gateway; printf 'x\nx\n' >"$T/update-fails"; up
check "Tor still connecting: it waits and tries again" bash -c '[ "$(grep -c " update" "$1")" = 3 ] && [ "$2" = "WREN-RESULT: ok" ]' _ "$T/apt" "$(said)"
vm gateway; : >"$T/never-online"; up
check "never connects (Tor held off until you choose a bridge): a failure, no upgrade, and it doesn't get around that" bash -c '
    [ "$1" = "WREN-RESULT: failed: no connection to the update servers" ] && ! grep -q full-upgrade "$2"' _ "$(said)" "$T/apt"
vm gateway; : >"$T/upgrade-fails"; up
check "apt fails: a failure" test "$(said)" = "WREN-RESULT: failed: apt"
vm workstation; : >"$T/upgrade-fails"; up
check "...and Tor Browser isn't touched then" not grep -q '^runuser' "$T/apt"

vm workstation; up
check "the Workstation: apt, then Tor Browser" test "$(said)" = "WREN-RESULT: ok"
check "...as the user, with a session (Whonix's check that Tor is up needs one) but no ~/.profile" \
    grep -qx "runuser -l user -s /usr/local/libexec/wren-update-browser" "$T/apt"
vm workstation; : >"$T/browser-fails"; up
check "...Tor Browser fails: the whole update counts as failed" test "$(said)" = "WREN-RESULT: failed: Tor Browser"
check "...a result is the last thing it says, for the host to read" bash -c '[ "$(tail -n 1 "$1" | cut -d: -f1)" = WREN-RESULT ]' _ "$T/out"
check "nothing of the browser's folders is handled as root (a hacked browser can write there)" \
    not grep -qE '\.tb|tor-browser|Browser/' "$HERE/data/whonix-update"

# ---- the service, and how it gets into the images ----
S=$HERE/data/whonix-update.service
check "the service runs only with the host's note" grep -qx 'ConditionCredential=wren.update' "$S"
check "...before the desktop and any login" grep -qx 'Before=display-manager.service getty@tty1.service' "$S"
check "...and however it ends, the VM powers off" grep -qx 'ExecStopPost=/usr/bin/systemctl poweroff --no-block' "$S"
check "...it can't wait for ever" grep -qx 'TimeoutStartSec=3h' "$S"
check "started by a plain file (the images are written file by file, not links)" grep -qx 'Wants=wren-update.service' "$HERE/data/whonix-update-wants.conf"
X=$HERE/extras/whonix.sh
for f in 'data/whonix-update" /usr/local/libexec/wren-update' 'data/whonix-update.service" /etc/systemd/system/wren-update.service' \
    'data/whonix-update-wants.conf" /etc/systemd/system/multi-user.target.d/wren-update.conf'; do
    check "the install writes $f" grep -qF "$f" "$X"
done
check "...into the Gateway" bash -c 'sed -n "/^gateway_config()/,/^}/p" "$1" | grep -qF "\${UPDATE_FILES[@]}"' _ "$X"
check "...and the Workstation, with its browser script" bash -c '
    sed -n "/^ws_files=/,/)$/p" "$1" | grep -qF "\${UPDATE_FILES[@]}" &&
    sed -n "/^ws_files=/,/)$/p" "$1" | grep -qF -- "--exec \"\$WREN_DIR/data/whonix-update-browser\" /usr/local/libexec/wren-update-browser"' _ "$X"
check "the install starts the 7 days, and --remove forgets them" bash -c '
    grep -q "touch \"\$WHONIX_STAMP\"" "$1" && sed -n "/--remove ]; then/,/^fi/p" "$1" | grep -q "\$WHONIX_STAMP"' _ "$X"
check "both scripts parse" bash -c 'bash -n "$1" && bash -n "$2"' _ "$HERE/data/whonix-update" "$HERE/data/whonix-update-browser"
if command -v shellcheck >/dev/null; then
    check "...and shellcheck finds nothing" shellcheck -x -s bash "$HERE/data/whonix-update" "$HERE/data/whonix-update-browser"
fi

[ "$fails" -eq 0 ]
