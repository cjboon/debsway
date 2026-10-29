#!/bin/bash
# Checks the cheat sheet filter (bin/keys and the "@if COMMAND" ... "@end" blocks
# of data/keys.txt): a block shows only if its command is installed. Uses pretend
# commands in a PATH of their own. Changes nothing. Run by test.sh, or:
#   bash tools/test-keys.sh
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

mkdir -p "$T/home/.local/share/debsway" "$T/bin"
cp "$HERE/data/keys.txt" "$T/home/.local/share/debsway/keys.txt"
# a PATH with the tools the filter itself needs, and only the commands we choose to add
for c in sh awk sed cat grep rm cp mktemp; do ln -s "$(command -v "$c")" "$T/bin/$c"; done
keys() { env -i HOME="$T/home" PATH="$T/bin" sh "$HERE/bin/keys" "$@"; }
have() { for c in "$@"; do printf '#!/bin/sh\n' >"$T/bin/$c"; chmod +x "$T/bin/$c"; done; }

out=$(keys --text)
check "with nothing optional installed there is a cheat sheet" grep -q 'START HERE' <<<"$out"
check "...with the lock key (always there)" grep -q 'Super+Escape' <<<"$out"
for word in 'Brightness keys' 'Volume keys' 'Print  ' 'claude-pull' 'nmtui' 'powerprofilesctl' 'udiskie-umount' 'wpctl status' 'ublock-allow'; do
    check "...without $word" not grep -q "$word" <<<"$out"
done
check "no marker lines are left in it" not grep -q '^@' <<<"$out"

have brightness volume
out=$(keys --text)
check "with brightness installed its keys appear" grep -q 'Brightness keys' <<<"$out"
check "with volume installed the volume keys and wpctl line appear" grep -q 'wpctl status' <<<"$out"
check "...but screenshots still do not" not grep -q 'Print  ' <<<"$out"
have screenshot
check "with screenshot installed the Print key appears" grep -q 'Print  ' <(keys --text)

# every marker in the real sheet is closed and names a command
check "every @if has an @end" test "$(grep -c '^@if ' "$HERE/data/keys.txt")" = "$(grep -c '^@end' "$HERE/data/keys.txt")"
check "no @if is nested or left open" python3 -I -c '
import sys
depth = 0
for line in open(sys.argv[1]):
    if line.startswith("@if "):
        assert depth == 0 and len(line.split()) == 2, line
        depth = 1
    elif line.startswith("@end"):
        assert depth == 1
        depth = 0
assert depth == 0
' "$HERE/data/keys.txt"

# ~/KEYS.txt follows along, but a file of your own with that name is left alone
have claude
keys --text >/dev/null
: >"$T/home/KEYS.txt"; echo "my notes" >"$T/home/KEYS.txt"
env -i HOME="$T/home" PATH="$T/bin" sh "$HERE/bin/keys" </dev/null >/dev/null 2>&1
check "a KEYS.txt of your own is not overwritten" grep -qx 'my notes' "$T/home/KEYS.txt"
rm -f "$T/home/KEYS.txt"
env -i HOME="$T/home" PATH="$T/bin" sh "$HERE/bin/keys" </dev/null >/dev/null 2>&1
check "a missing KEYS.txt is written as a plain file" test -f "$T/home/KEYS.txt" -a ! -L "$T/home/KEYS.txt"
check "...without the lines for what is not installed" not grep -q 'nmtui' "$T/home/KEYS.txt"

[ "$fails" -eq 0 ]
