#!/bin/bash
# Checks the sandboxed Firefox (bin/firefox, bin/firefox-session, the extra and
# its firewall) with pretend sudo, setfacl and wayland-restrict, a pretend
# Wayland socket and a pretend "id". Nothing is started and nothing outside a
# temp folder is changed. Run by test.sh, or:  bash tools/test-firefox-sandbox.sh
# shellcheck disable=SC2016,SC2088,SC2010,SC2317,SC1007  # patterns name shell variables literally; die() runs in the eval
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

T=$(mktemp -d) || { echo "  FAIL  couldn't make a temp folder (is /tmp full?)"; exit 1; }
trap 'rm -rf "$T"; kill $(jobs -p) 2>/dev/null' EXIT
fails=0
check() { # DESCRIPTION CONDITION-COMMAND...
    local what=$1
    shift
    if "$@" >/dev/null 2>&1; then printf '  ok    %s\n' "$what"; else printf '  FAIL  %s\n' "$what"; fails=$((fails + 1)); fi
}
not() { ! "$@"; }
command -v flock >/dev/null || { echo "  ok    skipped: flock isn't installed"; exit 0; }

mkdir -p "$T/fake" "$T/run" "$T/home" "$T/shm"
# sudo: -l says yes; "start" stays up a while (a running Firefox); anything else is written down
# shellcheck disable=SC2016  # written into the pretend programs, expanded when they run
cat >"$T/fake/sudo" <<FAKE
#!/bin/bash
echo "sudo \$*" >>"$T/calls"
case " \$* " in
    *" -l "*) exit 0 ;;
    *" start "*) sleep "\${FAKE_UP:-0.1}" ;;
esac
FAKE
# shellcheck disable=SC2016
printf '#!/bin/bash\necho "setfacl $*" >>"%s/calls"\n' "$T" >"$T/fake/setfacl"
# wayland-restrict: says it is ready, then waits until its input closes
printf '#!/bin/sh\necho ready\ncat >/dev/null\n' >"$T/fake/wayland-restrict"
chmod +x "$T/fake/"*
python3 -I -c 'import socket,sys; s=socket.socket(socket.AF_UNIX); s.bind(sys.argv[1]); import time; time.sleep(30)' "$T/run/wayland-1" &
sleep 0.3
fx() { env PATH="$T/fake:$PATH" HOME="$T/home" XDG_RUNTIME_DIR="$T/run" WAYLAND_DISPLAY=wayland-1 WREN_SHARE_ROOT="$T/shm" bash "$HERE/bin/firefox" "$@"; }

# 1. the first start
: >"$T/calls"
fx --no-audio https://example.org/
check "the first start runs the session as the firefox user" grep -q 'sudo -n -u firefox /usr/local/libexec/firefox-session start' "$T/calls"
check "...with its private folder, the restricted socket, no sound, your Downloads, the theme (dark), no picture and the address" \
    grep -qE "firefox-session start $T/shm/wren-firefox\.[A-Za-z0-9]+ firefox-wayland - $T/home/Downloads dark - https://example.org/" "$T/calls"
check "it gave the firefox user the socket and a way through to ~/Downloads, not the whole home" \
    grep -qE "setfacl -m u:firefox:--x $T/shm/wren-firefox\.[A-Za-z0-9]+ $T/home" "$T/calls"
check "...read and write on ~/Downloads, for both of you, for later files too" \
    grep -q "setfacl -P -d -m u:firefox:rwx,u:$(id -un):rwx $T/home/Downloads" "$T/calls"
check "...and took the access back when it ended" grep -q "setfacl -x u:firefox $T/home" "$T/calls"
check "~/Downloads exists" test -d "$T/home/Downloads"

# 1b. started with a PATH without ~/.local/bin (lib.sh's, so gh from git-helper.sh):
# wayland-restrict is still found there
mkdir -p "$T/fake-nolocal" "$T/home/.local/bin"
cp "$T/fake/sudo" "$T/fake/setfacl" "$T/fake-nolocal/"
cp "$T/fake/wayland-restrict" "$T/home/.local/bin/"
: >"$T/calls"
env PATH="$T/fake-nolocal:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" HOME="$T/home" XDG_RUNTIME_DIR="$T/run" WAYLAND_DISPLAY=wayland-1 WREN_SHARE_ROOT="$T/shm" \
    bash "$HERE/bin/firefox" --no-audio https://example.org/ >/dev/null 2>&1
check "a PATH without ~/.local/bin (Wren Linux's scripts): wayland-restrict is found there, it starts" grep -q 'firefox-session start' "$T/calls"
check "...so do incognito and the media viewer" bash -c 'for f in incognito media-sandbox; do grep -qx "restrict=\$HOME/.local/bin/wayland-restrict" "$1/bin/$f" || exit 1; done' _ "$HERE"
rm "$T/home/.local/bin/wayland-restrict"

# 2. a link while it is open goes to the running Firefox
: >"$T/calls"
FAKE_UP=3 fx --no-audio >/dev/null 2>&1 &
sleep 1
fx https://example.org/next
check "a second start while it is open opens the address in that Firefox" grep -qF 'firefox-session open https://example.org/next' "$T/calls"
check "...and does not start another" test "$(grep -c 'firefox-session start' "$T/calls")" -eq 1
wait %2 2>/dev/null

