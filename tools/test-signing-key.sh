#!/bin/bash
# Checks the signing key (extras/signing-key.sh, bin/wren-key, the signer
# bin/wren-signer, bin/wren-key-gpg): the first run's questions answered
# from a file, a pretend sudo that runs the signer as you, from a copy whose
# folders are in a temp folder, a pretend USB stick, and a copy of Wren Linux with
# git. The backup holds the whole key and opens only with the passphrase; the
# signer keeps only the signing subkey and hands out no secret key; git signs
# and checks through it; pin, sign-repo and renew do what they say; and its
# user's firewall rule drops everything. Nothing on this computer changes.
# Run by test.sh, or:  bash tools/test-signing-key.sh
# shellcheck disable=SC2016  # the inner shells and pretend programs expand their own variables
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
command -v gpg >/dev/null || { echo "  ok    skipped: gpg isn't installed"; exit 0; }
T=$(mktemp -d)
# shellcheck disable=SC2317,SC2329  # runs from the EXIT trap
cleanup() {
    local h
    for h in "$T"/signer-home/gnupg "$T"/signer-home/first "$T"/r "$T"/v "$T"/v2 "$T"/home/.local/share/wren/signing-key/public; do
        gpgconf --homedir "$h" --kill all 2>/dev/null
    done
    rm -rf "$T"
}
trap cleanup EXIT
fails=0
check() { # DESCRIPTION CONDITION-COMMAND...
    local what=$1
    shift
    if "$@" >/dev/null 2>&1; then printf '  ok    %s\n' "$what"; else printf '  FAIL  %s\n' "$what"; fails=$((fails + 1)); fi
}
not() { ! "$@"; }

export HOME=$T/home
unset XDG_DATA_HOME
mkdir -p "$HOME/.local/bin" "$T/stick" "$T/signer-home" "$T/shm"
chmod 700 "$T/signer-home" "$T/shm"
# The signer as installed, but with its folders in $T and without the check
# that it runs as wren-signer (here it runs as you)
sed -e "s|^HOME_DIR=/var/lib/wren-signer$|HOME_DIR=$T/signer-home|" -e "s|^SHM=/dev/shm$|SHM=$T/shm|" \
    -e 's|^\[ "\$(id -un)" = wren-signer \] \|\||true \|\||' "$HERE/bin/wren-signer" >"$T/signer"
chmod +x "$T/signer"
grep -q "HOME_DIR=$T/signer-home" "$T/signer" || { echo "  FAIL  the signer's folder line wasn't found"; exit 1; }
# A pretend sudo: sudo -u USER CMD ARGS runs CMD ARGS, and writes down that it did
printf '#!/bin/bash\necho "sudo $*" >>"%s/sudolog"\n[ "$1" = -u ] && shift 2\nexec "$@"\n' "$T" >"$T/sudo"
chmod +x "$T/sudo"
export WREN_SUDO=$T/sudo WREN_SIGNER=$T/signer
cp "$HERE/bin/wren-key" "$HERE/bin/wren-key-gpg" "$HOME/.local/bin/"
K=$HOME/.local/bin/wren-key
# A copy of Wren Linux with git, to set up signing and pin the key in
mkdir "$T/d"
(cd "$HERE" && git ls-files -co --exclude-standard | tar -cf - -T -) | tar -C "$T/d" -xf -
git -C "$T/d" init -q -b main
git -C "$T/d" -c user.name=t -c user.email=t@t add -A
git -C "$T/d" -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -q -m first
export WREN_DIR=$T/d GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
PW='seven random words make a long passphrase'
key() { printf '%s\n' "$@" >"$T/answers"; WREN_KEY_ANSWERS=$T/answers bash "$K" 2>&1; }

# Mistakes first: nothing is made
out=$(key "" me@example.org "$T/stick" y "$PW" "not the same")
check "two passphrases that don't match: nothing is made" bash -c '[ ! -e "$1/wren-signing-key" ] && [ ! -s "$2/gnupg/fingerprint" ] && grep -q "didn.t match" <<<"$3"' _ "$T/stick" "$T/signer-home" "$out"
out=$(key "" me@example.org "$T/stick" y short short)
check "a short passphrase: nothing is made" bash -c '[ ! -s "$1/gnupg/fingerprint" ] && grep -q "at least 20" <<<"$2"' _ "$T/signer-home" "$out"
out=$(key "" me@example.org "$T/nowhere")
check "a backup folder that isn't there: nothing is made" bash -c '[ ! -s "$1/gnupg/fingerprint" ]' _ "$T/signer-home"

# The first run: explained, asked, made
out=$(key "" me@example.org "$T/stick" y "$PW" "$PW" y y)
check "the first run says how much the key matters and how to back it up" bash -c '
    for s in "Every Wren Linux computer will trust this key" "second stick" "revocation certificate" "on paper"; do grep -q "$s" <<<"$1" || exit 1; done' _ "$out"
