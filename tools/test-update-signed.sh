#!/bin/bash
# Checks that update.sh brings in only what Wren Linux's own key signed, once
# pins.sh names that key (WREN_SIGNING_FPR, the key in
# data/wren-signing-key.asc): a pretend server and "your copy", made here
# from the real files, with throwaway keys (good, another, expired, revoked).
# Changes nothing outside a temp folder. Run by test.sh, or:
#   bash tools/test-update-signed.sh
# shellcheck disable=SC2016  # the inner shells and pretend programs expand their own variables
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

T=$(mktemp -d)
G=(gpg --homedir "$T/gh" --batch --quiet --pinentry-mode loopback --passphrase '')
trap 'gpgconf --homedir "$T/gh" --kill all 2>/dev/null; rm -rf "$T"' EXIT
fails=0
check() { # DESCRIPTION CONDITION-COMMAND...
    local what=$1
    shift
    if "$@" >/dev/null 2>&1; then printf '  ok    %s\n' "$what"; else printf '  FAIL  %s\n' "$what"; fails=$((fails + 1)); fi
}
not() { ! "$@"; }
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
export HOME="$T/home" XDG_STATE_HOME="$T/state" WREN_KEYS_ROOT="$T/no-keys"
mkdir -p "$HOME"
# nothing is run again (nothing is "set up" here), and no sudo is asked for
export WREN_UPDATE_ASSUME_INSTALLED='' WREN_SUDO=true

# Throwaway keys: the pinned one, another, one that expired (made "in 2020",
# for a day), and one revoked after use
mkdir -m 700 "$T/gh"
[ -z "${GPG_AGENT_PROGRAM:-}" ] || echo "agent-program $GPG_AGENT_PROGRAM" >"$T/gh/gpg.conf"
fpr_of() { "${G[@]}" --list-keys --with-colons "$1" 2>/dev/null | awk -F: '$1 == "fpr" { print $10; exit }'; }
# the pinned key as docs/maintaining.md says to make it: a primary key that
# only certifies, and a subkey that signs
"${G[@]}" --quick-generate-key pinned@test ed25519 cert 1y
"${G[@]}" --quick-add-key "$(fpr_of pinned@test)" ed25519 sign 1y
"${G[@]}" --quick-generate-key other@test ed25519 sign 1y
"${G[@]}" --faked-system-time 20200101T000000 --quick-generate-key old@test ed25519 sign 1d 2>/dev/null
"${G[@]}" --quick-generate-key revoked@test ed25519 sign 1y
FPIN=$(fpr_of pinned@test) FOTHER=$(fpr_of other@test) FOLD=$(fpr_of old@test) FREV=$(fpr_of revoked@test)
if [ -z "$FPIN" ] || [ -z "$FOTHER" ] || [ -z "$FOLD" ] || [ -z "$FREV" ]; then
    echo "  ok    skipped: gpg couldn't make test keys here (is gpg-agent installed?)"
    exit 0
fi

# git signs through this: gpg with the test keys, at a faked time for the old key
cat >"$T/gpg-sign" <<EOF
#!/bin/sh
exec gpg --homedir "$T/gh" --batch --quiet --pinentry-mode loopback --passphrase '' \${FAKETIME:+--faked-system-time \$FAKETIME} "\$@"
EOF
chmod +x "$T/gpg-sign"

# The server's working copy W, the server O, your copy L. Your copy pins the
# key and has its public half; a second key in that file must not count.
mkdir "$T/W"
(cd "$HERE" && git ls-files -co --exclude-standard | tar -cf - -T -) | tar -C "$T/W" -xf -
{ "${G[@]}" --export --armor "$FPIN"; "${G[@]}" --export --armor "$FOTHER"; } >"$T/W/data/wren-signing-key.asc"
sed -i "s/^WREN_SIGNING_FPR=.*/WREN_SIGNING_FPR=$FPIN/" "$T/W/pins.sh"
grep -qx "WREN_SIGNING_FPR=$FPIN" "$T/W/pins.sh" || { echo "  FAIL  pins.sh has no WREN_SIGNING_FPR line"; exit 1; }
git -C "$T/W" init -q -b main && git -C "$T/W" add -A && git -C "$T/W" commit -q -m first
git clone -q --bare "$T/W" "$T/O.git"
git clone -q "$T/O.git" "$T/L"
git -C "$T/W" remote add origin "$T/O.git"
# your own git setting for signatures must not change the check
git -C "$T/L" config gpg.program /bin/true