# 2a. a profile's downloads folder swapped for a link (the sandboxed Firefox
# can write in ~/Downloads): refused, no rights go anywhere
mkdir -p "$T/home/.ssh"
rm -rf "$T/home/Downloads/swapped"
ln -s "$T/home/.ssh" "$T/home/Downloads/swapped"
: >"$T/calls"
out=$(fx --no-audio --profile swapped 2>&1)
check "a profile's downloads folder that is a link (to ~/.ssh, say): refused, no rights given on it" bash -c '
    grep -q "isn.t a folder of yours" <<<"$1" && ! grep -q "fx-swapped:rwx" "$2"' _ "$out" "$T/calls"
rm -f "$T/home/Downloads/swapped"

# 2b. a profile with its own user runs next to it, with its own names and downloads folder
: >"$T/calls"
FAKE_UP=2 fx --no-audio https://example.org/ >/dev/null 2>&1 &
sleep 0.6
fx --no-audio --profile bank
check "a profile starts as its own user, next to the other Firefox" grep -qE "sudo -n -u fx-bank /usr/local/libexec/firefox-session start $T/shm/wren-firefox-bank\.[A-Za-z0-9]+ firefox-bank-wayland - $T/home/Downloads/bank dark -" "$T/calls"
check "...with its own downloads folder, so profiles cannot read each other's files" test -d "$T/home/Downloads/bank"
check "...and rights only for its own user on it" grep -q "setfacl -P -m u:fx-bank:rwx $T/home/Downloads/bank" "$T/calls"
check "...the main Firefox's, inherited from ~/Downloads, taken off its folder and what is in it" grep -qF "setfacl -P -R -x u:firefox,d:u:firefox $T/home/Downloads/bank" "$T/calls"
check "...and not the other user's" not grep -q "u:firefox:rwx $T/home/Downloads/bank" "$T/calls"
# closing the profile takes back only its own user's rights: the Firefox still
# open next to it keeps its way through your home folder to ~/Downloads
check "closing the profile takes back only its own user's access" grep -q "setfacl -x u:fx-bank $T/home $T/home/Downloads" "$T/calls"
wait
: >"$T/calls"
FAKE_UP=2 fx --profile bank https://bank.example/ >/dev/null 2>&1 &
sleep 0.6
fx --profile bank https://bank.example/next
check "a second start of the same profile opens in that profile's Firefox" grep -qF 'sudo -n -u fx-bank /usr/local/libexec/firefox-session open https://bank.example/next' "$T/calls"
wait
: >"$T/calls"
check "a profile name with a slash or capitals is refused" not fx --profile '../x'
check "...and so is one that is too long to be a user name" not fx --profile abcdefghijklmnopqrstuvwxyzabcdefghij
check "...before anything is run as another user" test ! -s "$T/calls"

# 3. what it refuses
: >"$T/calls"
check "an address that is not http or https is refused" not fx 'file:///etc/passwd'
check "...and so is javascript:" not fx 'javascript:alert(1)'
check "...before anything is run as the other user" test ! -s "$T/calls"
check "it refuses to run as root" grep -q 'run it as your normal user' "$HERE/bin/firefox"

# 4. The session only accepts what its caller may send. It resets its own PATH, so it
# cannot be tricked into thinking it is the firefox user from here; instead its own
# 2c. the theme and your New Tab picture
wait 2>/dev/null
mkdir -p "$T/home/.config/wren" "$T/home/Pictures/wren/firefox"
echo light >"$T/home/.config/wren/theme"
printf '\x89PNG\r\n\x1a\n' >"$T/home/Pictures/wren/firefox/old.png"
touch -d '2026-01-01' "$T/home/Pictures/wren/firefox/old.png"
printf '\xff\xd8\xff\xe0 newest' >"$T/home/Pictures/wren/firefox/new.jpg"
printf 'not a picture' >"$T/home/Pictures/wren/firefox/newest.png"
# (the pretend sudo keeps a copy of the picture while "Firefox" runs)
cat >"$T/fake/sudo" <<FAKE
#!/bin/bash
echo "sudo \$*" >>"$T/calls"
case " \$* " in
    *" -l "*) exit 0 ;;
    *" start "*) for p in "$T"/shm/wren-firefox.*/firefox-newtab.*; do [ -e "\$p" ] && cp "\$p" "$T/handed"; done ;;
esac
FAKE
: >"$T/calls"; rm -f "$T/handed"
fx --no-audio
check "the light theme: the session is told light" grep -qE "firefox-session start $T/shm/wren-firefox\.[A-Za-z0-9]+ firefox-wayland - $T/home/Downloads light firefox-newtab.jpg" "$T/calls"
check "your New Tab picture: the newest real one is handed over (one named .png that isn't a picture is passed over)" \
    bash -c 'grep -q newest "$1"' _ "$T/handed"
