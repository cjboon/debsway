#!/bin/bash
# Checks extras/security-key.sh with a pretend root folder, sudo, pamu2fcfg and
# pamtester: the sandboxed Firefox's rule only when you say so; for sudo, the
# keys go into a list only root changes (other users' kept), the setting is
# tried in a PAM service of its own first and sudo stays as it was if that
# fails, the line goes right after the password, the change undoes itself
# unless a new sudo works (and the undo does put it back), and --sudo-off and
# --remove leave sudo exactly as before. Nothing outside a temp folder changes.
# Run by test.sh, or:  bash tools/test-security-key.sh
# shellcheck disable=SC2016  # the inner shells and pretend programs expand their own variables
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
fails=0
check() { # DESCRIPTION CONDITION-COMMAND...
    local what=$1
    shift
    if "$@" >/dev/null 2>&1; then printf '  ok    %s\n' "$what"; else printf '  FAIL  %s\n' "$what"; fails=$((fails + 1)); fi
}
not() { ! "$@"; }
ME=$(id -un)

# ---- the pretend programs ----
mkdir -p "$T/bin" "$T/home"
cat >"$T/bin/sudo" <<EOF
#!/bin/bash
echo "sudo \$*" >>"$T/calls"
case \$1 in
    -v | -k) exit 0 ;;
    systemd-run | systemctl | udevadm | apt-get | apt-mark | dpkg) exit 0 ;;
    install)
        shift; dir=false; args=()
        while [ \$# -gt 0 ]; do case \$1 in -o | -g | -m) shift 2 ;; -d) dir=true; shift ;; -D) shift ;; *) args+=("\$1"); shift ;; esac; done
        if \$dir; then mkdir -p "\${args[@]}"; else mkdir -p "\$(dirname "\${args[-1]}")" && cp "\${args[0]}" "\${args[-1]}"; fi
        exit ;;
    # (the sudo that confirms the change: its rm of the pending mark)
    rm) case "\$*" in *wren-u2f-pending*) [ ! -e "$T/sudo-fails" ] || exit 1 ;; esac ;;
esac
exec "\$@"
EOF
cat >"$T/bin/dpkg-query" <<'EOF'
#!/bin/sh
case "$*" in
    *Status*) echo 'install ok installed' ;;
    *Depends*) echo 'libfido2-1, fido2-tools, libpam-u2f, pamu2fcfg, pamtester, acl' ;;
esac
EOF
# pamu2fcfg: a touch of key one, or (-n) of key two; pamtester: the key accepted unless told
cat >"$T/bin/pamu2fcfg" <<EOF
#!/bin/sh
echo "pamu2fcfg \$*" >>"$T/calls"
case " \$* " in *" -n "*) printf ':KEYTWO,es256,+presence' ;; *) printf '%s:KEYONE,es256,+presence' "$ME" ;; esac
EOF
cat >"$T/bin/pamtester" <<EOF
#!/bin/sh
echo "pamtester \$*" >>"$T/calls"
cp "$T/root/etc/pam.d/wren-u2f-test" "$T/tried" 2>/dev/null
[ ! -e "$T/key-refused" ]
EOF
printf "#!/bin/sh\nexit 0\n" >"$T/bin/logger"
chmod +x "$T/bin/"*

# A copy of Wren Linux whose lib.sh keeps the test's PATH
R=$T/r
mkdir -p "$R/extras" "$R/lib"
sed 's|^export PATH=.*|export PATH="$SK_TEST_PATH"|' "$HERE/lib.sh" >"$R/lib.sh"
grep -q SK_TEST_PATH "$R/lib.sh" || { echo "  FAIL  lib.sh's PATH line wasn't found"; exit 1; }
for f in pins.sh packages.sh data bin docs; do ln -s "$HERE/$f" "$R/$f"; done
for f in "$HERE"/lib/*; do ln -s "$f" "$R/lib/${f##*/}"; done
cp "$HERE/extras/security-key.sh" "$R/extras/"
export SK_TEST_PATH="$T/bin:$PATH"

SUDO_PAM_TEXT='#%PAM-1.0

# Set up user limits from /etc/security/limits.conf.
session    required   pam_limits.so

