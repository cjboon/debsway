#!/bin/bash
# Checks extras/torrent.sh's pieces without Transmission, sudo or a network:
# the settings it writes (data/torrent-settings.py, on Debian 13's own default
# settings.json), the torrent command (bin/torrent) with a pretend
# transmission-remote, and what the extra installs, including that its
# firewall rule leaves the Mullvad VPN app's working. Changes nothing outside
# a temp folder. Run by test.sh, or:  bash tools/test-torrent.sh
# shellcheck disable=SC2016  # the inner shells expand their own variables
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
fails=0
check() { # DESCRIPTION CONDITION-COMMAND...
    local what=$1
    shift
    if "$@" >/dev/null 2>&1; then printf '  ok    %s\n' "$what"; else printf '  FAIL  %s\n' "$what"; fails=$((fails + 1)); fi
}
not() { ! "$@"; }

# ---- the settings (data/torrent-settings.py) ----
# Debian 13's /etc/transmission-daemon/settings.json (transmission-daemon 4.1.0~beta2+dfsg-3+deb13u2)
cat >"$T/settings.json" <<'EOF'
{
    "blocklist-enabled": 0,
    "download-dir": "\/var\/lib\/transmission-daemon\/downloads",
    "download-limit": 100,
    "download-limit-enabled": 0,
    "encryption": 1,
    "max-peers-global": 200,
    "peer-port": 51413,
    "pex-enabled": 1,
    "port-forwarding-enabled": 0,
    "rpc-authentication-required": 1,
    "rpc-password": "transmission",
    "rpc-port": 9091,
    "rpc-username": "transmission",
    "rpc-whitelist": "127.0.0.1",
    "upload-limit": 100,
    "upload-limit-enabled": 0
}
EOF
chmod 660 "$T/settings.json"
PW=0123456789abcdef0123456789abcdef
echo "$PW" | python3 -I "$HERE/data/torrent-settings.py" "$T/settings.json" /dl /partial
get() { python3 -I -c 'import json, sys; print(json.dumps(json.load(open(sys.argv[1]))[sys.argv[2]]))' "$T/settings.json" "$1"; }
check "settings: the remote control listens on this computer only" bash -c '[ "$1" = "\"127.0.0.1\"" ]' _ "$(get rpc-bind-address)"
check "...from this computer only, checking the host name too (no DNS rebinding)" \
    bash -c '[ "$1" = "\"127.0.0.1,::1\"" ] && [ "$2" = true ] && [ "$3" = true ]' _ "$(get rpc-whitelist)" "$(get rpc-whitelist-enabled)" "$(get rpc-host-whitelist-enabled)"
check "...with a password of its own, not Debian's \"transmission\"" \
    bash -c '[ "$1" = "\"$3\"" ] && [ "$2" = "\"debsway\"" ] && [ "$4" = true ]' _ "$(get rpc-password)" "$(get rpc-username)" "$PW" "$(get rpc-authentication-required)"
check "no ports opened on your router (UPnP, NAT-PMP), no looking for peers on your network" \
    bash -c '[ "$1" = false ] && [ "$2" = false ]' _ "$(get port-forwarding-enabled)" "$(get lpd-enabled)"
check "downloads: finished in one folder, unfinished in another" \
    bash -c '[ "$1" = "\"/dl\"" ] && [ "$2" = "\"/partial\"" ] && [ "$3" = true ]' _ "$(get download-dir)" "$(get incomplete-dir)" "$(get incomplete-dir-enabled)"
check "...its files rw for it, readable by your group, nothing for others (umask 027)" test "$(get umask)" = 23
check "Debian's other settings are kept" test "$(get download-limit)" = 100
check "...and the file keeps its mode" test "$(stat -c %a "$T/settings.json")" = 660
check "without a password on standard input nothing is changed" \
    bash -c 'cp "$1" "$1.before"; ! python3 -I "$2" "$1" /dl /p </dev/null && cmp -s "$1" "$1.before"' _ "$T/settings.json" "$HERE/data/torrent-settings.py"

