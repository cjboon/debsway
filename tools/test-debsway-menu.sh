#!/bin/bash
# Checks bin/debsway-menu (the menu behind "debsway" in the bar) with a pretend
# wmenu that picks an entry and a pretend foot that only writes down how it was
# started. Changes nothing. Run by test.sh, or:  bash tools/test-debsway-menu.sh
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

mkdir -p "$T/fake" "$T/home/.local/bin" "$T/debsway"
# shellcheck disable=SC2016  # written into the pretend programs, expanded when they run
# wmenu: write down the entries it was shown, then "choose" $PICK (nothing = Escape)
printf '#!/bin/sh\ncat >"%s/entries"\n[ -n "$PICK" ] && echo "$PICK"\n' "$T" >"$T/fake/wmenu"
# foot: write down its arguments, one per line
printf '#!/bin/sh\nprintf "%%s\\n" "$@" >"%s/foot"\n' "$T" >"$T/fake/foot"
chmod +x "$T/fake/"*
export PATH="$T/fake:$PATH" HOME="$T/home"
: >"$T/debsway/update.sh"

menu() { rm -f "$T/foot" "$T/entries"; PICK=$1 DEBSWAY_DIR=${2-$T/debsway} sh "$HERE/bin/debsway-menu"; }

menu "" 
check "the menu shows Help, Install apps, Update and Status" test "$(paste -sd, "$T/entries")" = "Help,Install apps,Update,Status"
check "Escape starts nothing" test ! -e "$T/foot"

menu Help
check "Help opens the key cheat sheet" grep -qx "$T/home/.local/bin/keys" "$T/foot"
check "Help uses the keys window" grep -qx -e --app-id=debsway-keys "$T/foot"

menu Update
check "Update runs update.sh in the debsway folder" grep -qxF update.sh "$T/foot"
check "...given the folder as an argument, not pasted into a command" grep -qxF "$T/debsway" "$T/foot"
check "...in the window the sway rule makes floating" grep -qx -e --app-id=debsway-run "$T/foot"

menu "Install apps"
check "Install apps runs install-extras.sh" grep -qxF install-extras.sh "$T/foot"

menu Status
check "Status shows status.sh in a pager" grep -q 'status.sh | less' "$T/foot"

menu "" "$T/nowhere"
check "without the debsway folder only Help is offered" test "$(cat "$T/entries")" = Help

menu Help "$T/nowhere"
check "...and Help still works" grep -qx "$T/home/.local/bin/keys" "$T/foot"

# A folder name with spaces and quotes is data, not code
mkdir -p "$T/my 'dir\""
: >"$T/my 'dir\"/update.sh"
menu Update "$T/my 'dir\""
check "a folder name with quotes is passed through as one argument" grep -qxF "$T/my 'dir\"" "$T/foot"

# the bar item: the old name is gone and the new click opens the menu
check "the bar shows debsway" grep -q '"full_text":"debsway"' "$HERE/bin/sway-status"
check "the bar's old Help block is gone" not grep -q '"name":"help"' "$HERE/bin/sway-status"
check "a click on debsway starts the menu" grep -q 'debsway-menu' "$HERE/bin/sway-status"

[ "$fails" -eq 0 ]