# push_commit KEY|none [FAKETIME]: a new commit on the server, signed by KEY
push_commit() {
    echo "# change $RANDOM" >>"$T/W/README.md"
    git -C "$T/W" add -A
    if [ "$1" = none ]; then
        git -C "$T/W" commit -q -m change
    else
        FAKETIME=${2:-} git -C "$T/W" -c gpg.program="$T/gpg-sign" -c user.signingkey="$1" commit -q -S -m change
    fi
    git -C "$T/W" push -q origin main
}
head_of() { git -C "$T/L" rev-parse HEAD; }
server() { git -C "$T/O.git" rev-parse main; }
upd() { printf 'y\ny\n' >"$T/answers"; WREN_TEST_ANSWERS="$T/answers" bash "$T/L/update.sh" 2>&1; }

push_commit "$FPIN"
out=$(upd)
check "signed by the pinned key's signing subkey: brought in" test "$(head_of)" = "$(server)"
check "...and said" grep -q "is signed by Wren Linux's key" <<<"$out"

push_commit none
before=$(head_of)
out=$(upd)
check "not signed: nothing brought in" test "$(head_of)" = "$before"
check "...and said why" grep -q "isn't signed by Wren Linux's key" <<<"$out"

push_commit "$FOTHER"
out=$(upd)
check "signed by another key, even one in the key file: nothing brought in" test "$(head_of)" = "$before"
check "...because of the signature" grep -q "isn't signed by Wren Linux's key" <<<"$out"

# the old key's signature, made while it was valid ("2020"); it has expired since
push_commit "$FOLD" 20200101T120000
out=$(upd)
check "signed by an expired key: nothing brought in" test "$(head_of)" = "$before"
check "...because of the signature" grep -q "isn't signed by Wren Linux's key" <<<"$out"

push_commit "$FREV"
printf 'y\n0\n\ny\n' | gpg --homedir "$T/gh" --quiet --no-tty --pinentry-mode loopback --passphrase '' \
    --command-fd 0 --output "$T/rev.cert" --gen-revoke "$FREV" 2>/dev/null
"${G[@]}" --import "$T/rev.cert" 2>/dev/null
# your copy's key file: the pinned key and the revoked one, revocation included
{ "${G[@]}" --export --armor "$FPIN"; "${G[@]}" --export --armor "$FREV"; } >"$T/L/data/wren-signing-key.asc"
sed -i "s/^WREN_SIGNING_FPR=.*/WREN_SIGNING_FPR=$FREV/" "$T/L/pins.sh"
out=$(upd)
check "signed by a revoked key (pinned): nothing brought in" test "$(head_of)" = "$before"
check "...because of the signature" grep -q "isn't signed by Wren Linux's key" <<<"$out"
git -C "$T/L" checkout -q -- pins.sh data/wren-signing-key.asc

# a signed commit on top of unsigned ones: the newest one vouches for them all
push_commit none
push_commit "$FPIN"
out=$(upd)
check "unsigned commits under a signed one: brought in (the signature covers them)" test "$(head_of)" = "$(server)"

# a key file that isn't the pinned key: nothing brought in
push_commit "$FPIN"
before=$(head_of)
"${G[@]}" --export --armor "$FOTHER" >"$T/L/data/wren-signing-key.asc"
out=$(upd)
check "the key file without the pinned key: nothing brought in" test "$(head_of)" = "$before"
check "...because of the signature" grep -q "isn't signed by Wren Linux's key" <<<"$out"
git -C "$T/L" checkout -q -- data/wren-signing-key.asc

# no key pinned yet (your copy's pins.sh, not committed): brought in as before,
# saying it wasn't checked
sed -i 's/^WREN_SIGNING_FPR=.*/WREN_SIGNING_FPR=/' "$T/L/pins.sh"
push_commit none
out=$(upd)
check "no key pinned: brought in" test "$(head_of)" = "$(server)"
check "...saying it wasn't signature-checked" grep -q "is not checked: no signing key is pinned" <<<"$out"

[ "$fails" -eq 0 ]