# ---- the torrent command, with a pretend transmission-remote ----
mkdir -p "$T/fake" "$T/config/debsway" "$T/home" "$T/dl/My Film/sub"
echo "debsway:$PW" >"$T/config/debsway/torrent-rpc"
echo film >"$T/dl/My Film/a.mkv"
echo subs >"$T/dl/My Film/sub/b.srt"
echo "my secret" >"$T/home/secret"
ln -s "$T/home/secret" "$T/dl/My Film/link.mkv"
cat >"$T/fake/transmission-remote" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >>"$T/calls"
printf '%s\n' "\${TR_AUTH:-}" >"$T/auth"
[ -e "$T/down" ] && { echo "Couldn't connect to server"; exit 1; }
args=" \$* "
info() { printf '  Name: %s\n  Location: %s\n  Percent Done: %s\n' "\$1" "\$2" "\$3"; }
case \$args in
    *" -l "*) printf '%s\n' '    ID   Done       Have  ETA           Up    Down  Ratio  Status       Name' \
        '     1   100%   10.5 MB  Done         0.0     0.0    0.0  Idle         My Film' \
        '     2    45%    1.0 MB  1 min        0.0    10.0    0.0  Downloading  half' \
        'Sum:           11.5 MB               0.0    10.0' ;;
    *" -t 1 -i "*) info "My Film" "$T/dl" 100% ;;
    *" -t 2 -i "*) info half "$T/dl" 45% ;;
    *" -t 3 -i "*) info ../evil "$T/dl" 100% ;;
    *" -t 4 -i "*) info elsewhere /tmp/other 100% ;;
    *" -t 5 -i "*) info -x "$T/dl" 100% ;;
    *) echo "localhost:9091/transmission/rpc/ responded: success" ;;
esac
EOF
chmod +x "$T/fake/transmission-remote"
printf '#!/bin/sh\nexit 1\n' >"$T/fake/xdg-user-dir"
chmod +x "$T/fake/xdg-user-dir"
tor() { env PATH="$T/fake:/usr/bin:/bin" HOME="$T/home" XDG_CONFIG_HOME="$T/config" \
    DEBSWAY_TR_REMOTE="$T/fake/transmission-remote" DEBSWAY_TORRENT_DIR="$T/dl" bash "$HERE/bin/torrent" "$@"; }
last() { tail -1 "$T/calls"; }

: >"$T/calls"
tor >/dev/null
check "torrent alone lists what is downloading, from this computer's client" test "$(last)" = "localhost:9091 -ne -l"
check "...the password from the environment (TR_AUTH), as in its file" test "$(cat "$T/auth")" = "debsway:$PW"
check "...and never on a command line" not grep -q "$PW" "$T/calls"
tor add 'magnet:?xt=urn:btih:abc&dn=x' >/dev/null
check "add: a magnet link is passed on as it is" test "$(last)" = 'localhost:9091 -ne -a magnet:?xt=urn:btih:abc&dn=x'
echo d8:announce >"$T/home/x.torrent"
tor add "$T/home/x.torrent" >/dev/null
check "...a .torrent file is read by transmission-remote, as you (the client can't see your home)" test "$(last)" = "localhost:9091 -ne -a $T/home/x.torrent"
check "...a file that isn't there is refused" not tor add "$T/home/nothing.torrent"
: >"$T/calls"
tor "$T/home/x.torrent" >/dev/null
check "torrent FILE.torrent, without add, adds it" test "$(last)" = "localhost:9091 -ne -a $T/home/x.torrent"
tor 'magnet:?xt=urn:btih:def' >/dev/null
check "...and so does torrent MAGNET" test "$(last)" = 'localhost:9091 -ne -a magnet:?xt=urn:btih:def'
cp "$T/home/x.torrent" "$T/home/locked.torrent" && chmod 000 "$T/home/locked.torrent"
: >"$T/calls"
said=$(tor add "$T/home/locked.torrent" 2>&1)
check "a .torrent you can't read (the sandboxed Firefox's, say): it says whose it is and how to take it over" \
    bash -c 'grep -q "you can.t read .* (it belongs to $(id -un))" <<<"$1" && grep -q "sudo chown" <<<"$1" && [ ! -s "$2" ]' _ "$said" "$T/calls"
