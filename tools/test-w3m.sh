#!/bin/bash
# Checks bin/w3m (w3m's cookies kept only while it is open): the cookie file
# is deleted when it starts and when it ends, also when its terminal closes;
# arguments and exit status pass through; the real w3m is found further on
# the PATH, never itself. With a pretend w3m, in a temp folder.
# Run by test.sh, or:  bash tools/test-w3m.sh
# shellcheck disable=SC2016  # the pretend program expands its own variables
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

# mine/ holds the wrapper (as ~/.local/bin does), real/ the pretend w3m: it
# says whether the cookie file was there at its start, keeps a cookie, and
# ends with status 7 (or waits, with "wait" as its argument)
mkdir -p "$T/mine" "$T/also" "$T/real" "$T/home/.w3m"
cp "$HERE/bin/w3m" "$T/mine/w3m"
chmod +x "$T/mine/w3m"
ln -s "$T/mine/w3m" "$T/also/w3m"
cat >"$T/real/w3m" <<EOF
#!/bin/sh
if [ -e "$T/home/.w3m/cookie" ]; then echo present >"$T/at-start"; else echo absent >"$T/at-start"; fi
echo "\$*" >"$T/args"
echo "example.org	TRUE	/	FALSE	9999999999	sid	abc" >"$T/home/.w3m/cookie"
[ "\$1" = wait ] && { echo up >"$T/up"; exec sleep 30; }
exit 7
EOF
chmod +x "$T/real/w3m"
run() { env HOME="$T/home" PATH="$T/mine:$T/also:$T/real:/usr/bin:/bin" "$T/mine/w3m" "$@" </dev/null >/dev/null 2>&1; }

echo "old	TRUE	/	FALSE	9999999999	sid	old" >"$T/home/.w3m/cookie"
run -dump https://example.org
rc=$?
check "the cookies kept from before are gone when w3m starts" grep -qx absent "$T/at-start"
check "...and the ones it took are gone when it ends" test ! -e "$T/home/.w3m/cookie"
check "its arguments reach w3m, and its exit status comes back" bash -c '[ "$(cat "$1")" = "-dump https://example.org" ] && [ "$2" = 7 ]' _ "$T/args" "$rc"
check "the real w3m is found further on the PATH, not this one (nor a link to it)" test -s "$T/args"
rm -f "$T/args"
env HOME="$T/home" PATH="$T/mine:$T/also:/usr/bin:/bin" "$T/mine/w3m" x </dev/null >"$T/out" 2>&1
rc=$?
check "w3m not installed: it says so, with status 127, and doesn't run itself" \
    bash -c '[ "$1" = 127 ] && grep -q "w3m isn.t installed" "$2" && [ ! -e "$3" ]' _ "$rc" "$T/out" "$T/args"
# its terminal closed while w3m is open (the window shut): a hang-up to every
# program in it, so they run in a group of their own here and all get one
rm -f "$T/up"
setsid env HOME="$T/home" PATH="$T/mine:$T/also:$T/real:/usr/bin:/bin" "$T/mine/w3m" wait </dev/null >/dev/null 2>&1 &
pid=$!
for _ in $(seq 50); do [ -e "$T/up" ] && break; /bin/sleep 0.1; done
kill -HUP -- "-$pid" 2>/dev/null
for _ in $(seq 50); do kill -0 "$pid" 2>/dev/null || break; /bin/sleep 0.1; done
check "its window closed while w3m is open: the cookies are gone too" test ! -e "$T/home/.w3m/cookie"

check "the extra puts it in place and takes it out again" \
    bash -c 'grep -q "^install_bin w3m" "$1" && grep -q "remove_bin w3m" "$1" && grep -q "^# status:.*bin:w3m" "$1"' _ "$HERE/extras/w3m.sh"

[ "$fails" -eq 0 ]
