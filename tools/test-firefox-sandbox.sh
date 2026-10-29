#!/bin/bash
# Checks the sandboxed Firefox (bin/firefox, bin/firefox-session, the extra and
# its firewall) with pretend sudo, setfacl and wayland-restrict, a pretend
# Wayland socket and a pretend "id". Nothing is started and nothing outside a
# temp folder is changed. Run by test.sh, or:  bash tools/test-firefox-sandbox.sh
# shellcheck disable=SC2016,SC2088,SC2010,SC2317,SC1007  # patterns name shell variables literally; die() runs in the eval
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

T=$(mktemp -d)
trap 'rm -rf "$T"; kill $(jobs -p) 2>/dev/null' EXIT
fails=0
check() { # DESCRIPTION CONDITION-COMMAND...
    local what=$1
    shift
    if "$@" >/dev/null 2>&1; then printf '  ok    %s\n' "$what"; else printf '  FAIL  %s\n' "$what"; fails=$((fails + 1)); fi
}
not() { ! "$@"; }
command -v flock >/dev/null || { echo "  ok    skipped: flock isn't installed"; exit 0; }

mkdir -p "$T/fake" "$T/run" "$T/home"
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
fx() { env PATH="$T/fake:$PATH" HOME="$T/home" XDG_RUNTIME_DIR="$T/run" WAYLAND_DISPLAY=wayland-1 bash "$HERE/bin/firefox" "$@"; }

# 1. the first start
: >"$T/calls"
fx --no-audio https://example.org/
check "the first start runs the session as the firefox user" grep -q 'sudo -n -u firefox /usr/local/libexec/firefox-session start' "$T/calls"
check "...with the runtime folder, the restricted socket, no sound, your Downloads and the address" \
    grep -qF "firefox-session start $T/run firefox-wayland - $T/home/Downloads https://example.org/" "$T/calls"
check "it gave the firefox user the socket and a way through to ~/Downloads, not the whole home" \
    grep -q "setfacl -m u:firefox:--x $T/run $T/home" "$T/calls"
check "...read and write on ~/Downloads, for both of you, for later files too" \
    grep -q "setfacl -d -m u:firefox:rwx,u:$(id -un):rwx $T/home/Downloads" "$T/calls"
check "...and took the access back when it ended" grep -q "setfacl -x u:firefox $T/run $T/home" "$T/calls"
check "~/Downloads exists" test -d "$T/home/Downloads"

# 2. a link while it is open goes to the running Firefox
: >"$T/calls"
FAKE_UP=3 fx --no-audio >/dev/null 2>&1 &
sleep 1
fx https://example.org/next
check "a second start while it is open opens the address in that Firefox" grep -qF 'firefox-session open https://example.org/next' "$T/calls"
check "...and does not start another" test "$(grep -c 'firefox-session start' "$T/calls")" -eq 1
wait %2 2>/dev/null