@include common-auth
@include common-account
@include common-session-noninteractive'
fresh() { # a pretend root: Debian's /etc/pam.d/sudo, another user's key already listed
    rm -rf "$T/root" "$T/calls" "$T/sudo-fails" "$T/key-refused" "$T/tried"
    mkdir -p "$T/root/etc/pam.d" "$T/root/etc/wren" "$T/root/run"
    printf '%s\n' "$SUDO_PAM_TEXT" >"$T/root/etc/pam.d/sudo"
    echo 'alice:ALICEKEY,es256,+presence' >"$T/root/etc/wren/u2f_keys"
    : >"$T/calls"
}
sk() { # ANSWER... -- ARGS...: the extra, answering its questions in turn
    local a=()
    while [ "$1" != -- ]; do a+=("$1"); shift; done
    shift
    printf '%s\n' "${a[@]}" >"$T/answers"
    HOME=$T/home WREN_SK_ROOT=$T/root WREN_TEST_ANSWERS=$T/answers bash "$R/extras/security-key.sh" "$@" 2>&1
}
P=$T/root/etc/pam.d/sudo
K=$T/root/etc/wren/u2f_keys
U2F="auth required pam_u2f.so authfile=$K origin=pam://wren appid=pam://wren cue nouserok"

# ---- a whole setup: the Firefox rule, two keys, sudo ----
fresh
out=$(sk y y y n -- )
rc=$?
check "the setup goes through${out:+: $(tail -1 <<<"$out")}" test "$rc" -eq 0
check "the sandboxed Firefox's rule, as it is in data/, when you say yes" cmp "$HERE/data/security-key-firefox.rules" "$T/root/etc/udev/rules.d/72-wren-security-key-firefox.rules"
check "...udev reads it, and looks at the keys plugged in again" bash -c 'grep -q "sudo udevadm control --reload-rules" "$1" && grep -q "sudo udevadm trigger --subsystem-match=hidraw --action=change" "$1"' _ "$T/calls"
check "...it gives the key to the group wren-fx alone, and only to a device udev marks as a security key" bash -c '
    r=$(grep -v "^#" "$1"); grep -q "ENV{ID_SECURITY_TOKEN}==\"1\"" <<<"$r" && grep -q "setfacl -m g:wren-fx:rw" <<<"$r" && ! grep -qE "MODE=|GROUP=|0666" <<<"$r"' _ "$HERE/data/security-key-firefox.rules"
if command -v udevadm >/dev/null && udevadm verify --help >/dev/null 2>&1; then
    cp "$HERE/data/security-key-firefox.rules" "$T/72-x.rules"
    check "...and udev takes it (udevadm verify)" udevadm verify "$T/72-x.rules"
fi
check "both keys are registered, in one line of yours, next to the other user's" bash -c '
    grep -qx "alice:ALICEKEY,es256,+presence" "$1" && grep -qx "$2:KEYONE,es256,+presence:KEYTWO,es256,+presence" "$1" && [ "$(wc -l <"$1")" = 2 ]' _ "$K" "$ME"
check "...the list written as root's (install -o root -g root -m 0644)" grep -q "sudo install -o root -g root -m 0644 .* $K" "$T/calls"
check "it was tried in a PAM service of its own first, without nouserok, and that service is gone" bash -c '
    grep -q "pamtester wren-u2f-test $3 authenticate" "$1" && grep -qx "auth required pam_u2f.so authfile=$4 origin=pam://wren appid=pam://wren cue" "$2" && [ ! -e "$5" ]' _ "$T/calls" "$T/tried" "$ME" "$K" "$T/root/etc/pam.d/wren-u2f-test"
check "sudo: the key's line right after the password (@include common-auth), with its mark" bash -c '
    [ "$(grep -A2 -x "@include common-auth" "$1" | sed -n 3p)" = "$2" ] && grep -qx "# Wren Linux extras/security-key.sh: sudo takes your password and a touch of your key" "$1"' _ "$P" "$U2F"
check "...the rest of the file as it was" bash -c '[ "$(grep -v "Wren Linux extras/security-key.sh" "$1" | grep -vxF "$2")" = "$3" ]' _ "$P" "$U2F" "$SUDO_PAM_TEXT"
check "...it would have undone itself in 3 minutes (a copy of the old sudo, and a timer)" grep -q "sudo systemd-run --quiet --unit=wren-u2f-rollback --on-active=3min" "$T/calls"
check "...a new sudo worked: confirmed, the timer stopped, the copy gone" bash -c '
    [ ! -e "$1/run/wren-u2f-pending" ] && [ ! -e "$1/etc/pam.d/sudo.wren-old" ] && grep -q "sudo systemctl stop wren-u2f-rollback.timer" "$2" && grep -q "Confirmed" <<<"$3"' _ "$T/root" "$T/calls" "$out"