check "...readable by firefox alone, under the one name the session accepts" grep -qE "setfacl -m u:firefox:r-- $T/shm/wren-firefox\.[A-Za-z0-9]+/firefox-newtab.jpg" "$T/calls"
check "...and gone again when Firefox closes" bash -c '! ls "$1"/wren-firefox.*/firefox-newtab.jpg' _ "$T/shm"
: >"$T/calls"
fx --no-audio --profile bank
check "...a profile gets the theme, never the picture" grep -qF "firefox-bank-wayland - $T/home/Downloads/bank light -" "$T/calls"
rm -rf "$T/home/.config/wren" "$T/home/Pictures"
# validation lines are run against good and bad values.
bad_arg() { # LINE-PATTERN VALUE VAR: does the script's check for VAR refuse VALUE?
    local line
    line=$(grep -F -m1 "$1" "$HERE/bin/firefox-session")
    [ -n "$line" ] || return 1
    # shellcheck disable=SC2329  # die is called by the line run through eval
    ( die() { exit 1; }; export "$3=$2"; eval "${line//\[ -S*/true}" ) 2>/dev/null && return 1 || return 0
}
ok_arg() { ! bad_arg "$@"; }
host_dir= host_wl= audio= downloads= theme= picture=
check "a folder other than its own private one is refused" bad_arg 'unexpected socket folder' /run/user/1000 host_dir
check "...and its own is accepted" ok_arg 'unexpected socket folder' /dev/shm/wren-firefox.AbCd1234 host_dir
check "a Wayland name with a slash is refused" bad_arg 'unexpected Wayland display name' ../x host_wl
check "...and wayland-1 is accepted" ok_arg 'unexpected Wayland display name' wayland-1 host_wl
check "a sound pipe name it did not expect is refused" bad_arg 'unexpected sound pipe name' /etc/passwd audio
check "...and firefox-audio.fifo or - are accepted" ok_arg 'unexpected sound pipe name' firefox-audio.fifo audio
check "a theme other than light or dark is refused" bad_arg 'unexpected theme' 'dark;id' theme
check "...light is accepted" ok_arg 'unexpected theme' light theme
check "a picture name other than firefox-newtab.jpg or .png is refused" bad_arg 'unexpected picture name' ../../etc/passwd picture
check "...firefox-newtab.png is accepted" ok_arg 'unexpected picture name' firefox-newtab.png picture
check "a downloads folder other than /home/NAME/Downloads is refused" bad_arg 'unexpected downloads folder' /etc downloads
check "...also one that climbs out with .." bad_arg 'unexpected downloads folder' '/home/a/../../etc/Downloads' downloads
check "...and /home/me/Downloads is accepted" ok_arg 'unexpected downloads folder' /home/me/Downloads downloads
# a profile's user may use only its own folder
tag=bank
check "a profile accepts /home/me/Downloads/bank" ok_arg '/Downloads/$tag$' /home/me/Downloads/bank downloads
check "...not the shared Downloads folder" bad_arg '/Downloads/$tag$' /home/me/Downloads downloads
check "...and not another profile's" bad_arg '/Downloads/$tag$' /home/me/Downloads/shop downloads
check "a profile is never given a New Tab picture" bad_arg 'unexpected picture name' firefox-newtab.png picture
tag=''
check "the session accepts the users firefox and fx-NAME only" python3 -I -c '
s = open(__import__("sys").argv[1]).read()
assert "    firefox) tag= ;;" in s and "    fx-*)" in s and "this runs as the user firefox (or fx-NAME)" in s
' "$HERE/bin/firefox-session"
# the choices made at install (/etc/wren/firefox.conf), run with a copy of it
conf_lines() { # FILE PATTERN: the lines of FILE from PATTERN up to the profiles' part, reading $T/fx.conf instead
    sed -n "/$2/,/^# A profile with its own user/p" "$1" | sed '$d' | sed "s|/etc/wren/firefox.conf|$T/fx.conf|g"
}
# The theme follows on a profile that has run: Firefox's add-on list says
# which theme is active, and the session marks the one asked for
mkdir -p "$T/th"
printf '%s' '{"schemaVersion":37,"addons":[{"id":"firefox-compact-light@mozilla.org","type":"theme","active":true,"userDisabled":false},{"id":"firefox-compact-dark@mozilla.org","type":"theme","active":false,"userDisabled":true},{"id":"uBlock0@raymondhill.net","type":"extension","active":true,"userDisabled":false}]}' >"$T/th/extensions.json"
( profile=$T/th; eval "$(sed -n '/^set_theme_addon() {/,/^}$/p' "$HERE/bin/firefox-session")"; set_theme_addon firefox-compact-dark@mozilla.org ) 2>/dev/null
check "a profile that ran light starts dark when dark is asked for (its add-on list says so)" python3 -I -c '
import json, sys; a = {x["id"]: x for x in json.load(open(sys.argv[1]))["addons"]}
assert a["firefox-compact-dark@mozilla.org"]["active"] and not a["firefox-compact-dark@mozilla.org"]["userDisabled"]
assert not a["firefox-compact-light@mozilla.org"]["active"] and a["firefox-compact-light@mozilla.org"]["userDisabled"]
assert a["uBlock0@raymondhill.net"]["active"] and json.load(open(sys.argv[1]))["schemaVersion"] == 37
' "$T/th/extensions.json"
check "...and the session does it at every start, for the theme it was given" grep -qx 'set_theme_addon "firefox-compact-$theme@mozilla.org"' "$HERE/bin/firefox-session"
printf 'fast_js=yes\nsound=no\ndefault_browser=no\n' >"$T/fx.conf"
mkdir -p "$T/prof"
: >"$T/prof/user.js"
( profile=$T/prof tag=; eval "$(conf_lines "$HERE/bin/firefox-session" '^jit_on() {')" ) 2>/dev/null
check "fast JavaScript chosen: the main Firefox gets the JIT back" grep -qx 'user_pref("javascript.options.ion", true);' "$T/prof/user.js"
: >"$T/prof/user.js"
printf 'fast_js=no\ncookies=delete\n' >"$T/fx.conf"
( profile=$T/prof tag=; eval "$(conf_lines "$HERE/bin/firefox-session" '^jit_on() {')" ) 2>/dev/null
check "...not chosen: it stays off" not grep -q 'javascript.options.ion' "$T/prof/user.js"
check "cookies, site data and the cache are deleted when it closes (delete chosen), history kept" bash -c '
    grep -qx "user_pref(\"privacy.sanitize.sanitizeOnShutdown\", true);" "$1" &&
    grep -qx "user_pref(\"privacy.clearOnShutdown_v2.cookiesAndStorage\", true);" "$1" &&
    grep -qx "user_pref(\"privacy.clearOnShutdown_v2.cache\", true);" "$1" &&
    grep -qx "user_pref(\"privacy.clearOnShutdown_v2.historyFormDataAndDownloads\", false);" "$1" &&
    grep -qx "user_pref(\"privacy.clearOnShutdown_v2.browsingHistoryAndDownloads\", false);" "$1"' _ "$T/prof/user.js"
