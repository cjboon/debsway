#!/bin/bash
# Your home folder private to you, also from Wren Linux's own sandbox users.
# The sandboxed Firefox (firefox, fx-NAME) and Claude (claude-agent...) users
# are given passage through your home (--x) to reach the one folder they share
# with you (~/Downloads, ~/projects). Passage means they can't list your home,
# but they can open any folder or file in it whose name they know or guess
# (~/.bashrc, ~/.config, ~/Documents...) if its "others" permission allows,
# and Debian's default (umask 002 or 022) does allow reading. Then a hacked
# browser could read your files after all.
#  - "Others" lose all access to everything directly in your home folder
#    (folders and files; links are left alone). Behind a closed folder,
#    nothing deeper can be reached, so that is enough. Folders shared with a
#    sandbox keep it: they name that user in an ACL, which this doesn't touch.
#  - New files and folders start private (umask 077: only you), set at the
#    top of ~/.profile, so sway and everything it starts get it.
#  - sudo would combine that with its own, so root's files made through sudo
#    (Wren Linux's settings in /etc, which a sandbox user must read) would be
#    root's alone: a sudo rule gives commands run through sudo Debian's usual
#    umask (022), as before.
# Your own access doesn't change; programs that run as you see everything as
# before. Usage: bash home-private.sh [--remove]
# status: file:~/.config/wren/home-private
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
need_user

PROFILE=$HOME/.profile
MARK=$HOME/.config/wren/home-private
SUDOERS=/etc/sudoers.d/wren-umask
BEGIN='# >>> Wren Linux home-private >>>'
END='# <<< Wren Linux home-private <<<'

take_out() { [ -f "$PROFILE" ] && sed -i "\\|^$BEGIN\$|,\\|^$END\$|d" "$PROFILE"; return 0; }

if [ "${1:-}" = --remove ]; then
    take_out
    sudo rm -f "$SUDOERS"
    rm -f "$MARK"
    note "New files get the system's default permissions again from your next login."
    note "What this made private stays private (chmod o+rx a folder yourself to open it)."
    exit
fi

say "Commands run through sudo keep Debian's usual umask"
rule=$(mktemp)
printf '%s\n' '# Written by Wren Linux parts/home-private.sh: your umask is 077 (only you);' \
    "# commands run through sudo get Debian's usual 022 instead of the union of both," \
    "# so the files they make in /etc can be read by the users that need them." \
    'Defaults umask=0022' 'Defaults umask_override' >"$rule"
if ! sudo visudo -cf "$rule" >/dev/null; then
    rm -f "$rule"
    die "The sudoers rule didn't pass visudo's check, so nothing was changed."
fi
sudo install -o root -g root -m 0440 "$rule" "$SUDOERS"
rm -f "$rule"

say "Your home folder, private to you"
chmod go-w "$HOME"
chmod o-rwx "$HOME"
opened=0
while IFS= read -r -d '' f; do
    chmod o-rwx "$f" && opened=$((opened + 1))
done < <(find "$HOME" -mindepth 1 -maxdepth 1 ! -type l -perm /o=rwx -print0)
note "Closed to others: $opened folders and files directly in your home."

# At the very top of ~/.profile: the autostart block further down starts sway
# and never returns, so anything after it would never run
take_out
touch "$PROFILE"
{
    printf '%s\n' "$BEGIN" '# New files and folders: only you (Wren Linux parts/home-private.sh)' 'umask 077' "$END"
    cat "$PROFILE"
} >"$PROFILE.wren-new"
cat "$PROFILE.wren-new" >"$PROFILE"
rm -f "$PROFILE.wren-new"
umask 077
mkdir -p "${MARK%/*}"
: >"$MARK"
note "New files and folders are only yours from your next login."
