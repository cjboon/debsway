#!/bin/bash
# Checks the cheat sheet filter (bin/keys and the "@if COMMAND" ... "@end" blocks
# of data/keys.txt): a block shows only if its command is installed. Uses pretend
# commands in a PATH of their own. Changes nothing. Run by test.sh, or:
#   bash tools/test-keys.sh
# shellcheck disable=SC2016  # sway's $mod is not a shell variable
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

# Alt or Super: the sheet follows the set $mod line of your sway config
CONF=$T/home/.config/sway/config
mkdir -p "${CONF%/*}"
printf '%s\n' '# sway config' 'set $mod Mod4' 'bindsym $mod+Return exec foot' >"$CONF"
out=$(keys --text)
check "with Super as sway's key the sheet says Super+d" grep -q 'Super+d ' <<<"$out"
check "program shortcuts are on it: Ctrl+w closes a tab" grep -q 'Ctrl+w .*close the tab' <<<"$out"
check "...and Ctrl+q quits the program" grep -q 'Ctrl+q .*quit the program' <<<"$out"
check "how to switch the key is on it" grep -q 'keys --mod alt' <<<"$out"
keys --mod alt >/dev/null
check "keys --mod alt sets Mod1 in the sway config" grep -qx 'set $mod Mod1' "$CONF"
check "...and leaves the rest of it alone" grep -qx 'bindsym $mod+Return exec foot' "$CONF"
out=$(keys --text)
check "then the sheet says Alt+d" grep -q 'Alt+d ' <<<"$out"
check "...and no Super anywhere" not grep -q 'Super' <<<"$out"
check "...and its first line says Alt is sway's key" grep -q "Alt = sway's key" <<<"$(head -1 <<<"$out")"
check "Ctrl+Alt+F2 is still Ctrl+Alt+F2" grep -q 'Ctrl+Alt+F2' <<<"$out"
keys --mod super >/dev/null
check "keys --mod super puts Mod4 back" grep -qx 'set $mod Mod4' "$CONF"
check "a wrong word for --mod is refused" not keys --mod hyper
printf '%s\n' 'set $mod Mod3' >"$CONF"
check "a config with some other mod key is refused" not keys --mod alt
check "...and not changed" grep -qx 'set $mod Mod3' "$CONF"

# The first login asks which key, then shows the sheet (less is a pretend one here)
ln -s "$(command -v cat)" "$T/bin/less"
printf '%s\n' '# sway config' 'set $mod Mod4' >"$CONF"
out=$(printf '2\n\n' | keys --welcome 2>&1)
check "the first login asks Super or Alt" grep -q '2) Alt' <<<"$out"
check "answering 2 sets Alt" grep -qx 'set $mod Mod1' "$CONF"
check "...and then shows the sheet with Alt" grep -q 'Alt+Enter' <<<"$out"
printf '%s\n' '# sway config' 'set $mod Mod4' >"$CONF"
printf '\n\n' | keys --welcome >/dev/null 2>&1
check "pressing Enter keeps Super" grep -qx 'set $mod Mod4' "$CONF"

[ "$fails" -eq 0 ]