: >"$T/prof/user.js"
printf 'cookies=keep\n' >"$T/fx.conf"
( profile=$T/prof tag=; eval "$(conf_lines "$HERE/bin/firefox-session" '^jit_on() {')" ) 2>/dev/null
check "...keep chosen: they stay" grep -qx 'user_pref("privacy.sanitize.sanitizeOnShutdown", false);' "$T/prof/user.js"
: >"$T/prof/user.js"
printf 'fast_js=no\n' >"$T/fx.conf"
( profile=$T/prof tag=; eval "$(conf_lines "$HERE/bin/firefox-session" '^jit_on() {')" ) 2>/dev/null
check "...an install from before the question (no answer saved): they stay, nothing deleted unasked" grep -qx 'user_pref("privacy.sanitize.sanitizeOnShutdown", false);' "$T/prof/user.js"
: >"$T/prof/user.js"
printf 'fast_js=yes\n' >"$T/fx.conf"
( profile=$T/prof tag=-bank; eval "$(conf_lines "$HERE/bin/firefox-session" '^jit_on() {')" ) 2>/dev/null
check "...and the main Firefox's choices aren't a profile's (it keeps its cookies: that is what it is for)" test ! -s "$T/prof/user.js"
# sound: the main Firefox's choice from its file, a profile's from its own
sound_of() { # NAME (empty: the main Firefox): what the firefox command decides
    local name=$1 audio=true PROFILES=$T/prof
    eval "$(sed -n '/^# sound off when that was the choice/,/|| audio=false$/p' "$HERE/bin/firefox" |
        sed "s|/etc/wren/firefox.conf|$T/fx.conf|")"
    echo "$audio"
}
mkdir -p "$T/prof"
printf 'sound=no\n' >"$T/fx.conf"
printf 'sound=yes\n' >"$T/prof/bank.conf"
check "sound chosen off: the main Firefox starts without sound" test "$(sound_of '')" = false
check "...but a profile follows its own choice, not the main one's" test "$(sound_of bank)" = true
printf 'sound=yes\n' >"$T/fx.conf"
printf 'sound=no\n' >"$T/prof/bank.conf"
check "...a profile with sound off is silent, the main Firefox not" bash -c '[ "$1" = false ] && [ "$2" = true ]' _ "$(sound_of bank)" "$(sound_of '')"
rm -f "$T/prof/bank.conf"
check "...never asked (no file): with sound" test "$(sound_of bank)" = true
check "the install asks about cookies (delete or keep, default delete), explained, history and passwords kept" python3 -I -c '
import sys; s = open(sys.argv[1]).read()
assert "choose cookies \"When Firefox closes, its cookies and site data:\" \"$cookies\" delete keep" in s and "cookies=delete" in s
assert "Manage Exceptions" in s and "History, bookmarks and saved passwords stay either way" in s and "\"cookies=$cookies\"" in s
' "$HERE/extras/firefox-sandbox.sh"
check "Firefox's fingerprinting protection is on (gentler than incognito's)" grep -qx 'user_pref("privacy.fingerprintingProtection", true);' "$HERE/data/firefox-user.js"
check "saved passwords fill in on a click, not as the page loads" grep -qx 'user_pref("signon.autofillForms", false);' "$HERE/data/firefox-user.js"
check "the install asks about fast JavaScript (default no), sound and links (default yes), last answers first" python3 -I -c '
import sys; s = open(sys.argv[1]).read()
assert "fast=n sound=y links=y" in s
for q in ("Turn on fast JavaScript?", "Sound in Firefox", "Open links from other programs in it"):
    assert q in s, q
