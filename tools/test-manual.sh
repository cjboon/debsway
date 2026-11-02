#!/bin/bash
# Checks the extras' pages (docs/extras/NAME.md) and --manual: a page has a
# SYNOPSIS (naming --manual), a LIMITS and a MANUAL INSTALL section, in that
# order; "bash extras/NAME.sh --manual" prints that section with every @VAR@
# filled in, and changes nothing: it runs with a pretend sudo, apt-get and
# systemctl that only log, in a temp home. Also print_manual (lib/core.sh) on
# its own, and that secure-dns's manual steps write the same Unbound settings
# as the script. Run by test.sh, or:  bash tools/test-manual.sh
# shellcheck disable=SC2016  # the pretend programs expand their own variables
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

# A copy of debsway whose lib.sh keeps the test's PATH (lib.sh sets its own),
# so the pretend programs are the ones found
R=$T/r
mkdir -p "$R" "$T/bin" "$T/home"
# extras/ is a real folder of links: through a linked folder, extras/../lib.sh
# would be the real lib.sh, with the real PATH and the real sudo
for f in "$HERE"/*; do
    case ${f##*/} in lib.sh | extras) ;; *) ln -s "$f" "$R/${f##*/}" ;; esac
done
mkdir -p "$R/extras"
for f in "$HERE"/extras/*; do ln -s "$f" "$R/extras/${f##*/}"; done
sed 's|^export PATH=.*|export PATH="$MANUAL_TEST_PATH"|' "$HERE/lib.sh" >"$R/lib.sh"
grep -q MANUAL_TEST_PATH "$R/lib.sh" || { echo "  FAIL  lib.sh's PATH line wasn't found"; exit 1; }
for p in sudo apt-get apt-mark systemctl nft gsettings wget; do
    printf '#!/bin/sh\necho "%s $*" >>"%s/calls"\n' "$p" "$T" >"$T/bin/$p"
done
chmod +x "$T/bin/"*
export MANUAL_TEST_PATH="$T/bin:$PATH" DEBSWAY_SUDO=$T/bin/sudo
# Stop here unless the scripts would really get the pretend sudo
[ "$(bash -c '. "$1/extras/../lib.sh"; command -v sudo' _ "$R")" = "$T/bin/sudo" ] ||
    { echo "  FAIL  the scripts would run the real sudo; stopping"; exit 1; }

# ---- print_manual on its own ----
mkdir -p "$T/p/docs/extras" "$T/p/extras"
cat >"$T/p/docs/extras/demo.md" <<'EOF'
# demo
## SYNOPSIS
not this
## MANUAL INSTALL
```
sudo apt install @PKGS@
echo @ONE@ and @ONE@, @UNSET_THING@, user@example.org
```
Last line.
## AFTER
not this either
EOF
pm() { (
    . "$HERE/lib.sh"
    set +e
    DEBSWAY_DIR=$T/p PKGS=(a b c) ONE=1
    # print_manual finds the page from $0, the script's name
    BASH_ARGV0=$T/p/extras/demo.sh
    print_manual
); }
out=$(pm 2>&1)
check "only the MANUAL INSTALL section is printed" bash -c '! grep -q "not this" <<<"$1" && grep -q "Last line." <<<"$1"' _ "$out"
check "...without its code fences" not grep -q '```' <<<"$out"
check "an array gives its items" grep -qx 'sudo apt install a b c' <<<"$out"
check "a variable is filled in each time it appears" grep -q '^echo 1 and 1, ' <<<"$out"
check "an unknown @NAME@ is left as it is (so the test below catches it)" grep -q '@UNSET_THING@' <<<"$out"
check "an address with @ in it is left alone" grep -q 'user@example.org$' <<<"$out"

# ---- every page that has manual steps, and its --manual ----
pages=0
for doc in "$HERE"/docs/extras/*.md; do
    grep -qx '## MANUAL INSTALL' "$doc" || continue
    name=$(basename "$doc" .md)
    script=$HERE/extras/$name.sh
    pages=$((pages + 1))
    order=$(grep -nx '## SYNOPSIS\|## LIMITS\|## MANUAL INSTALL' "$doc" | cut -d: -f2 | paste -sd,)
    check "$name: SYNOPSIS, LIMITS, MANUAL INSTALL, in that order" test "$order" = '## SYNOPSIS,## LIMITS,## MANUAL INSTALL'
    check "$name: the SYNOPSIS names --manual" bash -c 'sed -n "/^## SYNOPSIS/,/^## LIMITS/p" "$1" | grep -q -- "$2 --manual"' _ "$doc" "extras/$name.sh"
    check "$name: one paragraph says what it is" test "$(sed -n '/^## SYNOPSIS/,/^## LIMITS/p' "$doc" | awk '/^```/ { f = !f; next } !f && NF' | grep -vc '^## ')" -gt 2
    if [ ! -f "$script" ]; then check "$name: extras/$name.sh exists" false; continue; fi
    check "$name: its script takes --manual" grep -q -- '--manual' "$script"
    : >"$T/calls"
    HOME=$T/home bash "$R/extras/$name.sh" --manual >"$T/out" 2>&1
    rc=$?
    check "$name --manual: works" test "$rc" -eq 0
    check "$name --manual: prints the steps" grep -q 'sudo \|mkdir\|apt install' "$T/out"
    check "$name --manual: every @VAR@ is filled in" not grep -qE '@[A-Z][A-Z0-9_]*@' "$T/out"
    check "$name --manual: runs nothing (no sudo, apt, systemctl...)" test ! -s "$T/calls"
    check "$name --manual: writes nothing in your home" test -z "$(ls -A "$T/home")"
done
check "at least the first three pages have manual steps (w3m, tutamail, secure-dns)" test "$pages" -ge 3

# ---- secure-dns: the manual Unbound settings are the script's ----
(
    . "$HERE/lib.sh"
    . "$HERE/lib/secure-dns.sh"
    set +e
    bash "$R/extras/secure-dns.sh" --manual >"$T/sd"
    block=$(sed -n '/^{$/,/^} | sudo tee/p' "$T/sd" | sed '$s/.*/}/')
    for name in "${DNS_PROVIDERS[@]}"; do
        NAME=$name DOT=$(dns_pin "$name")
        TLS=${DOT%% *} ADDRS=${DOT#* }
        manual=$(eval "$block" | grep -v '^#' | grep .)
        script=$(dns_unbound_conf "$name" | grep -v '^#' | grep .)
        check "secure-dns: the manual steps write the script's Unbound settings ($name)" test "$manual" = "$script"
        check "...and the provider line status.sh reads" test "$(eval "$block" | head -1)" = "# provider: $name"
    done
    exit "$fails"
) || fails=$?

[ "$fails" -eq 0 ]
