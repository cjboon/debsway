#!/bin/bash
# Checks who decides about the system tor service (tor@default): apt over Tor
# and remote access use it, OnionShare masks it, and none of them may switch it
# off or mask it while another still needs it (system_tor_wanted, lib/tor.sh),
# on a pretend /etc; and that Tor Browser's AppArmor fix is fully undone.
# Changes nothing. Run by test.sh, or:
#   bash tools/test-tor-service.sh
# shellcheck disable=SC2016  # the inner bash expands its own variables
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck disable=SC1091
. "$HERE/lib.sh"
set +e +o pipefail

T=$(mktemp -d) || { echo "  FAIL  couldn't make a temp folder (is /tmp full?)"; exit 1; }
trap 'rm -rf "$T"' EXIT
fails=0
not() { ! "$@"; }
check() { # DESCRIPTION CONDITION-COMMAND...
    local what=$1
    shift
    if "$@" >/dev/null 2>&1; then printf '  ok    %s\n' "$what"; else printf '  FAIL  %s\n' "$what"; fails=$((fails + 1)); fi
}
yes_() { if "$@"; then echo yes; else echo no; fi; }

export WREN_ETC=$T/etc
mkdir -p "$T/etc/tor"
check "nothing set up: nobody wants the tor service" test "$(yes_ system_tor_wanted)" = no
touch "$T/etc/tor/.wren-remote-access"
check "remote access set up: it is wanted (so OnionShare must not mask it)" test "$(yes_ system_tor_wanted)" = yes
check "...but not by anyone else, when remote access removes itself" \
    test "$(yes_ system_tor_wanted .wren-remote-access)" = no
check "apt over Tor, removing itself, still sees remote access" \
    test "$(yes_ system_tor_wanted .wren-apt-tor)" = yes
touch "$T/etc/tor/.wren-apt-tor"
check "both set up: remote access removing itself leaves it wanted" \
    test "$(yes_ system_tor_wanted .wren-remote-access)" = yes

# Every script that marks itself as a user of the tor service is on the list,
# and the scripts that stop or mask it ask the list, not one mark of their own
for f in "$HERE"/parts/*.sh "$HERE"/extras/*.sh; do
    mark=$(sed -n 's|^MARK=/etc/tor/\(\.wren-[a-z-]*\)$|\1|p' "$f")
    [ -n "$mark" ] || continue
    check "${f#"$HERE"/}: its mark $mark is on the list" grep -qw -- "$mark" <<<" $TOR_SERVICE_MARKS "
done
for f in extras/onionshare.sh parts/apt-tor.sh extras/remote-access.sh; do
    check "$f doesn't decide about the tor service from one mark alone" \
        bash -c '! grep -nE "(if|&&|\|\|) \[ !? ?-[ef] (\"\\\$APT_TOR_MARK\"|/etc/tor/\.wren-)" "$1"' _ "$HERE/$f"
done
# At boot Debian starts tor@default only through tor.service: a script that
# enables tor@default alone leaves Tor off after the next reboot
check "tor_service_on enables tor.service, not just tor@default" \
    bash -c 'sed -n "/^tor_service_on() {/,/^}/p" "$1" | grep -q "systemctl enable tor.service tor@default.service"' _ "$HERE/lib/tor.sh"
for f in parts/apt-tor.sh extras/remote-access.sh extras/onion-site.sh; do
    check "$f starts Tor with tor_service_on (so it also runs after a reboot)" grep -qx 'tor_service_on' "$HERE/$f"
    check "$f doesn't enable or disable tor@default by itself" \
        bash -c '! grep -nE "systemctl (enable|disable)[^#]*tor@default" "$1"' _ "$HERE/$f"
done
# Tor Browser's AppArmor fix: taken out again on --remove, and the profile read
# again, so the loaded rules lose it now rather than at the next reboot
check "tor-browser.sh reloads Tor's AppArmor profile after taking its lines out" \
    bash -c 'sed -n "/^unfix_apparmor_dns() {/,/^}/p" "$1" | grep -q "apparmor_parser -r \"\$TOR_PROFILE\""' _ "$HERE/extras/tor-browser.sh"
# Tor Browser 16 keeps torrc-defaults (the bridges' ClientTransportPlugin lines),
# geoip and geoip6 in TorBrowser/Tor, where the package's profile doesn't let Tor
# read them: the fix adds reading those three, once, and --remove takes it out
A=$T/aa
mkdir -p "$A/bin"
printf '#!/bin/sh\n[ "$1" = apparmor_parser ] && { echo "$*" >>"%s/parsed"; exit 0; }\nexec "$@"\n' "$A" >"$A/bin/sudo"
chmod +x "$A/bin/sudo"
: >"$A/profile"
mkdir "$A/apparmorfs"   # (AppArmor's folder, which a container may not have)
printf '%s\n' '# by hand' 'owner @{torbrowser_home_dir}/TorBrowser/Tor/geoip r,' >"$A/local"
aa() { PATH="$A/bin:$PATH" bash -c 'note() { :; }
    eval "$(sed -n "/^TOR_PROFILE=/,/geoip6 r,.)$/p; /^fix_apparmor_dns() {/,/^}/p; /^unfix_apparmor_dns() {/,/^}/p" "$1" |
        sed "s|/sys/kernel/security/apparmor|$2/apparmorfs|")"
    TOR_PROFILE=$2/profile TOR_LOCAL=$2/local; '"$1" _ "$HERE/extras/tor-browser.sh" "$A"; }
aa fix_apparmor_dns
aa fix_apparmor_dns
check "Tor Browser 16: Tor may read its torrc-defaults, geoip and geoip6 in TorBrowser/Tor" bash -c '
    for f in torrc-defaults geoip geoip6; do
        [ "$(grep -cx "owner @{torbrowser_home_dir}/TorBrowser/Tor/$f r," "$1")" = 1 ] || exit 1
    done' _ "$A/local"
check "...read only, and nothing else of TorBrowser/Tor (the bridge programs were allowed already)" \
    test "$(grep -c "TorBrowser/Tor/" "$A/local")" = 3
check "...the profile read again so it applies now" grep -q "apparmor_parser -r $A/profile" "$A/parsed"
aa unfix_apparmor_dns
check "...and --remove takes it out" not grep -q "TorBrowser/Tor/torrc-defaults" "$A/local"
check "OnionShare masks the tor service only when nobody needs it" \
    bash -c 'grep -B8 "systemctl mask tor.service" "$1" | grep -q "system_tor_wanted"' _ "$HERE/extras/onionshare.sh"

[ "$fails" -eq 0 ]
