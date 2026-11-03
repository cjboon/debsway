#!/bin/sh
# preseed/late_command for Wren Linux's install ISO (prep/make-install-iso.sh):
# runs inside the Debian installer at the end, with the new system in /target.
# It copies Wren Linux from the ISO to the new user's ~/wren, owned by them,
# with the folders and scripts as they should be, and adds to ~/.profile a
# question asked once at the first login on the console: set Wren Linux up now?
# (yes runs bash ~/wren/start.sh, as the user, on the running system).
# With --autologin, tty1 then logs the user in without the password.
#   late.sh USERNAME
set -e
user=$1
case $user in '' | *[!a-z0-9_-]*) echo "late.sh: bad user name '$user'" >&2; exit 1 ;; esac
src=/cdrom/wren
dest=/target/home/$user/wren
[ -d "$src" ] || exit 0
[ -d "/target/home/$user" ] || { echo "late.sh: /home/$user is missing in the new system" >&2; exit 1; }
rm -rf "$dest"
cp -R "$src" "$dest"
# The ISO's files are all read-only; give them the usual modes back
find "$dest" -type d -exec chmod 755 {} \;
find "$dest" -type f -exec chmod 644 {} \;
find "$dest" -type f \( -name '*.sh' -o -path "$dest/bin/*" \) -exec chmod 755 {} \;
in-target chown -R "$user:$user" "/home/$user/wren"
# The first-login question (once, even if this runs again)
profile=/target/home/$user/.profile
if [ -f /cdrom/wren-install/first-login.sh ] && ! grep -q '^# >>> Wren Linux first login >>>$' "$profile" 2>/dev/null; then
    [ -f "$profile" ] || in-target cp /etc/skel/.profile "/home/$user/.profile"
    cat /cdrom/wren-install/first-login.sh >>"$profile"
    in-target chown "$user:$user" "/home/$user/.profile"
fi
# Logged in on tty1 without a password (make-install-iso.sh --autologin)
if [ -f /cdrom/wren-install/autologin.conf ]; then
    mkdir -p /target/etc/systemd/system/getty@tty1.service.d
    cp /cdrom/wren-install/autologin.conf /target/etc/systemd/system/getty@tty1.service.d/50-wren-autologin.conf
    chmod 644 /target/etc/systemd/system/getty@tty1.service.d/50-wren-autologin.conf
fi
# Extras ticked in the first install list (make-install-iso.sh --simplesway)
if [ -f /cdrom/wren-install/preselect ]; then
    mkdir -p "/target/home/$user/.config/wren"
    cp /cdrom/wren-install/preselect "/target/home/$user/.config/wren/preselect"
    chmod 644 "/target/home/$user/.config/wren/preselect"
    in-target chown -R "$user:$user" "/home/$user/.config"
fi
# The user's own extra scripts, if the ISO has any
if [ -d /cdrom/wren-install/scripts ]; then
    rm -rf "/target/home/$user/scripts"
    cp -R /cdrom/wren-install/scripts "/target/home/$user/scripts"
    find "/target/home/$user/scripts" -type d -exec chmod 755 {} \;
    find "/target/home/$user/scripts" -type f -exec chmod 644 {} \;
    in-target chown -R "$user:$user" "/home/$user/scripts"
fi
exit 0