assert s.index("chosen fast_js") < s.index("Turn on fast JavaScript?")
' "$HERE/extras/firefox-sandbox.sh"
check "...writes the answers where only root can change them" grep -q 'sudo tee "$CHOICES"' "$HERE/extras/firefox-sandbox.sh"
check "...links not wanted: it stops being the default browser" python3 -I -c '
import sys; s = open(sys.argv[1]).read(); d = s.index("say \"Default browser\"")
b = s[d:s.index("say \"incognito\"", d)]
assert "if [ \"$links\" = yes ]; then" in b and "unset_default_app wren-firefox.desktop" in b
' "$HERE/extras/firefox-sandbox.sh"
check "...and --remove takes the answers away" grep -q 'sudo rm -f /etc/wren/firefox.conf' "$HERE/extras/firefox-sandbox.sh"
# what the session writes for the theme and the picture, run on a temp profile
session_theme() { # THEME PICTURE: the session's lines, with $T/rt as its private folder
    mkdir -p "$T/tp" "$T/rt"
    : >"$T/tp/user.js"
    ( profile=$T/tp host_dir=$T/rt theme=$1 picture=$2
      eval "$(sed -n '/^# Light or dark (bin\/theme)/,/^# fast JavaScript:/p' "$HERE/bin/firefox-session")" ) 2>/dev/null
}
session_theme light -
check "light: Firefox's light theme, websites told light, the light fox" bash -c '
    grep -qx "user_pref(\"extensions.activeThemeID\", \"firefox-compact-light@mozilla.org\");" "$1" &&
    grep -qx "user_pref(\"layout.css.prefers-color-scheme.content-override\", 1);" "$1" &&
    grep -q "light-fox-anniversary" "$1"' _ "$T/tp/user.js"
session_theme dark -
check "dark: the dark ones" bash -c 'grep -q "firefox-compact-dark@mozilla.org" "$1" && grep -q "content-override\", 0" "$1" && grep -q "dark-fox-anniversary" "$1"' _ "$T/tp/user.js"
printf '\xff\xd8\xff\xe0 a photo' >"$T/rt/firefox-newtab.jpg"
session_theme dark firefox-newtab.jpg
check "a picture: in the New Tab page's stylesheet, as data (Firefox loads no outside file there)" bash -c '
    grep -q "^@-moz-document url(\"about:newtab\"), url(\"about:home\")" "$1" && grep -q "data:image/jpeg;base64,$(base64 -w0 "$2")" "$1" &&
    grep -q "legacyUserProfileCustomizations.stylesheets\", true" "$3"' _ "$T/tp/chrome/userContent.css" "$T/rt/firefox-newtab.jpg" "$T/tp/user.js"
printf 'not a picture' >"$T/rt/firefox-newtab.jpg"
session_theme dark firefox-newtab.jpg
check "...one that isn't really a picture: none, and the old stylesheet goes" test ! -e "$T/tp/chrome/userContent.css"
ln -sf /etc/passwd "$T/rt/firefox-newtab.png"
session_theme dark firefox-newtab.png
check "...a link instead of a file isn't followed" test ! -e "$T/tp/chrome/userContent.css"
printf '/* mine */\n' >"$T/tp/chrome/userContent.css"
session_theme dark -
check "...a userContent.css of your own is left alone" grep -qx '/\* mine \*/' "$T/tp/chrome/userContent.css"
check "a profile's settings come from the file only root can write" grep -q '/etc/wren/firefox-profiles/\$tag.conf' "$HERE/bin/firefox-session"
check "the address in it is checked before it is used" grep -q "isn't a plain web address" "$HERE/bin/firefox-session"
check "the session's own checks come before it looks for the Landlock wrapper" python3 -I -c '
import sys
s = open(sys.argv[1]).read()
assert s.index("unexpected downloads folder") < s.index("\nneed_noabs\n")
' "$HERE/bin/firefox-session"
check "it starts Firefox inside the abstract-socket wrapper" grep -q '"\$noabs" bash -c' "$HERE/bin/firefox-session"
check "links go to the running Firefox through a private bus, also under the wrapper" grep -q '"\$noabs" /usr/lib/firefox-esr/firefox-esr --profile' "$HERE/bin/firefox-session"
# firefox-esr by name opens the sandbox, so the sandboxes start Firefox itself
# by its path: by name they would start the sandbox again from inside it
check "the sandboxes start Firefox by its path, never firefox-esr by name (that is the sandbox now)" \
    bash -c '! grep -nE "(^|[[:space:]\"])firefox-esr( |\$)" "$1" "$2" && grep -q "/usr/lib/firefox-esr/firefox-esr --profile" "$1" && grep -q "cage -d -- /usr/lib/firefox-esr/firefox-esr" "$2"' _ "$HERE/bin/firefox-session" "$HERE/bin/incognito-session"
