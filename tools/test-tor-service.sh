#!/bin/bash
# Checks who decides about the system tor service (tor@default): apt over Tor
# and remote access use it, OnionShare masks it, and none of them may switch it
# off or mask it while another still needs it (system_tor_wanted, lib/tor.sh),
# on a pretend /etc. Changes nothing. Run by test.sh, or:
#   bash tools/test-tor-service.sh
# shellcheck disable=SC2016  # the inner bash expands its own variables
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck disable=SC1091
. "$HERE/lib.sh"
set +e +o pipefail

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
fails=0
check() { # DESCRIPTION CONDITION-COMMAND...
    local what=$1
    shift
    if "$@" >/dev/null 2>&1; then printf '  ok    %s\n' "$what"; else printf '  FAIL  %s\n' "$what"; fails=$((fails + 1)); fi
}
yes_() { if "$@"; then echo yes; else echo no; fi; }

export DEBSWAY_ETC=$T/etc
mkdir -p "$T/etc/tor"
check "nothing set up: nobody wants the tor service" test "$(yes_ system_tor_wanted)" = no
touch "$T/etc/tor/.debsway-remote-access"
check "remote access set up: it is wanted (so OnionShare must not mask it)" test "$(yes_ system_tor_wanted)" = yes
check "...but not by anyone else, when remote access removes itself" \
    test "$(yes_ system_tor_wanted .debsway-remote-access)" = no
check "apt over Tor, removing itself, still sees remote access" \
    test "$(yes_ system_tor_wanted .debsway-apt-tor)" = yes
touch "$T/etc/tor/.debsway-apt-tor"
check "both set up: remote access removing itself leaves it wanted" \
    test "$(yes_ system_tor_wanted .debsway-remote-access)" = yes

# Every script that marks itself as a user of the tor service is on the list,
# and the scripts that stop or mask it ask the list, not one mark of their own
for f in "$HERE"/parts/*.sh "$HERE"/extras/*.sh; do
    mark=$(sed -n 's|^MARK=/etc/tor/\(\.debsway-[a-z-]*\)$|\1|p' "$f")
    [ -n "$mark" ] || continue
    check "${f#"$HERE"/}: its mark $mark is on the list" grep -qw -- "$mark" <<<" $TOR_SERVICE_MARKS "
done
for f in extras/onionshare.sh parts/apt-tor.sh extras/remote-access.sh; do
    check "$f doesn't decide about the tor service from one mark alone" \
        bash -c '! grep -nE "(if|&&|\|\|) \[ !? ?-[ef] (\"\\\$APT_TOR_MARK\"|/etc/tor/\.debsway-)" "$1"' _ "$HERE/$f"
done
check "OnionShare masks the tor service only when nobody needs it" \
    bash -c 'grep -B8 "systemctl mask tor.service" "$1" | grep -q "system_tor_wanted"' _ "$HERE/extras/onionshare.sh"

[ "$fails" -eq 0 ]