check "...it warns that a backup folder on this computer isn't a stick" grep -q "is on this computer, not on a stick" <<<"$out"
check "...it suggests a passphrase of random words" bash -c 'command -v diceware >/dev/null || exit 0; grep -q "A suggestion, made just now" <<<"$1"' _ "$out"
F=$(cat "$HOME/.local/share/wren/signing-key/fingerprint" 2>/dev/null)
check "a key is made" bash -c '[[ $1 =~ ^[0-9A-F]{40}$ ]] && grep -q "The key: $1" <<<"$2"' _ "$F" "$out"
B=$T/stick/wren-signing-key
check "the stick gets the backup, the revocation certificate and the public key, yours alone" bash -c '
    for f in backup revocation public; do [ "$(stat -c %a "$1/wren-signing-key-$f.asc")" = 600 ] || exit 1; done' _ "$B"
check "...nothing else (no tar left)" test "$(find "$B" -mindepth 1 | wc -l)" = 3
mkdir -m 700 "$T/r"
check "the backup doesn't open with another passphrase" not gpg --homedir "$T/r" --batch --pinentry-mode loopback --passphrase "wrong one" --decrypt "$B/wren-signing-key-backup.asc"
gpg --homedir "$T/r" --batch --pinentry-mode loopback --passphrase "$PW" --decrypt "$B/wren-signing-key-backup.asc" 2>/dev/null |
    gpg --homedir "$T/r" --batch --import 2>/dev/null
check "...with yours it is the whole key: the primary key's secret part and the signing subkey" \
    bash -c '[ "$(gpg --homedir "$1" --with-colons -K "$2" | grep -E "^(sec|ssb)" | cut -d: -f1,15 | paste -sd" ")" = "sec:+ ssb:+" ]' _ "$T/r" "$F"
check "the signer keeps only the signing subkey: the primary key's secret part isn't on this computer" \
    bash -c '[ "$(gpg --homedir "$1/gnupg" --with-colons -K "$2" | grep -E "^(sec|ssb)" | cut -d: -f1,15 | paste -sd" ")" = "sec:# ssb:+" ]' _ "$T/signer-home" "$F"
check "...and no copy of it is left in memory or on disk" bash -c '[ -z "$(ls -A "$1")" ] && ! grep -rqs "BEGIN PGP PRIVATE" "$2"' _ "$T/shm" "$T/signer-home"
check "the revocation certificate is the key's" bash -c 'grep -q "revocation certificate" "$1" && grep -q "$2" "$1"' _ "$B/wren-signing-key-revocation.asc" "$F"
check "it went through sudo, as wren-signer, to the signer only" bash -c '! grep -v "^sudo -u wren-signer $1 " "$2"' _ "$T/signer" "$T/sudolog"
out=$(key)
check "run again, it shows the key instead of making another" bash -c 'grep -q "Key: $1" <<<"$2"' _ "$F" "$out"
check "the signer won't make a second key" bash -c 'printf "%s\n" "$3" | "$1" new "x y" a@b.org 2>&1 | grep -q "there is a key already"' _ "$T/signer" "" "$PW"

# What the signer refuses
check "the signer hands out no secret key" bash -c '! "$1" export-secret-keys && ! "$1" export-secret-subkeys' _ "$T/signer"
check "...and takes no options of yours (no other key, file or homedir)" bash -c '! echo x | "$1" sign --local-user ABC && ! echo x | "$1" sign --homedir /tmp' _ "$T/signer"

# git signs every commit, through the signer, and checks with the public key
check "git-setup: git signs every commit and tag with the key, through wren-key-gpg" bash -c '
    [ "$(git -C "$1" config user.signingkey)" = "$2" ] && [ "$(git -C "$1" config commit.gpgsign)" = true ] &&
    [ "$(git -C "$1" config tag.gpgSign)" = true ] && [ "$(git -C "$1" config gpg.program)" = "$3/.local/bin/wren-key-gpg" ]' _ "$T/d" "$F" "$HOME"
echo change >>"$T/d/README.md"
git -C "$T/d" commit -q -am "a signed commit" 2>"$T/commit.err"
check "a commit is signed" bash -c 'git -C "$1" cat-file commit HEAD | grep -q "BEGIN PGP SIGNATURE"' _ "$T/d"
check "...and git checks it, with the public key alone" git -C "$T/d" verify-commit HEAD
check "wren-key-gpg does only that: no other gpg command" bash -c '! "$1/.local/bin/wren-key-gpg" --export-secret-keys && ! "$1/.local/bin/wren-key-gpg" --list-keys' _ "$HOME"
check "...and signs with Wren Linux's key only" bash -c '! echo x | "$1/.local/bin/wren-key-gpg" --status-fd=2 -bsau ABCDEF0123456789' _ "$HOME"

