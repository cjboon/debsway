#!/bin/bash
# Checks parts/home-private.sh on a temp home with a pretend sudo: "others"
# lose access to what is directly in it (folders and files, not links), a
# folder shared with a sandbox through an ACL keeps that, umask 077 goes at
# the very top of ~/.profile (once, above the block that starts sway), the
# sudo umask rule passes visudo, and --remove takes the umask out again.
# Nothing of this computer is changed. Run by test.sh, or:  bash tools/test-home-private.sh
# shellcheck disable=SC2016  # the inner shells expand their own variables
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
T=$(mktemp -d)
trap 'chmod -R u+rwX "$T" 2>/dev/null; rm -rf "$T"' EXIT
fails=0
check() { # DESCRIPTION CONDITION-COMMAND...
    local what=$1
    shift
    if "$@" >/dev/null 2>&1; then printf '  ok    %s\n' "$what"; else printf '  FAIL  %s\n' "$what"; fails=$((fails + 1)); fi
}

R=$T/r
H=$T/home
mkdir -p "$R/parts" "$T/bin" "$T/etc" "$H/Documents" "$H/Downloads" "$T/elsewhere"
sed 's|^export PATH=.*|export PATH="$HP_TEST_PATH"|' "$HERE/lib.sh" >"$R/lib.sh"
grep -q HP_TEST_PATH "$R/lib.sh" || { echo "  FAIL  lib.sh's PATH line wasn't found"; exit 1; }
for f in packages.sh pins.sh lib data bin docs; do ln -s "$HERE/$f" "$R/$f"; done
sed "s|/etc/sudoers.d/debsway-umask|$T/etc/debsway-umask|" "$HERE/parts/home-private.sh" >"$R/parts/home-private.sh"
cat >"$T/bin/sudo" <<'SUDO'
#!/bin/bash
# a pretend sudo: runs it as this user (install without -o/-g, which only root may give)
while [ "${1#-}" != "$1" ]; do shift; done
[ $# -gt 0 ] || exit 0
if [ "$1" = install ]; then
    a=()
    while [ $# -gt 0 ]; do case $1 in -o | -g) shift 2 ;; *) a+=("$1"); shift ;; esac; done
    set -- "${a[@]}"
fi
[ "$1" != visudo ] || set -- /usr/sbin/visudo "${@:2}"
exec "$@"
SUDO
chmod +x "$T/bin/sudo"
[ "$(HP_TEST_PATH="$T/bin:$PATH" bash -c '. "$1/lib.sh"; command -v sudo' _ "$R")" = "$T/bin/sudo" ] ||
    { echo "  FAIL  the real sudo would run; stopping"; exit 1; }
part() { HOME=$H HP_TEST_PATH="$T/bin:$PATH" bash "$R/parts/home-private.sh" "$@" >"$T/out" 2>&1; }

chmod 0755 "$H/Documents"
echo secret >"$H/Documents/passwords.kdbx"
echo 'alias ll="ls -l"' >"$H/.bashrc"
chmod 0644 "$H/.bashrc" "$H/Documents/passwords.kdbx"
chmod 0775 "$H/Downloads"
setfacl -m "u:root:--x" "$H/Downloads"
chmod 0755 "$T/elsewhere"
ln -s "$T/elsewhere" "$H/link"
printf '%s\n' '# the autostart block' 'exec sway' >"$H/.profile"

part
check "folders directly in your home: closed to others" test "$(stat -c %a "$H/Documents")" = 750
check "files directly in it: unreadable to others" test "$(stat -c %a "$H/.bashrc")" = 640
check "...your own access unchanged" bash -c '[ -r "$1/Documents/passwords.kdbx" ] && [ -w "$1/.bashrc" ]' _ "$H"
check "a folder shared through an ACL keeps that user" bash -c 'getfacl -p "$1/Downloads" | grep -qx "user:root:--x"' _ "$H"
check "...and is closed to everyone else" test "$(stat -c %a "$H/Downloads" | cut -c3)" = 0
check "a link is left alone (and what it points to)" test "$(stat -c %a "$T/elsewhere")" = 755
check "umask 077 at the very top of ~/.profile, above the block that starts sway" bash -c '
    [ "$(sed -n 1p "$1")" = "# >>> debsway home-private >>>" ] && grep -qx "umask 077" "$1" &&
    [ "$(grep -n "^umask 077$" "$1" | cut -d: -f1)" -lt "$(grep -n "^exec sway$" "$1" | cut -d: -f1)" ]' _ "$H/.profile"
check "the sudo umask rule: Debian's usual 022 through sudo, and visudo accepts it" bash -c '
    grep -qx "Defaults umask=0022" "$1" && grep -qx "Defaults umask_override" "$1" && /usr/sbin/visudo -cf "$1"' _ "$T/etc/debsway-umask"
part
check "a re-run: one block, ~/.profile otherwise as it was" bash -c '
    [ "$(grep -c "^# >>> debsway home-private >>>$" "$1")" = 1 ] && [ "$(tail -2 "$1")" = "$(printf "# the autostart block\nexec sway")" ]' _ "$H/.profile"
part --remove
check "--remove: the umask block and the sudo rule go" bash -c '
    ! grep -q "home-private" "$1" && [ ! -e "$2" ] && [ "$(cat "$1")" = "$(printf "# the autostart block\nexec sway")" ]' _ "$H/.profile" "$T/etc/debsway-umask"
check "it is the second base part, before anything else writes files" bash -c '
    . "$1/packages.sh"; [ "${PARTS[1]}" = home-private ]' _ "$HERE"

[ "$fails" -eq 0 ]
