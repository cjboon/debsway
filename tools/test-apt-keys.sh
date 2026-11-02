#!/bin/bash
# Checks lib/apt-keys.sh: status.sh and update.sh see an apt repository's
# signing key that has expired or will soon (also when only its signing
# subkey does, as the Tor Project's will), and update.sh fetches it again,
# installing the new one only if it is the pinned key and signs for longer.
# Throwaway keys (some made as if in 2020, so they have expired), a pretend
# sudo (install writes into the temp folder) and a pretend key server: nothing
# on this computer changes. Run by test.sh, or:  bash tools/test-apt-keys.sh
# shellcheck disable=SC2016  # the inner shells expand their own variables
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
command -v gpg >/dev/null || { echo "  ok    skipped: gpg isn't installed"; exit 0; }

T=$(mktemp -d)
trap 'gpgconf --homedir "$T/gh" --kill all 2>/dev/null; rm -rf "$T"' EXIT
fails=0
check() { # DESCRIPTION CONDITION-COMMAND...
    local what=$1
    shift
    if "$@" >/dev/null 2>&1; then printf '  ok    %s\n' "$what"; else printf '  FAIL  %s\n' "$what"; fails=$((fails + 1)); fi
}
not() { ! "$@"; }

mkdir -m 700 "$T/gh"
G=(gpg --homedir "$T/gh" --batch --quiet --passphrase '' --pinentry-mode loopback)
gg() { "${G[@]}" "$@" 2>/dev/null; }
fpr() { gpg --show-keys --with-colons "$1" | awk -F: '/^fpr/ { print $10; exit }'; }
export_key() { gg --armor --export "$1" >"$2"; }
# soon: signs, expires in 20 days; then the same key renewed for two years
gg --quick-gen-key "soon <soon@test>" ed25519 sign 20d
export_key soon@test "$T/soon.asc"
SOON=$(fpr "$T/soon.asc")
gg --quick-set-expire "$SOON" 2y
export_key soon@test "$T/soon-renewed.asc"
# old: made in 2020 to last a year, so expired; then renewed
gg --faked-system-time 20200101T000000 --quick-gen-key "old <old@test>" ed25519 sign 1y
export_key old@test "$T/old.asc"
OLD=$(fpr "$T/old.asc")
gg --quick-set-expire "$OLD" 2y
export_key old@test "$T/old-renewed.asc"
# sub: like the Tor Project's, a key that never expires but only certifies,
# signing with a subkey that expires in 20 days
gg --quick-gen-key "sub <sub@test>" ed25519 cert never
SUB=$(gpg --homedir "$T/gh" --with-colons --list-keys sub@test 2>/dev/null | awk -F: '/^fpr/ { print $10; exit }')
gg --quick-add-key "$SUB" ed25519 sign 20d
export_key sub@test "$T/sub.asc"
gg --quick-gen-key "other <other@test>" ed25519 sign never
export_key other@test "$T/other.asc"
gg --quick-gen-key "fine <fine@test>" ed25519 sign never
export_key fine@test "$T/fine.asc"
FINE=$(fpr "$T/fine.asc")

mkdir -p "$T/bin"
cat >"$T/bin/sudo" <<EOF
#!/bin/bash
echo "sudo \$*" >>"$T/calls"
case "\$1" in
    install) args=("\$@"); dest=\${args[-1]}; mkdir -p "$T/root\${dest%/*}"; args[-1]="$T/root\$dest"; "\${args[@]}" ;;
esac
EOF
printf '#!/bin/sh\ncp "%s/served.asc" "$2"\n' "$T" >"$T/bin/wget"
chmod +x "$T/bin/"*
F=/usr/share/keyrings/signal-desktop-keyring.asc
# keys INSTALLED SERVED PINNED-FPR CMD: Signal's key file holds INSTALLED, the
# server has SERVED; runs CMD (apt_keys_status or apt_keys_refresh)
keys() {
    rm -rf "$T/root"; mkdir -p "$T/root${F%/*}"; : >"$T/calls"
    cp "$T/$1.asc" "$T/root$F"
    cp "$T/$2.asc" "$T/served.asc"
    PATH="$T/bin:$PATH" DEBSWAY_KEYS_ROOT=$T/root bash -c '
        . "$1/lib.sh"; . "$1/lib/apt-keys.sh"
        export PATH="$2:$PATH" SIGNAL_FPR=$3 SIGNAL_KEY_URL=https://keys.example/signal.asc
        "$4"' _ "$HERE" "$T/bin" "$3" "$4" >"$T/out" 2>&1
}

