#!/bin/sh
# preseed/late_command for Wren Linux's install ISO (prep/make-install-iso.sh):
# runs inside the Debian installer at the end, with the new system in /target.
# It installs Wren Linux's package from the ISO into the new system: root's,
# read-only to the user, in /usr/share/wren (nothing of it in the home
# folder). The saved downloads (the Wi-Fi packages, Tor Browser...) go to the
# user's ~/.local/share/wren/offline. It adds to ~/.profile a question asked
# once at the first login on the console: set Wren Linux up now? (yes runs
# bash /usr/share/wren/start.sh, as the user, on the running system).
# With --autologin, tty1 then logs the user in without the password.
#   late.sh USERNAME
set -e
user=$1
case $user in '' | *[!a-z0-9_-]*) echo "late.sh: bad user name '$user'" >&2; exit 1 ;; esac
inst=/cdrom/wren-install
[ -d "$inst" ] || exit 0
[ -d "/target/home/$user" ] || { echo "late.sh: /home/$user is missing in the new system" >&2; exit 1; }
# The package: only bash and sudo are needed, which the new system has, so it
# installs without a network. It has no install scripts: it only puts files
# in place. If it doesn't go in, say so and stop: Wren Linux is never copied
# into the home folder instead.
set -- "$inst"/wren-linux_*_all.deb
[ -f "$1" ] || { echo "late.sh: there is no Wren Linux package on the ISO" >&2; exit 1; }
cp "$1" /target/tmp/wren-linux.deb
if ! in-target dpkg -i /tmp/wren-linux.deb; then
    echo "late.sh: the Wren Linux package didn't install; after the first boot: sudo apt install /media/.../wren-install/${1##*/}" >&2
    rm -f /target/tmp/wren-linux.deb
    exit 1
fi
rm -f /target/tmp/wren-linux.deb
# The saved downloads, the user's
if [ -d "$inst/offline" ]; then
    mkdir -p "/target/home/$user/.local/share/wren"
    rm -rf "/target/home/$user/.local/share/wren/offline"
    cp -R "$inst/offline" "/target/home/$user/.local/share/wren/offline"
    find "/target/home/$user/.local/share/wren/offline" -type d -exec chmod 755 {} \;
    find "/target/home/$user/.local/share/wren/offline" -type f -exec chmod 644 {} \;
    in-target chown -R "$user:$user" "/home/$user/.local"
fi
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
