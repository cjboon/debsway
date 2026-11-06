#!/bin/bash
# This computer's name isn't sent to the networks it joins: dhcpcd and dhclient send it
# unless told otherwise, and on a cable or through wifi.sh, that's what is in use. A name
# like "alex-laptop" says who you are to a café's router, and on every network, it
# says this is the same computer. NetworkManager's own setting is in parts/random-mac.sh.
# Takes effect at each connection's next lease. A few networks show the name on
# their router's list of devices; that line then goes empty.
# Usage: bash dhcp-no-name.sh [--remove]
# status: file:~/.config/wren/dhcp-no-name
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
need_user

# (your user can read these files, but this says it was done, for status.sh)
MARK=$HOME/.config/wren/dhcp-no-name

if [ "${1:-}" = --remove ]; then
    dhcp_no_name off
    rm -f "$MARK"
    note "dhcpcd and dhclient send this computer's name again, as Debian sets them."
    exit
fi

say "This computer's name stays off the networks it joins"
dhcp_no_name on
mkdir -p "${MARK%/*}"
: >"$MARK"
note "dhcpcd and dhclient send no name from their next lease on."
