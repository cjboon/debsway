#!/bin/bash
# Checks the Super+d launcher line (lib/sway.sh style_launcher / unstyle_launcher,
# used by parts/wmenu.sh) on pretend sway configs. Changes nothing outside a
# temp folder. Run by test.sh, or:  bash tools/test-launcher.sh
# shellcheck disable=SC2016  # sway's $menu and $mod are not shell variables
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
set +e +o pipefail

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
fails=0
check() { # DESCRIPTION CONDITION-COMMAND...
    local what=$1
    shift
    if "$@" >/dev/null 2>&1; then printf '  ok    %s\n' "$what"; else printf '  FAIL  %s\n' "$what"; fails=$((fails + 1)); fi
}
not() { ! "$@"; }

# the lines of sway's stock config that matter, with others around them
printf '%s\n' 'set $term foot' 'set $menu wmenu-run' 'bindsym $mod+d exec $menu' 'bar {' '    position top' '}' >"$T/stock"

cp "$T/stock" "$T/c"
style_launcher "$T/c"
check "the stock launcher line is replaced" grep -qxF "$LAUNCHER_STYLED" "$T/c"
check "...and nothing else changes" test "$(diff "$T/stock" "$T/c" | grep -c '^[<>]')" -eq 2
check "the Super+d binding is untouched" grep -qxF 'bindsym $mod+d exec $menu' "$T/c"
cp "$T/c" "$T/once"
style_launcher "$T/c"
check "doing it twice changes nothing more" cmp -s "$T/c" "$T/once"
unstyle_launcher "$T/c"
check "undoing it gives back the stock config exactly" cmp -s "$T/c" "$T/stock"

printf '%s\n' 'set $menu wmenu-run -f "Iosevka 14"' 'bindsym $mod+d exec $menu' >"$T/mine"
cp "$T/mine" "$T/mine.before"
style_launcher "$T/mine"; rc=$?
check "...with a failure status" test "$rc" -ne 0
check "...and left exactly as it was" cmp -s "$T/mine" "$T/mine.before"

# the options are ones wmenu has, and the colors are opaque (6 digits, no alpha)
check "only options wmenu documents are used" python3 -I -c '
import re, sys
line = sys.argv[1]
opts = re.findall(r"\s-([A-Za-z])\s", " " + line + " ")
assert set(opts) <= set("fNnMmSs"), opts
'  "$LAUNCHER_STYLED"
check "every color is opaque: six hex digits, no alpha" python3 -I -c '
import re, sys
vals = re.findall(r"\s-[NnMmSs]\s+(\S+)", sys.argv[1])
assert len(vals) == 6 and all(re.fullmatch(r"[0-9a-f]{6}", v) for v in vals), vals
' "$LAUNCHER_STYLED"
check "the font is bigger than a default bar's (10)" python3 -I -c '
import re, sys
size = int(re.search(r"monospace (\d+)", sys.argv[1]).group(1))
assert size > 10, size
' "$LAUNCHER_STYLED"

[ "$fails" -eq 0 ]