X=$HERE/extras/firefox-sandbox.sh
check "firefox-esr moves to firefox-unsafe with dpkg-divert (so Debian's updates land there), and a script in its place opens the sandbox" \
    bash -c 'grep -q "dpkg-divert --quiet --local --rename --divert \"\$UNSAFE\" --add \"\$ESR\"" "$1" && grep -qF "'"'"'exec /usr/local/bin/firefox \"\$@\"'"'"'" "$1" && grep -q "^UNSAFE=/usr/bin/firefox-unsafe$" "$1"' _ "$X"
check "...Debian's menu entry, which names the program itself, is hidden for you" grep -q "'Hidden=true'" "$X"
check "...and --remove undoes it, before Firefox's packages may go" python3 -I -c '
import sys
s = open(sys.argv[1]).read()
r = s[s.index("= --remove ]"):]
assert r.index("dpkg-divert --quiet --local --rename --remove") < r.index("apt_purge")
' "$X"
check "no 'open' without a running Firefox" grep -q 'Firefox is not running' "$HERE/bin/firefox-session"

# 5. the firewall mirrors incognito's, for the other user
check "the firewall rule covers the whole sandbox group (firefox and every profile user)" grep -q 'meta skgid "wren-fx" jump firefox' "$HERE/data/firefox-firewall.nft"
check "it rejects anything addressed to this computer (lo), like incognito's" grep -q 'oifname "lo" reject' "$HERE/data/firefox-firewall.nft"
check "...and the same private ranges as incognito's" test "$(grep -E '^[[:space:]]+(ip|ip6) daddr|^ +[0-9]' "$HERE/data/firefox-firewall.nft" | tr -s ' ' | md5sum)" = "$(grep -E '^[[:space:]]+(ip|ip6) daddr|^ +[0-9]' "$HERE/data/incognito-firewall.nft" | tr -s ' ' | md5sum)"
check "DNS only to this computer's resolver (the set parts/sandbox-dns.sh fills)" grep -q 'ip daddr @resolvers udp dport 53 accept' "$HERE/data/firefox-firewall.nft"
check "it says how to allow the local network for a while" grep -q 'systemctl stop wren-firefox-firewall' "$HERE/data/firefox-firewall.nft"

# IPv6: a LAN's global addresses can't be told from the internet's by a fixed rule,
# so the sandbox users get no IPv6 at all (the sign-in window may reach the LAN anyway)
for f in firefox incognito claude claude-vm opencode-vm yt-dlp onion-site; do
    check "$f's firewall: no IPv6 (only DNS, and answers, before it)" bash -c '
        grep -qx "        meta nfproto ipv6 reject" "$1" && ! grep -q "ip6 daddr" "$1" &&
        [ "$(grep -n "dport 53 accept" "$1" | head -1 | cut -d: -f1)" -lt "$(grep -n "meta nfproto ipv6 reject" "$1" | cut -d: -f1)" ]' _ "$HERE/data/$f-firewall.nft"
done

# 6. the extra
e=$HERE/extras/firefox-sandbox.sh
s=$(sed -n 's/^# summary: //p' "$e")
check "the extra has a short summary and a status line" test -n "$s" -a "${#s}" -le 52 -a -n "$(grep '^# status: ' "$e")"
check "it makes the user through the shared helper, in the sandbox group" grep -q 'fx_create_user "\$NAME"' "$e"
l=$HERE/lib/firefox-sandbox.sh
check "the helper makes a locked system user with its own home, no login" grep -q 'useradd --system --gid "\$FX_GROUP" --create-home' "$l"
check "...whose home only it can enter" grep -q 'chmod 0700 "\$home"' "$l"
check "the sudoers rule is checked with visudo before it is installed" python3 -I -c '
import sys
s = open(sys.argv[1]).read()
assert s.index("visudo -cf") < s.index("install -o root -g root -m 0440")
' "$l"
check "the rule allows the one session script only" grep -q 'NOPASSWD: %s' "$l"
check "the Firefox it installs becomes the default browser for links" grep -q 'set_default_app wren-firefox.desktop x-scheme-handler/http x-scheme-handler/https' "$e"
check "...and that is undone on --remove" grep -q 'unset_default_app wren-firefox.desktop' "$e"
check "the desktop entry runs the sandboxed command with the link" grep -q '^Exec=/usr/local/bin/firefox %u$' "$HERE/data/wren-firefox.desktop"
check "...and handles web links only" grep -q '^MimeType=x-scheme-handler/http;x-scheme-handler/https;$' "$HERE/data/wren-firefox.desktop"
check "it can be removed" grep -q -e '--remove' "$e"
check "the Firefox profile is offered for deletion, never deleted silently" grep -q 'Delete that profile too?' "$e"

# 9. Downloads readable for you. You are named in ~/Downloads' default ACL, but a
# file Firefox saves as private (600) gets an empty ACL mask, so that entry gave
# you nothing ("Permission denied"). The session opens the mask on what its user
# saved, and shuts the group and others entries.
S=$HERE/bin/firefox-session
mkdir -p "$T/share/Downloads/sub" "$T/share/bin"
printf '#!/bin/sh\nfor a; do case $a in -*) ;; *) echo "${a##*/}" >>"%s/share/fixed" ;; esac; done\n' "$T" >"$T/share/bin/setfacl"
chmod +x "$T/share/bin/setfacl"
for f in private:600 normal:644 open-to-group:660 group-read:640 exec-group:670 world:606; do
    : >"$T/share/Downloads/${f%%:*}" && chmod "${f##*:}" "$T/share/Downloads/${f%%:*}"
