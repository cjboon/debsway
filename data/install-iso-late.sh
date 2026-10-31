#!/bin/sh
# preseed/late_command for debsway's install ISO (prep/make-install-iso.sh):
# runs inside the Debian installer at the end, with the new system in /target.
# It copies debsway from the ISO to the new user's ~/debsway, owned by them,
# with the folders and scripts as they should be, and adds to ~/.profile a
# question asked once at the first login on the console: set debsway up now?
# (yes runs bash ~/debsway/start.sh, as the user, on the running system)
#   late.sh USERNAME
set -e
user=$1
case $user in '' | *[!a-z0-9_-]*) echo "late.sh: bad user name '$user'" >&2; exit 1 ;; esac
src=/cdrom/debsway
dest=/target/home/$user/debsway
[ -d "$src" ] || exit 0
[ -d "/target/home/$user" ] || { echo "late.sh: /home/$user is missing in the new system" >&2; exit 1; }
rm -rf "$dest"
cp -R "$src" "$dest"
# The ISO's files are all read-only; give them the usual modes back
find "$dest" -type d -exec chmod 755 {} \;
find "$dest" -type f -exec chmod 644 {} \;
find "$dest" -type f \( -name '*.sh' -o -path "$dest/bin/*" \) -exec chmod 755 {} \;
in-target chown -R "$user:$user" "/home/$user/debsway"
# The first-login question (once, even if this runs again)
profile=/target/home/$user/.profile
if [ -f /cdrom/debsway-install/first-login.sh ] && ! grep -q '^# >>> debsway first login >>>$' "$profile" 2>/dev/null; then
    [ -f "$profile" ] || in-target cp /etc/skel/.profile "/home/$user/.profile"
    cat /cdrom/debsway-install/first-login.sh >>"$profile"
    in-target chown "$user:$user" "/home/$user/.profile"
fi
# The user's own extra scripts, if the ISO has any
if [ -d /cdrom/debsway-install/scripts ]; then
    rm -rf "/target/home/$user/scripts"
    cp -R /cdrom/debsway-install/scripts "/target/home/$user/scripts"
    find "/target/home/$user/scripts" -type d -exec chmod 755 {} \;
    find "/target/home/$user/scripts" -type f -exec chmod 644 {} \;
    in-target chown -R "$user:$user" "/home/$user/scripts"
fi
exit 0
