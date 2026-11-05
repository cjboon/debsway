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

T=$(mktemp -d) || { echo "  FAIL  couldn't make a temp folder (is /tmp full?)"; exit 1; }
trap 'rm -rf "$T"' EXIT
fails=0
check() { # DESCRIPTION CONDITION-COMMAND...
    local what=$1
    shift
    if "$@" >/dev/null 2>&1; then printf '  ok    %s\n' "$what"; else printf '  FAIL  %s\n' "$what"; fails=$((fails + 1)); fi
}
not() { ! "$@"; }

# A copy of Wren Linux whose lib.sh keeps the test's PATH (lib.sh sets its own),
# so the pretend programs are the ones found
R=$T/r
mkdir -p "$R" "$T/bin" "$T/home"
# extras/ is a real folder of links: through a linked folder, extras/../lib.sh
# would be the real lib.sh, with the real PATH and the real sudo
for f in "$HERE"/*; do
    case ${f##*/} in lib.sh | extras) ;; *) ln -s "$f" "$R/${f##*/}" ;; esac
done
mkdir -p "$R/extras"
for f in "$HERE"/extras/*; do
    if [ -d "$f" ]; then
        mkdir -p "$R/extras/${f##*/}"
        for g in "$f"/*; do ln -s "$g" "$R/extras/${f##*/}/${g##*/}"; done
    else
        ln -s "$f" "$R/extras/${f##*/}"
    fi
done
sed 's|^export PATH=.*|export PATH="$MANUAL_TEST_PATH"|' "$HERE/lib.sh" >"$R/lib.sh"
grep -q MANUAL_TEST_PATH "$R/lib.sh" || { echo "  FAIL  lib.sh's PATH line wasn't found"; exit 1; }
for p in sudo apt-get apt-mark systemctl nft gsettings wget; do
    printf '#!/bin/sh\necho "%s $*" >>"%s/calls"\n' "$p" "$T" >"$T/bin/$p"
done
chmod +x "$T/bin/"*
export MANUAL_TEST_PATH="$T/bin:$PATH" WREN_SUDO=$T/bin/sudo
# Stop here unless the scripts would really get the pretend sudo
for l in extras/../lib.sh extras/firefox-profiles/../../lib.sh; do
    [ "$(bash -c '. "$1/$2"; command -v sudo' _ "$R" "$l")" = "$T/bin/sudo" ] ||
        { echo "  FAIL  the scripts would run the real sudo ($l); stopping"; exit 1; }
done

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
    WREN_DIR=$T/p PKGS=(a b c) ONE=1
    # print_manual finds the page from $0, the script's name
    BASH_ARGV0=$T/p/extras/demo.sh
    # shellcheck disable=SC2119  # no page: the script's own, from $0
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
    # The script whose --manual prints this page, from the SYNOPSIS
    # (wrenctl manual NAME is extras/NAME.sh --manual)
    rel=$(sed -n -e '/^## SYNOPSIS/,/^## LIMITS/s|.*bash ~/wren/\([^ ]*\.sh\) --manual.*|\1|p' \
        -e '/^## SYNOPSIS/,/^## LIMITS/s|^wrenctl manual \([a-z0-9-]*\) .*|extras/\1.sh|p' "$doc" | head -1)
    script=$HERE/$rel
    pages=$((pages + 1))
    order=$(grep -nx '## SYNOPSIS\|## LIMITS\|## MANUAL INSTALL' "$doc" | cut -d: -f2 | paste -sd,)
    check "$name: SYNOPSIS, LIMITS, MANUAL INSTALL, in that order" test "$order" = '## SYNOPSIS,## LIMITS,## MANUAL INSTALL'
    check "$name: the SYNOPSIS names the script's --manual" test -n "$rel"
    check "$name: one paragraph says what it is" test "$(sed -n '/^## SYNOPSIS/,/^## LIMITS/p' "$doc" | awk '/^```/ { f = !f; next } !f && NF' | grep -vc '^## ')" -gt 2
    if [ -z "$rel" ] || [ ! -f "$script" ]; then check "$name: its script (${rel:-?}) exists" false; continue; fi
    # A script that doesn't know --manual would go on to install: never run it
    if ! grep -q -- '= --manual \]' "$script"; then check "$name: its script takes --manual" false; continue; fi
    rm -rf "${T:?}/home" && mkdir "$T/home"
    : >"$T/calls"
    HOME=$T/home bash "$R/$rel" --manual >"$T/out" 2>&1
    rc=$?
    check "$name --manual: works" test "$rc" -eq 0
    check "$name --manual: prints the steps" grep -q 'sudo \|mkdir\|apt install' "$T/out"
    check "$name --manual: every @VAR@ is filled in" not grep -qE '@[A-Z][A-Z0-9_]*@' "$T/out"
    check "$name --manual: runs nothing (no sudo, apt, systemctl...)" test ! -s "$T/calls"
    check "$name --manual: writes nothing in your home" test -z "$(ls -A "$T/home")"
done
# Every extra has them, and takes --manual
missing=()
for script in "$HERE"/extras/*.sh "$HERE"/extras/firefox-profiles/new-profile.sh; do
    grep -q -- '= --manual \]' "$script" || missing+=("${script#"$HERE"/}")
done
check "every extra takes --manual${missing:+ (not: ${missing[*]})}" test ${#missing[@]} -eq 0
missing=()
for script in "$HERE"/extras/*.sh; do
    grep -qx '## MANUAL INSTALL' "$HERE/docs/extras/$(basename "$script" .sh).md" 2>/dev/null || missing+=("${script##*/}")
