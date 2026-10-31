#!/bin/bash
# Checks sshd_problems (lib/net.sh), which compares what `sshd -T` says sshd
# will do with what extras/remote-access.sh needs, using sample output.
# Changes nothing. Run by test.sh, or:  bash tools/test-sshd-check.sh
# shellcheck disable=SC2016  # sed and awk programs, and inner shells, expand their own
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
set +e +o pipefail

fails=0
check() { # DESCRIPTION CONDITION-COMMAND...
    local what=$1
    shift
    if "$@" >/dev/null 2>&1; then printf '  ok    %s\n' "$what"; else printf '  FAIL  %s\n' "$what"; fails=$((fails + 1)); fi
}
good=$'port 22\nlistenaddress 127.0.0.1:22\npermitrootlogin no\npasswordauthentication no\nkbdinteractiveauthentication no\nallowusers alice\n'
good+=$'allowtcpforwarding no\nallowstreamlocalforwarding no\ngatewayports no\nallowagentforwarding no\nx11forwarding no\npermittunnel no\npermituserenvironment no\nmaxauthtries 3\n'
problems() { printf '%s' "$1" | sshd_problems alice; }
has() { problems "$1" | grep -q "$2"; }

check "the settings debsway writes pass" test -z "$(problems "$good")"
check "password login still on is caught" has "${good/passwordauthentication no/passwordauthentication yes}" 'PasswordAuthentication is yes'
check "keyboard-interactive login still on is caught" has "${good/kbdinteractiveauthentication no/kbdinteractiveauthentication yes}" 'KbdInteractiveAuthentication is yes'
check "root login allowed is caught" has "${good/permitrootlogin no/permitrootlogin prohibit-password}" 'PermitRootLogin is prohibit-password'
check "listening on every address is caught" has "${good/listenaddress 127.0.0.1:22/listenaddress 0.0.0.0:22}" 'ListenAddress 0.0.0.0:22'
check "an extra listen address is caught" has "${good}listenaddress [::]:22"$'\n' 'ListenAddress \[::\]:22'
check "no AllowUsers is caught" has "${good/allowusers alice/}" 'AllowUsers is not set'
check "another allowed user is caught" has "${good}allowusers mallory"$'\n' 'AllowUsers includes mallory'
check "nothing at all is caught" has "" 'AllowUsers is not set'
# Forwarding, tunnels, the agent and X11 off; few tries
for s in allowtcpforwarding:AllowTcpForwarding:yes allowstreamlocalforwarding:AllowStreamLocalForwarding:all \
    gatewayports:GatewayPorts:clientspecified allowagentforwarding:AllowAgentForwarding:yes x11forwarding:X11Forwarding:yes \
    permittunnel:PermitTunnel:point-to-point permituserenvironment:PermitUserEnvironment:yes; do
    IFS=: read -r key name val <<<"$s"
    check "$name $val (another file overriding debsway's) is caught" has "${good/$key no/$key $val}" "$name is $val"
    check "...and $name missing is caught" has "${good/$key no$'\n'/}" "$name is not set"
done
check "MaxAuthTries 6 (Debian's default) is caught" has "${good/maxauthtries 3/maxauthtries 6}" 'MaxAuthTries is 6'
check "MaxAuthTries 2 is fine" test -z "$(problems "${good/maxauthtries 3/maxauthtries 2}")"
# What extras/remote-access.sh writes is what this check wants
conf=$(sed -n '/^sudo tee "$SSHD_CONF" >\/dev\/null <<EOF$/,/^EOF$/p' "$DEBSWAY_DIR/extras/remote-access.sh" | grep -vE '^(sudo|EOF|#)' |
    sed -e 's/\$USER/alice/' -e 's/^ListenAddress 127.0.0.1$/ListenAddress 127.0.0.1:22/' | awk '{ print tolower($1), $2 }')
check "the settings remote-access.sh writes pass the check" test -z "$(problems "port 22"$'\n'"$conf"$'\n')"
check "...and include every new one" bash -c 'for k in allowtcpforwarding allowstreamlocalforwarding gatewayports allowagentforwarding x11forwarding permittunnel permituserenvironment maxauthtries logingracetime; do grep -q "^$k " <<<"$1" || exit 1; done' _ "$conf"

[ "$fails" -eq 0 ]