out=$(sk -- --sudo)
check "--sudo again: it says the key is in use already, and changes nothing" bash -c 'grep -q "takes your key already" <<<"$1" && [ "$(grep -c pam_u2f "$2")" = 1 ]' _ "$out" "$P"
out=$(sk -- --sudo-off)
check "--sudo-off: sudo exactly as before, your keys out of the list, the other user's kept" bash -c '
    [ "$(cat "$1")" = "$2" ] && [ "$(cat "$3")" = "alice:ALICEKEY,es256,+presence" ]' _ "$P" "$SUDO_PAM_TEXT" "$K"

# ---- the key refused when tried: sudo untouched ----
fresh
out=$(sk n y n -- )
rc=$?
check "no to the sandboxed Firefox: no rule" test ! -e "$T/root/etc/udev/rules.d/72-wren-security-key-firefox.rules"
fresh
: >"$T/key-refused"
out=$(sk n y n -- )
rc=$?
check "the key refused in the PAM service of its own: sudo stays exactly as it was, nothing is armed" bash -c '
    [ "$4" -ne 0 ] && [ "$(cat "$1")" = "$2" ] && ! grep -q systemd-run "$3" && [ ! -e "$5/etc/pam.d/wren-u2f-test" ]' _ "$P" "$SUDO_PAM_TEXT" "$T/calls" "$rc" "$T/root"

# ---- the new sudo failing: the timer puts the old one back ----
fresh
: >"$T/sudo-fails"
out=$(sk n y n -- )
rc=$?
check "a new sudo failing: it says so, and the old sudo waits to come back" bash -c '
    [ "$3" -ne 0 ] && grep -q "takes your password alone again, by itself" <<<"$1" && [ -e "$2/run/wren-u2f-pending" ] && [ -e "$2/etc/pam.d/sudo.wren-old" ]' _ "$out" "$T/root" "$rc"
rollback=$(sed -n 's/.*--on-active=3min \/bin\/sh -c //p' "$T/calls")
rm -f "$T/sudo-fails"
PATH="$T/bin:$PATH" sh -c "$rollback"
check "...and the timer's command does put it back" bash -c '[ "$(cat "$1")" = "$2" ] && [ ! -e "$3/run/wren-u2f-pending" ]' _ "$P" "$SUDO_PAM_TEXT" "$T/root"

# ---- what it refuses, and saying no ----
fresh
out=$(sk n n -- )
check "no to sudo: sudo untouched, and it says how to later" bash -c '[ "$(cat "$1")" = "$2" ] && grep -q "wrenctl install security-key --sudo" <<<"$3"' _ "$P" "$SUDO_PAM_TEXT" "$out"
fresh
printf '#%%PAM-1.0\nauth required pam_unix.so\n' >"$P"
out=$(sk n y n -- )
check "a sudo PAM file without @include common-auth: left as it was" bash -c 'grep -q "has no @include common-auth" <<<"$1" && ! grep -q pam_u2f "$2" && [ ! -e "$3/run/wren-u2f-pending" ]' _ "$out" "$P" "$T/root"

# ---- --remove ----
fresh
sk y y n -- >/dev/null
out=$(sk -- --remove)
check "--remove: sudo as before, the rule gone, the packages purged" bash -c '
    [ "$(cat "$1")" = "$2" ] && [ ! -e "$3/etc/udev/rules.d/72-wren-security-key-firefox.rules" ] && grep -q "apt-get purge" "$4"' _ "$P" "$SUDO_PAM_TEXT" "$T/root" "$T/calls"
check "in real use the list is /etc/wren/u2f_keys, root's" grep -q '^KEYS=$ROOT/etc/wren/u2f_keys$' "$HERE/extras/security-key.sh"
check "vps-client.sh makes an SSH key that needs the security key" grep -q 'ed25519-sk' "$HERE/tools/vps-client.sh"
check "setup-vps.sh takes such a key" grep -q 'sk-ssh-ed25519@openssh' "$HERE/tools/setup-vps.sh"

[ "$fails" -eq 0 ]