# 2b. a profile with its own user runs next to it, with its own names and downloads folder
: >"$T/calls"
FAKE_UP=2 fx --no-audio https://example.org/ >/dev/null 2>&1 &
sleep 0.6
fx --no-audio --profile bank
check "a profile starts as its own user, next to the other Firefox" grep -qF "sudo -n -u fx-bank /usr/local/libexec/firefox-session start $T/run firefox-bank-wayland - $T/home/Downloads/bank" "$T/calls"
check "...with its own downloads folder, so profiles cannot read each other's files" test -d "$T/home/Downloads/bank"
check "...and rights only for its own user on it" grep -q "setfacl -m u:fx-bank:rwx $T/home/Downloads/bank" "$T/calls"
check "...and not the other user's" not grep -q "u:firefox:rwx $T/home/Downloads/bank" "$T/calls"
# closing the profile takes back only its own user's rights: the Firefox still
# open next to it keeps its way through your home folder to ~/Downloads
check "closing the profile takes back only its own user's access" grep -q "setfacl -x u:fx-bank $T/run $T/home $T/home/Downloads" "$T/calls"
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
# validation lines are run against good and bad values.
bad_arg() { # LINE-PATTERN VALUE VAR: does the script's check for VAR refuse VALUE?
    local line
    line=$(grep -F -m1 "$1" "$HERE/bin/firefox-session")
    [ -n "$line" ] || return 1
    ( die() { exit 1; }; export "$3=$2"; eval "${line//\[ -S*/true}" ) 2>/dev/null && return 1 || return 0
}
ok_arg() { ! bad_arg "$@"; }
host_rt= host_wl= audio= downloads=
check "a runtime folder that is not /run/user/N is refused" bad_arg '=~ ^/run/user/' /tmp/x host_rt
check "...and /run/user/1000 is accepted" ok_arg '=~ ^/run/user/' /run/user/1000 host_rt
check "a Wayland name with a slash is refused" bad_arg 'unexpected Wayland display name' ../x host_wl
check "...and wayland-1 is accepted" ok_arg 'unexpected Wayland display name' wayland-1 host_wl
check "a sound pipe name it did not expect is refused" bad_arg 'unexpected sound pipe name' /etc/passwd audio
check "...and firefox-audio.fifo or - are accepted" ok_arg 'unexpected sound pipe name' firefox-audio.fifo audio
check "a downloads folder other than /home/NAME/Downloads is refused" bad_arg 'unexpected downloads folder' /etc downloads
check "...also one that climbs out with .." bad_arg 'unexpected downloads folder' '/home/a/../../etc/Downloads' downloads
check "...and /home/me/Downloads is accepted" ok_arg 'unexpected downloads folder' /home/me/Downloads downloads
# a profile's user may use only its own folder
tag=bank
check "a profile accepts /home/me/Downloads/bank" ok_arg '/Downloads/$tag$' /home/me/Downloads/bank downloads
check "...not the shared Downloads folder" bad_arg '/Downloads/$tag$' /home/me/Downloads downloads
check "...and not another profile's" bad_arg '/Downloads/$tag$' /home/me/Downloads/shop downloads
tag=''
check "the session accepts the users firefox and fx-NAME only" python3 -I -c '
s = open(__import__("sys").argv[1]).read()
assert "    firefox) tag= ;;" in s and "    fx-*)" in s and "this runs as the user firefox (or fx-NAME)" in s
' "$HERE/bin/firefox-session"
check "a profile's settings come from the file only root can write" grep -q '/etc/debsway/firefox-profiles/\$tag.conf' "$HERE/bin/firefox-session"
check "the address in it is checked before it is used" grep -q "isn't a plain web address" "$HERE/bin/firefox-session"
check "the session's own checks come before it looks for the Landlock wrapper" python3 -I -c '
import sys
s = open(sys.argv[1]).read()
assert s.index("unexpected downloads folder") < s.index("\nneed_noabs\n")
' "$HERE/bin/firefox-session"
check "it starts Firefox inside the abstract-socket wrapper" grep -q '"\$noabs" bash -c' "$HERE/bin/firefox-session"
check "links go to the running Firefox through a private bus, also under the wrapper" grep -q '"\$noabs" firefox-esr --profile' "$HERE/bin/firefox-session"
check "no 'open' without a running Firefox" grep -q 'Firefox is not running' "$HERE/bin/firefox-session"

# 5. the firewall mirrors incognito's, for the other user
check "the firewall rule covers the whole sandbox group (firefox and every profile user)" grep -q 'meta skgid "debsway-fx" jump firefox' "$HERE/data/firefox-firewall.nft"
check "it rejects anything addressed to this computer (lo), like incognito's" grep -q 'oifname "lo" reject' "$HERE/data/firefox-firewall.nft"
check "...and the same private ranges as incognito's" test "$(grep -E '^[[:space:]]+(ip|ip6) daddr|^ +[0-9]' "$HERE/data/firefox-firewall.nft" | tr -s ' ' | md5sum)" = "$(grep -E '^[[:space:]]+(ip|ip6) daddr|^ +[0-9]' "$HERE/data/incognito-firewall.nft" | tr -s ' ' | md5sum)"
check "DNS stays open" grep -q 'udp dport 53 accept' "$HERE/data/firefox-firewall.nft"
check "it says how to allow the local network for a while" grep -q 'systemctl stop debsway-firefox-firewall' "$HERE/data/firefox-firewall.nft"

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
check "the Firefox it installs becomes the default browser for links" grep -q 'set_default_app debsway-firefox.desktop x-scheme-handler/http x-scheme-handler/https' "$e"
check "...and that is undone on --remove" grep -q 'unset_default_app debsway-firefox.desktop' "$e"
check "the desktop entry runs the sandboxed command with the link" grep -q '^Exec=/usr/local/bin/firefox %u$' "$HERE/data/debsway-firefox.desktop"
check "...and handles web links only" grep -q '^MimeType=x-scheme-handler/http;x-scheme-handler/https;$' "$HERE/data/debsway-firefox.desktop"
check "it can be removed" grep -q -e '--remove' "$e"
check "the Firefox profile is offered for deletion, never deleted silently" grep -q 'Delete that profile too?' "$e"

[ "$fails" -eq 0 ]