done
check "every extra has a page with MANUAL INSTALL${missing:+ (not: ${missing[*]})}" test ${#missing[@]} -eq 0

# ---- remote-access: the manual sshd settings are the script's, line for line ----
script=$(sed -n '/^sudo tee "\$SSHD_CONF" >\/dev\/null <<EOF$/,/^EOF$/p' "$HERE/extras/remote-access.sh" | sed '1d;$d' | grep -v '^#')
manual=$(HOME=$T/home bash "$R/extras/remote-access.sh" --manual | sed -n '/^sudo tee \/etc\/ssh\/sshd_config.d\/00-wren-remote-access.conf <<EOF$/,/^EOF$/p' | sed '1d;$d' | grep -v '^#')
check "remote-access: the manual sshd settings are the script's" bash -c '[ "$(wc -l <<<"$1")" -gt 10 ] && [ "$1" = "$2" ]' _ "$script" "$manual"

# ---- claude-vm: the manual sed fills the provisioning script as the script does ----
(
    . "$HERE/lib.sh"
    set +e
    line=$(bash "$R/extras/claude-vm.sh" --manual | grep "^sed -e 's|\[@\]ANTHROPIC_FPR@")
    mapfile -t exprs < <(grep -o "'s|[^']*'" <<<"$line" | tr -d "'")
    args=()
    for e in "${exprs[@]}"; do args+=(-e "$e"); done
    manual=$(sed "${args[@]}" "$HERE/data/claude-vm-provision.sh")
    script=$(sed -e "s|@ANTHROPIC_FPR@|$ANTHROPIC_FPR|g" -e "s|@ANTHROPIC_KEY_URL@|$ANTHROPIC_KEY_URL|g" \
        -e "s|@VM_USER@|agent|g" "$HERE/data/claude-vm-provision.sh")
    check "claude-vm: the manual steps fill in the provisioning script as the script does" \
        bash -c '[ ${#2} -gt 0 ] && [ "$1" = "$2" ] && ! grep -q "@[A-Z_]*@" <<<"$1"' _ "$manual" "$script"
    exit "$fails"
) || fails=$?

# A launcher's settings (write_launcher VAR=VALUE) are in its manual's one too
for s in "$HERE"/extras/*.sh; do
    line=$(grep -m1 '^write_launcher ' "$s") || continue
    read -r -a w <<<"$line"
    page=$HERE/docs/extras/$(basename "$s" .sh).md
    want="exec env APPDIR=\"\$dir\" ${w[*]:4}${w[4]:+ }\"\$dir/${w[3]}\" \"\$@\""
    check "$(basename "$s"): the manual's launcher runs ${w[3]} with the same settings" grep -qF "'$want'" "$page"
done

check "simplex: Java told that sway puts no frames around windows" grep -q '^write_launcher .*AppRun _JAVA_AWT_WM_NONREPARENTING=1$' "$HERE/extras/simplex-chat.sh"

[ "$fails" -eq 0 ]
