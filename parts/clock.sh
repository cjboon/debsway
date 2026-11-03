#!/bin/bash
# The clock: kept right over the network, and showing your local time.
# A Debian installed with "standard system utilities" only can have no NTP
# client at all (then nothing ever corrects the clock), and Wren Linux's install
# stick used to set the time zone to UTC, so the bar showed UTC, not your time.
#  - systemd-timesyncd sets the clock from Debian's time servers
#    (debian.pool.ntp.org) and keeps it right. This is plain NTP: your network
#    can see that this computer asks for the time, and that it runs Debian.
#    Tor needs a right clock: off by more than a few hours, it can't connect.
#  - The time zone: while it is UTC, this asks for yours (Enter keeps UTC).
#    Run it again to change it. An unattended run (the base install's
#    defaults) leaves it as it is.
# Usage: bash clock.sh [--remove]
# status: apt:systemd-timesyncd
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
need_user

if [ "${1:-}" = --remove ]; then
    apt_purge systemd-timesyncd
    note "The clock is no longer set over the network. The time zone stays as it is."
    exit
fi

say "Keeping the clock right"
apt_install systemd-timesyncd
sudo timedatectl set-ntp true ||
    warn "Couldn't switch on setting the clock over the network; check: timedatectl"
note "The clock is set from debian.pool.ntp.org and kept right (check: timedatectl)."

say "Time zone"
zone=$(timedatectl show -p Timezone --value 2>/dev/null || true)
case $zone in '' | UTC | Etc/UTC | Etc/UCT | UCT | Etc/Universal | Universal | Etc/Zulu | Zulu) utc=true ;; *) utc=false ;; esac
if [ -n "${WREN_NONINTERACTIVE:-}" ]; then
    note "Time zone: ${zone:-UTC}. Change it with: bash $WREN_DIR/parts/clock.sh"
elif $utc || ! ask "The time zone is $zone. Keep it?" y; then
    $utc && note "The time zone is UTC, so the clock in the bar shows UTC, not your local time."
    note "Type yours as Area/City, like America/New_York, Europe/Berlin or Asia/Tokyo"
    note "(all of them: timedatectl list-timezones)."
    want=''
    for _ in 1 2 3; do
        tty_read want "    time zone (Enter keeps ${zone:-UTC})> "
        [ -n "$want" ] || break
        if timedatectl list-timezones 2>/dev/null | grep -qxF -- "$want"; then break; fi
        warn "\"$want\" isn't a time zone. Look it up with: timedatectl list-timezones | grep -i CITY"
        want=''
    done
    if [ -n "$want" ]; then
        sudo timedatectl set-timezone "$want"
        note "Time zone: $want. The bar shows the new time within a few seconds."
    else
        note "Kept ${zone:-UTC}. Change it any time with: bash $WREN_DIR/parts/clock.sh"
    fi
else
    note "Kept $zone."
fi