keys fine fine "$FINE" apt_keys_status
check "a key that is fine: status says so" grep -qx '  \[x\] Signal' "$T/out"
keys fine other "$FINE" apt_keys_refresh
check "...and update.sh fetches nothing, says nothing" bash -c '[ ! -s "$1" ] && [ ! -s "$2" ]' _ "$T/calls" "$T/out"

keys soon soon "$SOON" apt_keys_status
check "a key expiring in 20 days: status warns, with the way out" grep -q '\[!\] Signal: stops signing in 1[89] days. bash update.sh' "$T/out"
keys soon soon-renewed "$SOON" apt_keys_refresh
check "...update.sh installs the renewed key" cmp "$T/soon-renewed.asc" "$T/root$F"
keys soon soon "$SOON" apt_keys_refresh
check "...not yet renewed by its maker: kept, and said" bash -c '! grep -q "sudo install" "$1" && grep -q "renewed its key yet" "$2"' _ "$T/calls" "$T/out"
keys soon other "$SOON" apt_keys_refresh
check "...a key that isn't the pinned one is refused, the old one kept" bash -c '! grep -q "sudo install" "$1" && grep -q "isn.t exactly the pinned key" "$2" && cmp "$3" "$4"' _ "$T/calls" "$T/out" "$T/soon.asc" "$T/root$F"

keys old old "$OLD" apt_keys_status
check "an expired key: status says apt takes no updates" grep -q '\[ \] Signal: EXPIRED' "$T/out"
keys old old-renewed "$OLD" apt_keys_refresh
check "...update.sh installs the renewed key" cmp "$T/old-renewed.asc" "$T/root$F"
keys old old "$OLD" apt_keys_refresh
check "...still expired at its maker: update.sh says apt can't check its updates (and goes on)" grep -q "apt can't check Signal's updates" "$T/out"

keys sub sub "$SUB" apt_keys_status
check "a key whose signing subkey expires soon (as the Tor Project's): warned too" grep -q '\[!\] Signal: stops signing' "$T/out"

# the files in APT_KEYS are where the scripts put the keys
check "APT_KEYS names each key file where its script puts it" bash -c '
    grep -q "|/etc/apt/keyrings/claude-code.asc|ANTHROPIC_FPR|" "$1/lib/apt-keys.sh" && grep -qx "CLAUDE_KEY=/etc/apt/keyrings/claude-code.asc" "$1/lib/claude-repo.sh" &&
    grep -q "|/usr/share/keyrings/signal-desktop-keyring.asc|SIGNAL_FPR|" "$1/lib/apt-keys.sh" && grep -qx "KEY=/usr/share/keyrings/signal-desktop-keyring.asc" "$1/extras/signal.sh" &&
    grep -q "|/usr/share/keyrings/mullvad-keyring.asc|MULLVAD_FPR|" "$1/lib/apt-keys.sh" && grep -qx "MULLVAD_KEY=/usr/share/keyrings/mullvad-keyring.asc" "$1/lib/mullvad-repo.sh" &&
    grep -q "|/usr/share/keyrings/debsway-torproject.asc|TORPROJECT_FPR|" "$1/lib/apt-keys.sh" && grep -qx "TORPROJECT_KEY=/usr/share/keyrings/debsway-torproject.asc" "$1/lib/tor.sh"' _ "$HERE"
check "every install_apt_key in debsway has its key in APT_KEYS" bash -c '
    n=$(grep -rh "^ *install_apt_key \"\\$" "$1/lib" "$1/extras" "$1/parts" | wc -l)
    [ "$n" = "$(grep -c "^    \"[^\"]*|/[^|]*|[A-Z]*_FPR|[A-Z_]*_KEY_URL\"$" "$1/lib/apt-keys.sh")" ]' _ "$HERE"
check "update.sh checks the keys every time" grep -q '^    apt_keys_refresh' "$HERE/update.sh"

[ "$fails" -eq 0 ]
