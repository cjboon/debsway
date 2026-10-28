#!/bin/bash
# Checks sshd_problems (lib/net.sh), which compares what `sshd -T` says sshd
# will do with what extras/remote-access.sh needs, using sample output.
# Changes nothing. Run by test.sh, or:  bash tools/test-sshd-check.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
set +e +o pipefail

fails=0
check() { # DESCRIPTION CONDITION-COMMAND...
    local what=$1
    shift
    if "$@" >/dev/null 2>&1; then printf '  ok    %s\n' "$what"; else printf '  FAIL  %s\n' "$what"; fails=$((fails + 1)); fi
}
good=$'port 22\nlistenaddress 127.0.0.1:22\npermitrootlogin no\npasswordauthentication no\nkbdinteractiveauthentication no\nallowusers alice\n'
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

[ "$fails" -eq 0 ]