# pin: pins.sh and the key file, as update.sh and the repository part check them
check "pin: pins.sh pins the key" grep -qx "WREN_SIGNING_FPR=$F" "$T/d/pins.sh"
check "...data/wren-signing-key.asc is exactly that key (as test.sh and update.sh check it)" \
    bash -c '. "$1/lib.sh"; key_ok "$1/data/wren-signing-key.asc" "$2"' _ "$T/d" "$F"
check "...and what it says to run commits the new key file too (commit -a leaves a new file out: a pin with no key refuses every update)" bash -c '
    grep -q "add pins.sh data/wren-signing-key.asc" "$1" && ! grep -q "commit -am" "$1"' _ "$HERE/bin/wren-key"
mkdir -p "$T/u"
check "update.sh's check takes the signed commit" bash -c '
    cd "$1" && . ./lib.sh && . lib/update.sh && . lib/appimage.sh && WREN_SIGNING_FPR=$2 && update_signed HEAD' _ "$T/d" "$F"

# sign-repo: a repository signed by the signer, which the public key verifies
mkdir -p "$T/p/DEBIAN"
chmod 0755 "$T/p" "$T/p/DEBIAN"
printf 'Package: wren-linux\nVersion: 1.0\nArchitecture: all\nMaintainer: t <t@t>\nDescription: test\n' >"$T/p/DEBIAN/control"
chmod 0644 "$T/p/DEBIAN/control"
dpkg-deb --root-owner-group --build "$T/p" "$T/wren-linux_1.0_all.deb" >/dev/null 2>&1
if command -v apt-ftparchive >/dev/null; then
    bash "$K" sign-repo "$T/repo" "$T/wren-linux_1.0_all.deb" >"$T/repo.out" 2>&1
    mkdir -m 700 "$T/v"
    gpg --homedir "$T/v" --batch --import "$B/wren-signing-key-public.asc" 2>/dev/null
    check "sign-repo: InRelease and Release.gpg are signed by the key" bash -c '
        gpg --homedir "$1" --batch --status-fd 1 --verify "$2/dists/trixie/InRelease" 2>/dev/null | grep -q "VALIDSIG .* $3$" &&
        gpg --homedir "$1" --batch --status-fd 1 --verify "$2/dists/trixie/Release.gpg" "$2/dists/trixie/Release" 2>/dev/null | grep -q "VALIDSIG .* $3$"' _ "$T/v" "$T/repo" "$F"
fi

# renew: two more years from the backup; the old backup kept
printf '%s\n' "$PW" >"$T/answers"
out=$(WREN_KEY_ANSWERS=$T/answers bash "$K" renew "$B/wren-signing-key-backup.asc" 2>&1)
check "renew: a renewed backup, and the old one kept" bash -c '[ -s "$1/wren-signing-key-backup.asc" ] && [ -s "$1/wren-signing-key-backup.asc.old" ] && grep -q "Renewed" <<<"$2"' _ "$B" "$out"
check "...the signer still has only the subkey" \
    bash -c '[ "$(gpg --homedir "$1/gnupg" --with-colons -K "$2" | grep -E "^(sec|ssb)" | cut -d: -f1,15 | paste -sd" ")" = "sec:# ssb:+" ]' _ "$T/signer-home" "$F"
printf '%s\n' "not the passphrase at all" >"$T/answers"
out=$(WREN_KEY_ANSWERS=$T/answers bash "$K" renew "$B/wren-signing-key-backup.asc" 2>&1)
check "...a wrong passphrase renews nothing" bash -c 'grep -q "doesn.t open with that passphrase" <<<"$1" && [ ! -e "$2/wren-signing-key-backup.asc.old.old" ]' _ "$out" "$B"