chmod 600 "$T/home/locked.torrent"
help=$(tor help)
check "the help is the comment at the top, and nothing of the code after it" \
    bash -c 'grep -q "torrent get N|all" <<<"$1" && ! grep -qE "set -u|DEBSWAY_" <<<"$1"' _ "$help"

said=$(tor get 1 2>&1)
check "get: a finished download is copied into ~/Downloads, folders and all" \
    bash -c '[ "$(cat "$1/My Film/a.mkv")" = film ] && [ "$(cat "$1/My Film/sub/b.srt")" = subs ]' _ "$T/home/Downloads"
check "...as files of yours" bash -c '[ -f "$1" ] && [ ! -L "$1" ] && [ "$(stat -c %U "$1")" = "$(id -un)" ]' _ "$T/home/Downloads/My Film/a.mkv"
check "...but not a link (to one of your files, say)" bash -c '[ ! -e "$1" ] && [ ! -L "$1" ]' _ "$T/home/Downloads/My Film/link.mkv"
check "...and it says how many and where" grep -q "My Film: 2 file(s) in $T/home/Downloads" <<<"$said"
check "...the client's own copy stays (to keep sharing it)" test -f "$T/dl/My Film/a.mkv"
tor get 1 >/dev/null 2>&1
check "...again: nothing of yours is overwritten (\"a (2).mkv\")" \
    bash -c '[ "$(cat "$1/a.mkv")" = film ] && [ -f "$1/a (2).mkv" ]' _ "$T/home/Downloads/My Film"
check "an unfinished one isn't copied" bash -c '! "$@" get 2 && [ ! -e "$HOME/Downloads/half" ]' _ env HOME="$T/home" PATH="$T/fake:/usr/bin:/bin" \
    XDG_CONFIG_HOME="$T/config" DEBSWAY_TR_REMOTE="$T/fake/transmission-remote" DEBSWAY_TORRENT_DIR="$T/dl" bash "$HERE/bin/torrent"
# something real for ../evil to reach: a folder beside the client's
mkdir -p "$T/evil" && echo private >"$T/evil/notes.txt"
check "a name that leads elsewhere (../evil) is refused" not tor get 3
check "...and nothing from beside the client's folder is copied" \
    bash -c '[ -z "$(find "$1" -name notes.txt)" ]' _ "$T/home"
check "a download outside the client's folder is refused" not tor get 4
check "a name that looks like an option (-x) is refused" not tor get 5
: >"$T/calls"
tor get all >/dev/null 2>&1
check "get all copies only the finished ones" bash -c 'grep -q -- "-t 1 -i" "$1" && ! grep -q -- "-t 2 -i" "$1"' _ "$T/calls"
check "get with something that isn't a number is refused" not tor get first
tor pause all >/dev/null
check "pause all" test "$(last)" = "localhost:9091 -ne -t all -S"
tor resume 2 >/dev/null
check "resume 2" test "$(last)" = "localhost:9091 -ne -t 2 -s"
tor remove 2 >/dev/null
check "remove 2 removes it and its files in the client's folder" test "$(last)" = "localhost:9091 -ne -t 2 --remove-and-delete"
: >"$T/calls"
check "remove with something that isn't a number is refused, and nothing is sent" bash -c '! "$@" remove abc && [ ! -s "'"$T"'/calls" ]' _ \
    env HOME="$T/home" PATH="$T/fake:/usr/bin:/bin" XDG_CONFIG_HOME="$T/config" DEBSWAY_TR_REMOTE="$T/fake/transmission-remote" \
    DEBSWAY_TORRENT_DIR="$T/dl" bash "$HERE/bin/torrent"
touch "$T/down"
check "when the client isn't running it says how to start it" grep -q 'sudo systemctl start transmission-daemon' <<<"$(tor 2>&1)"
rm "$T/down"
mv "$T/config/debsway/torrent-rpc" "$T/rpc"
check "without its password file it says how to set it up" grep -q 'bash ~/debsway/extras/torrent.sh' <<<"$(tor 2>&1)"
mv "$T/rpc" "$T/config/debsway/torrent-rpc"