done
: >"$T/share/Downloads/sub/deeper" && chmod 600 "$T/share/Downloads/sub/deeper"
ln -s "$T/share/Downloads/private" "$T/share/Downloads/link"
: >"$T/share/fixed"
( eval "$(sed -n '/^share_downloads() {/,/^}/p' "$S")"
  PATH="$T/share/bin:$PATH" user=$(id -un) downloads=$T/share/Downloads share_downloads )
fixed=$(sort "$T/share/fixed" | paste -sd' ')
check "a download saved private (600) is opened up for you" grep -qw private <<<"$fixed"
check "...so is one others could read (644, 606), and one with an odd mask (670)" \
    bash -c 'for f in normal world exec-group; do grep -qw "$f" <<<"$1" || exit 1; done' _ "$fixed"
check "...but not one already readable to you and no one else (660, 640)" \
    bash -c '! grep -qw open-to-group <<<"$1" && ! grep -qw group-read <<<"$1"' _ "$fixed"
check "...nor files in subfolders (other profiles' folders), nor links" \
    bash -c '! grep -qw deeper <<<"$1" && ! grep -qw link <<<"$1"' _ "$fixed"
check "the mask is set to rw, group and others to nothing" grep -qF -- '-exec setfacl -m g::-,o::-,m::rw {} +' "$S"
check "the session shares at its start, every 2 seconds while Firefox runs, and at its end" \
    bash -c 'grep -qx "share_downloads" "$1" && grep -qF "while kill -0 \"\$pid\" 2>/dev/null; do sleep 2; share_downloads; done &" "$1" && sed -n "/^cleanup() {/,/^}/p" "$1" | grep -q share_downloads' _ "$S"

# 10. One Firefox extra: this one also installs Firefox ESR run as you
# (firefox-esr), its hardening and incognito (extras/firefox.sh is gone)
X=$HERE/extras/firefox-sandbox.sh
order() { python3 -I -c 'import sys; s = open(sys.argv[1]).read(); assert s.index(sys.argv[2]) < s.index(sys.argv[3])' "$X" "$1" "$2"; }
check "the plain Firefox extra is gone; this is the only one" bash -c '[ ! -e "$1/extras/firefox.sh" ]' _ "$HERE"
check "it sets up Firefox's hardening for every profile" grep -qx 'bash "$WREN_DIR/parts/firefox-hardening.sh"' "$X"
check "it sets up incognito too, without asking" \
    bash -c 'grep -qx "bash \"\$WREN_DIR/parts/incognito.sh\" ||" "$1" && ! grep -q "Set it up too" "$1"' _ "$X"
check "it takes over the old Firefox extra's marker after installing its own (Firefox stays)" \
    order 'apt_install firefox-esr' 'WREN_OWNER=firefox apt_purge'
remove=$(sed -n '/^if \[ "${1:-}" = --remove \]/,/^fi$/p' "$X")
rorder() { python3 -I -c 'import sys; s = sys.argv[1]; assert s.index(sys.argv[2]) < s.index(sys.argv[3])' "$remove" "$1" "$2"; }
check "--remove asks about incognito first (its firewall and wayland-restrict decisions depend on it)" \
    rorder 'ask "Remove incognito (the throwaway Firefox) too?" y' 'remove_wayland_restrict'
check "--remove takes out the hardening, unless incognito stays" \
    grep -qF 'bash "$WREN_DIR/parts/firefox-hardening.sh" --remove' <<<"$remove"
check "--remove takes out the packages it installed" grep -qx '    apt_purge' <<<"$remove"
check "the status screen names this extra for Firefox" grep -qF 'echo "Firefox (extras/firefox-sandbox.sh):"' "$HERE/status.sh"
for f in firefox-user.js incognito-user.js; do
    check "$f: WebRTC off (no direct connections a page opens)" grep -qx 'user_pref("media.peerconnection.enabled", false);' "$HERE/data/$f"
done
# the owner's New Tab page, for every sandboxed Firefox: the fox, which Firefox
# 140+ shows only with user.enabled, and no shortcuts, weather or search box
check "the New Tab page: the fox shown, no shortcuts, weather or search box (no logo)" bash -c '
    for p in "newtabWallpapers.user.enabled\", true" "newtabWallpapers.enabled\", true" "newtabWallpapers.wallpaper\", \"dark-fox-anniversary\"" \
             "feeds.topsites\", false" "showWeather\", false" "showSearch\", false"; do
        grep -qF "pref(\"browser.newtabpage.activity-stream.$p" "$1" || exit 1
    done' _ "$HERE/data/firefox-hardening.js"