# restore: a new computer (the signer with no key, nothing remembered) gets the
# key from the backup; the key pins.sh pins, or one you name
gpgconf --homedir "$T/signer-home/gnupg" --kill all 2>/dev/null
mv "$T/signer-home/gnupg" "$T/signer-home/first"
mv "$HOME/.local/share/wren/signing-key" "$T/first-state"
restore() { printf '%s\n' "$1" n >"$T/answers"; shift; WREN_KEY_ANSWERS=$T/answers bash "$K" restore "$@" 2>&1; }
out=$(restore "not the passphrase at all" "$B/wren-signing-key-backup.asc")
check "restore: a wrong passphrase restores nothing" bash -c 'grep -q "doesn.t open with that passphrase" <<<"$1" && [ ! -s "$2/gnupg/fingerprint" ]' _ "$out" "$T/signer-home"
out=$(restore "$PW" "$B/wren-signing-key-backup.asc" 0123456789ABCDEF0123456789ABCDEF01234567)
check "...a backup that isn't the key asked for: nothing" bash -c 'grep -q "isn.t the key" <<<"$1" && [ ! -s "$2/gnupg/fingerprint" ]' _ "$out" "$T/signer-home"
out=$(restore "$PW" "$B/wren-signing-key-public.asc")
check "...the public key alone isn't a backup: nothing" bash -c '[ ! -s "$1/gnupg/fingerprint" ]' _ "$T/signer-home"
check "...nor are options or a short fingerprint taken" bash -c '! "$1" restore 2>/dev/null </dev/null && ! "$1" restore ABC </dev/null 2>/dev/null && ! "$1" restore --homedir /tmp </dev/null 2>/dev/null' _ "$T/signer"
out=$(restore "$PW" "$B/wren-signing-key-backup.asc")
check "...the right passphrase: the key pins.sh pins is back" bash -c '[ "$(cat "$1/gnupg/fingerprint")" = "$2" ] && grep -q "Restored" <<<"$3" && [ "$(cat "$4/.local/share/wren/signing-key/fingerprint")" = "$2" ]' _ "$T/signer-home" "$F" "$out" "$HOME"
check "...the signer has only the signing subkey, and nothing is left in memory" \
    bash -c '[ "$(gpg --homedir "$1/gnupg" --with-colons -K "$2" | grep -E "^(sec|ssb)" | cut -d: -f1,15 | paste -sd" ")" = "sec:# ssb:+" ] && [ -z "$(ls -A "$3")" ]' _ "$T/signer-home" "$F" "$T/shm"
check "...and it signs: a signature the public key checks" bash -c '
    mkdir -p -m 700 "$2/v2" && gpg --homedir "$2/v2" --batch --import "$4" 2>/dev/null &&
    echo hello >"$2/msg" && "$1" detach-sign <"$2/msg" >"$2/msg.asc" && gpg --homedir "$2/v2" --batch --status-fd 1 --verify "$2/msg.asc" "$2/msg" 2>/dev/null | grep -q "VALIDSIG .* $3$"' _ "$T/signer" "$T" "$F" "$B/wren-signing-key-public.asc"
out=$(restore "$PW" "$B/wren-signing-key-backup.asc")
check "...run again: refused, the key is there already" grep -q "has a key already" <<<"$out"
check "the first run says how to restore instead of making a second key" grep -q "wren-key restore BACKUP" "$HERE/bin/wren-key"

# The extra: the firewall before the user, the rule asks for your password
X=$HERE/extras/signing-key.sh
check "the extra's sudo rule is the signer only, and asks for your password (no NOPASSWD)" bash -c '
    r=$(grep "ALL=(%s)" "$1"); [ -n "$r" ] && [[ $r != *NOPASSWD* ]] && [[ $r == *"ALL=(%s) %s"* ]] && grep -q "visudo -cf" "$1"' _ "$X"
check "...the firewall rule is in place before the user exists, and a rule that doesn't load stops it" bash -c '
    f=$(grep -n "data/signer-firewall.nft" "$1" | head -1 | cut -d: -f1); u=$(grep -n "useradd --system" "$1" | cut -d: -f1)
    [ "$f" -lt "$u" ] && grep -q "it must never be on the network" "$1"' _ "$X"
FW=$HERE/data/signer-firewall.nft
check "the firewall rule drops everything wren-signer sends" bash -c '[ "$(grep -v "^ *#" "$1" | grep -c "skuid")" = 1 ] && grep -qx "        meta skuid \"wren-signer\" drop" "$1"' _ "$FW"
NS_PATH=/usr/sbin:/sbin:/usr/bin:/bin
if PATH=$NS_PATH command -v nft >/dev/null && unshare -rn true 2>/dev/null; then
    sed -e 's/meta skuid "wren-signer" drop/meta skuid 0 counter drop/' "$FW" >"$T/fw.nft"
    out=$(PATH=$NS_PATH unshare -rn bash -c '
        ip link set lo up && ip link add d0 type dummy && ip link set d0 up && ip addr add 192.168.5.2/24 dev d0 || exit 9
        nft -f "$1" || exit 8
        for t in 127.0.0.1/53 192.168.5.1/80 192.168.5.2/22; do timeout 0.2 bash -c "exec 3<>/dev/tcp/$t" 2>/dev/null && echo "connected $t"; done
        nft list ruleset | grep -o "counter packets [0-9]*"' _ "$T/fw.nft")
    check "...with Debian's nft, in a network namespace: nothing gets out (DNS, the network, this computer)" \
        bash -c '! grep -q connected <<<"$1" && grep -qE "counter packets [1-9]" <<<"$1"' _ "$out"
fi

[ "$fails" -eq 0 ]