# ---- what the extra installs ----
X=$HERE/extras/torrent.sh
order() { # TEXT-BEFORE TEXT-AFTER: in the extra, the first comes before the second
    python3 -I -c 'import sys; s = open(sys.argv[1]).read(); a, b = s.index(sys.argv[2]), s.index(sys.argv[3]); assert a < b' "$X" "$1" "$2"
}
check "Transmission is stopped before its settings are changed (it writes them back when it stops)" \
    order 'sudo systemctl stop transmission-daemon.service' 'sudo python3 -I "$DEBSWAY_DIR/data/torrent-settings.py"'
check "...and started only after the firewall rule is loaded" \
    order 'sudo systemctl restart debsway-torrent-firewall.service' 'sudo systemctl start transmission-daemon.service'
check "the password goes to the settings on standard input, not a command line" \
    grep -qF 'cut -d: -f2- "$AUTH_FILE" | sudo python3 -I "$DEBSWAY_DIR/data/torrent-settings.py"' "$X"
check "...and its file is readable by you only" bash -c 'grep -qF "(umask 077 && printf" "$1" && grep -qF "chmod 600 \"\$AUTH_FILE\"" "$1"' _ "$X"
check "the service can't see /home, and may write only its own folders" \
    bash -c 'grep -qF "ProtectHome=true" "$1" && grep -qF "ProtectSystem=strict" "$1" && grep -qF "ReadWritePaths=/var/lib/transmission-daemon /etc/transmission-daemon \$DIR" "$1"' _ "$X"
check "both download folders give what is made in them your group (setgid; a finished file is renamed across)" \
    bash -c '[ "$(grep -cE "install -d -o \"\\\$NAME\" -g \"\\\$\(id -gn\)\" -m 2750 \"\\\$(DL|PARTIAL)\"" "$1")" = 2 ]' _ "$X"
check "the firewall keeps it off the network with the sandboxed Firefox's rules" bash -c '
    a=$(sed -n "/chain firefox {/,\$p" "$1/data/firefox-firewall.nft" | sed "s/chain firefox/chain X/")
    b=$(sed -n "/chain torrent {/,\$p" "$1/data/torrent-firewall.nft" | sed "s/chain torrent/chain X/")
    [ -n "$a" ] && [ "$a" = "$b" ] && grep -qF "meta skuid \"debian-transmission\" jump torrent" "$1/data/torrent-firewall.nft"' _ "$HERE"
# With the Mullvad app's firewall too: a packet must pass every table, so this
# one must only ever reject (no drop policy, no verdict but its rejects), and
# let DNS through before it rejects private addresses: Mullvad's DNS is
# 10.64.0.1, inside the tunnel
F=$HERE/data/torrent-firewall.nft
check "with Mullvad: the rule's table only rejects (its policy accepts, nothing is dropped)" \
    bash -c 'grep -q "policy accept;" "$1" && ! grep -qE "^[^#]*\bdrop\b" "$1" && ! grep -qE "^[^#]*policy drop" "$1"' _ "$F"
check "...and DNS (Mullvad's is 10.64.0.1) is let through before private addresses are rejected" \
    python3 -I -c 'import sys; s = open(sys.argv[1]).read(); assert s.index("udp dport 53 accept") < s.index("10.0.0.0/8") and s.index("tcp dport 53 accept") < s.index("10.0.0.0/8")' "$F"
remove=$(sed -n '/^if \[ "${1:-}" = --remove \]/,/^fi$/p' "$X")
for thing in '"$DROPIN"' '"$FIREWALL"' '"$UNIT"' 'nft delete table inet debsway_torrent' 'remove_bin torrent' 'rm -f "$AUTH_FILE"' 'apt_purge'; do
    check "--remove takes out $thing" grep -qF -- "$thing" <<<"$remove"
done
check "--remove asks before deleting downloads that are still there" grep -qF 'ask "Delete $DIR and everything in it?" n' <<<"$remove"

[ "$fails" -eq 0 ]