# ---- profiles from the firefox command: list, make, remove; Tab completion ----
P=$T/profiles-list
mkdir -p "$P" "$T/home/.local/bin" "$T/wrendir/extras/firefox-profiles"
printf 'url=https://bank.example/\nfast_js=no\ntoolbars=hidden\nsound=no\ncookies=keep\n' >"$P/bank.conf"
printf 'url=https://mail.example/\ncookies=delete\n' >"$P/mail.conf"
printf '#!/bin/sh\n# Written by Wren Linux extras/firefox-profiles/new-profile.sh\n' >"$T/home/.local/bin/bank"
lst=$(WREN_FX_PROFILE_DIR=$P fx --profiles 2>&1)
check "firefox --profiles: each profile, its command, its address and its choices" bash -c '
    grep -qE "^bank +bank +https://bank.example/, no sound$" <<<"$1" && grep -qE "^mail +\(no command\) +https://mail.example/, cookies deleted on close$" <<<"$1"' _ "$lst"
mkdir -p "$T/profiles-none"
check "...none yet: it says how to make one" grep -q 'firefox --new-profile' <<<"$(WREN_FX_PROFILE_DIR=$T/profiles-none fx --profiles 2>&1)"
printf '#!/bin/sh\n[ "$1" = --dir ] && echo "%s"\n' "$T/wrendir" >"$T/fake/wrenctl"
printf '#!/bin/sh\nprintf "%%s\\n" "$@" >"%s/np-args"\n' "$T" >"$T/wrendir/extras/firefox-profiles/new-profile.sh"
chmod +x "$T/fake/wrenctl"
fx --new-profile github https://github.com --delete-cookies >/dev/null 2>&1
check "firefox --new-profile NAME URL: new-profile.sh, from where Wren Linux is, with them" test "$(paste -sd' ' "$T/np-args")" = "github https://github.com --delete-cookies"
fx --new-profile >/dev/null 2>&1
check "...without them: new-profile.sh asks" test -z "$(cat "$T/np-args")"
fx --remove-profile bank >/dev/null 2>&1
check "firefox --remove-profile NAME: new-profile.sh --remove NAME" test "$(paste -sd' ' "$T/np-args")" = "--remove bank"
check "...without a name: refused" not fx --remove-profile
export P HERE
comp() { WREN_FX_PROFILE_DIR=$P bash -c '. "$1"; shift; COMP_WORDS=("$@"); COMP_CWORD=$((${#COMP_WORDS[@]} - 1)); _wren_firefox; printf "%s\n" "${COMPREPLY[@]}"' _ "$HERE/data/firefox-completion.bash" "$@"; }
export -f comp
check "Tab: the profiles after --profile and --remove-profile" bash -c '[ "$(comp firefox --profile "" | sort | paste -sd" ")" = "bank mail" ] && [ "$(comp firefox --remove-profile b)" = bank ]' _
check "...and the options first" test "$(comp firefox --pro | sort | paste -sd' ')" = "--profile --profiles"
check "the extra installs it where bash-completion looks" grep -q 'bash-completion/completions/firefox' "$HERE/extras/firefox-sandbox.sh"

# ---- a file in the downloads folder may be opened (file://), nothing else of yours ----
mkdir -p "$T/home/Downloads/bank"
echo '<p>hi</p>' >"$T/home/Downloads/page.html"
echo '<p>mine</p>' >"$T/home/notes.html"
ln -sf "$T/home/notes.html" "$T/home/Downloads/out.html"
echo '<p>bank</p>' >"$T/home/Downloads/bank/statement.html"
: >"$T/calls"
fx --no-audio "file://$T/home/Downloads/page.html" >/dev/null 2>&1
check "a file in ~/Downloads: opened (file://), it can read that folder anyway" grep -qF "file://$T/home/Downloads/page.html" "$T/calls"
for bad in "file://$T/home/notes.html" "file://$T/home/Downloads/out.html" "file://$T/home/Downloads/../notes.html" "file://$T/home/Downloads/%2e%2e/notes.html" "file:///etc/passwd"; do
    : >"$T/calls"
    check "...but not ${bad#file://"$T"/} (outside it, a link out of it, .. or an escape)" bash -c '! "$@" 2>/dev/null && ! grep -q "firefox-session" "$T/calls"' _ fx --no-audio "$bad"
done
: >"$T/calls"
check "a profile: a file in the main ~/Downloads isn't its to open" not fx --no-audio --profile bank "file://$T/home/Downloads/page.html"
: >"$T/calls"
fx --no-audio --profile bank "file://$T/home/Downloads/bank/statement.html" >/dev/null 2>&1
check "...its own folder's is" grep -qF "file://$T/home/Downloads/bank/statement.html" "$T/calls"
check "...and the main Firefox's rights, inherited from ~/Downloads, are taken off its folder" \
    grep -qF "setfacl -P -R -x u:firefox,d:u:firefox $T/home/Downloads/bank" "$T/calls"
check "the session takes a file only in a downloads folder, and no .., itself too" bash -c '
    eval "$(sed -n "/^check_urls() {/,/^}/p" "$1")"; die() { exit 1; }; tag=
    ! (check_urls "file:///etc/passwd") && ! (check_urls "file:///home/me/Downloads/../.ssh/id") && ! (check_urls "file:///home/me/.bashrc") &&
    tag=bank && ! (check_urls "file:///home/me/Downloads/x.html")' _ "$HERE/bin/firefox-session"

[ "$fails" -eq 0 ]
