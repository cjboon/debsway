#!/bin/bash
# Checks the ready-made Firefox profiles (data/firefox-profiles.list) and how
# new-profile.sh uses them: every line is a usable profile (name, address,
# settings), each uBlock exception is the profile's own site, and
# "new-profile.sh NAME" makes it with those settings and exceptions. In a copy
# of this checkout whose make_profile and ublock-allow only write down what
# they were asked; changes nothing outside a temp folder.
# Run by test.sh, or:  bash tools/test-firefox-catalog.sh
# shellcheck disable=SC2016  # the inner bash expands its own variables
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
L=$HERE/data/firefox-profiles.list

# ---- every line a usable profile ----
bad=$(cd "$HERE" && bash -c '. ./lib.sh; . lib/firefox-sandbox.sh; . lib/firefox-profiles.sh; set +e
    url_ok() { [[ $1 =~ ^https://[a-z0-9.-]+(/[A-Za-z0-9._~/?#=%+,@-]*)?$ ]]; }
    while read -r name url fast toolbars sound cookies allow hash what; do
        [[ $name == "#"* || -z $name ]] && continue
        fx_profile_name_ok "$name" || echo "$name: not a usable name"
        url_ok "$url" || echo "$name: address $url"
        [[ $fast =~ ^(yes|no)$ && $toolbars =~ ^(hidden|shown)$ && $sound =~ ^(yes|no)$ && $cookies =~ ^(keep|delete)$ ]] ||
            echo "$name: settings $fast $toolbars $sound $cookies"
        [ "$hash" = "#" ] && [ -n "$what" ] || echo "$name: no description"
        host=${url#https://}; host=${host%%/*}
        if [ "$allow" != - ]; then
            for s in ${allow//,/ }; do
                # its own site only: the address'"'"'s host or a domain above it
                [[ $host == "$s" || $host == *".$s" ]] || echo "$name: allows $s, not its own site ($host)"
            done
        fi
    done <"$1"' _ "$L" 2>&1)
check "every ready-made profile has a usable name, an https address, its settings and what it is${bad:+ ($(paste -sd';' <<<"$bad"))}" test -z "$bad"
check "each name once" test -z "$(awk '!/^#/ && NF { print $1 }' "$L" | sort | uniq -d)"
check "none takes the name of a program (claudefx, not claude: that is Claude Code)" \
    bash -c 'for n in $(awk '"'"'!/^#/ && NF { print $1 }'"'"' "$1"); do for d in /usr/local/bin /usr/bin /bin /usr/sbin /sbin; do [ ! -e "$d/$n" ] || exit 1; done; [ "$n" != claude ] || exit 1; done' _ "$L"
check "the ones you asked for are there" bash -c 'for n in duckai pornhub xvideos chess github claudefx youtube tutamail protonmail gmail yahoomail; do grep -q "^$n " "$1" || exit 1; done' _ "$L"
check "sites whose page loads their own code from a second domain get their uBlock exception (GitHub, YouTube, Gmail, chess.com)" \
    bash -c 'grep -q "^github .* github.com #" "$1" && grep -q "^youtube .* youtube.com #" "$1" && grep -q "^gmail .* mail.google.com #" "$1" && grep -q "^chess .* chess.com #" "$1"' _ "$L"
check "...and those that don't, none (Tuta, Proton, Lichess, duck.ai)" \
    bash -c 'for n in tutamail protonmail lichess duckai; do grep -q "^$n [^#]* - #" "$1" || exit 1; done' _ "$L"
check "the adult, chess and video ones forget everything when they close" \
    bash -c 'for n in pornhub xvideos chess youtube; do grep -q "^$n [^#]* delete [^#]*#" "$1" || exit 1; done' _ "$L"

# ---- new-profile.sh with them ----
mkdir "$T/W"
(cd "$HERE" && git ls-files -co --exclude-standard | tar -cf - -T -) | tar -C "$T/W" -xf -
# make_profile only writes down what it was asked
cat >>"$T/W/lib/firefox-profiles.sh" <<EOF
make_profile() { echo "make_profile \$*" >>"$T/calls"; }
EOF
printf '#!/bin/sh\necho "ublock-allow $*" >>"%s/calls"\n' "$T" >"$T/ublock-allow"
chmod +x "$T/ublock-allow"
np() { : >"$T/calls"; printf '%s\n' "${ANS[@]}" >"$T/answers"; HOME=$T WREN_UBLOCK_ALLOW=$T/ublock-allow WREN_TEST_ANSWERS=$T/answers bash "$T/W/extras/firefox-profiles/new-profile.sh" "$@" 2>&1; }
ANS=()
out=$(np github)
check "new-profile.sh github: made with its ready-made settings" grep -qx 'make_profile github https://github.com no shown no keep' "$T/calls"
check "...and its site allowed in uBlock, after the profile is made" \
    bash -c '[ "$(cat "$1")" = "$(printf "make_profile github https://github.com no shown no keep\nublock-allow github.com")" ]' _ "$T/calls"
out=$(np pornhub)
check "new-profile.sh pornhub: sound, cookies deleted when it closes" grep -qx 'make_profile pornhub https://www.pornhub.com no hidden yes delete' "$T/calls"
out=$(np tutamail)
check "a ready-made one with nothing to allow: ublock-allow isn't run" bash -c '! grep -q ublock-allow "$1" && grep -q "^make_profile tutamail " "$1"' _ "$T/calls"
out=$(np nosuchsite) && rc=0 || rc=$?
check "a name that isn't ready-made, without an address: refused, saying how" \
    bash -c '[ "$1" -ne 0 ] && grep -q "no ready-made profile called \"nosuchsite\"" <<<"$2" && grep -q "new-profile.sh NAME URL" <<<"$2" && [ ! -s "$3" ]' _ "$rc" "$out" "$T/calls"
out=$(np bank https://mybank.example --delete-cookies)
check "your own, by name and address: as before, nothing allowed" \
    bash -c 'grep -qx "make_profile bank https://mybank.example no hidden yes delete" "$1" && ! grep -q ublock-allow "$1"' _ "$T/calls"
ANS=(chess)
out=$(np)
check "asked, a ready-made name typed: its settings, no more questions" \
    bash -c 'grep -qx "make_profile chess https://www.chess.com yes hidden yes delete" "$1" && ! grep -q "address (e.g." <<<"$2"' _ "$T/calls" "$out"
out=$(np --list)
check "--list: each ready-made one, by kind, with what it is" \
    bash -c 'grep -q "^  github  *GitHub$" <<<"$1" && grep -q "^Mail$" <<<"$1" && [ "$(grep -c "^  [a-z]" <<<"$1")" = "$(awk "!/^#/ && NF" "$2" | wc -l)" ]' _ "$out" "$L"

# ---- the check boxes (--choose) ----
# A pretend checklist: writes down what it was shown, and "ticks" $T/tick
cat >>"$T/W/lib/checklist.sh" <<EOF
checklist() {
    printf '%s|%s|%s\\n' "\${ITEMS[@]}" >"$T/shown"
    [ -e "$T/tick" ] || return 1
    mapfile -t chosen <"$T/tick"
}
EOF
cat >>"$T/W/lib/firefox-profiles.sh" <<EOF
remove_profile() { echo "remove_profile \$*" >>"$T/calls"; }
EOF
mkdir -p "$T/profiles"
: >"$T/profiles/github.conf"
: >"$T/profiles/bank.conf"
# (with a terminal of its own: the boxes are only drawn on one)
choose() {
    : >"$T/calls"
    script -qec "env HOME=$T WREN_FX_PROFILE_DIR=$T/profiles WREN_UBLOCK_ALLOW=$T/ublock-allow bash $T/W/extras/firefox-profiles/new-profile.sh --choose" /dev/null 2>&1
}
printf '%s\n' github chess >"$T/tick"
out=$(choose)
check "--choose: the ready-made ones as boxes, by kind; the ones you have ticked, marked *" \
    bash -c 'grep -q "^~[0-9]*|== Mail ==|OFF$" "$1" && grep -q "^github|\* GitHub|ON$" "$1" && grep -q "^chess|  Chess.com, forgotten when it closes|OFF$" "$1"' _ "$T/shown"
check "...your own profiles aren't among them (bank)" not grep -q '^bank|' "$T/shown"
check "...a newly ticked one is made, with its settings and uBlock exception; one kept is left as it is" \
    bash -c '[ "$(cat "$1")" = "$(printf "make_profile chess https://www.chess.com yes hidden yes delete\nublock-allow chess.com")" ]' _ "$T/calls"
check "...and it says how to come back to it" grep -q 'firefox --choose-profiles' <<<"$out"
# (as the real make_profile would have left it)
: >"$T/profiles/chess.conf"
printf '%s\n' chess >"$T/tick"
out=$(choose)
check "...an unticked one you have is removed (remove_profile asks about its logins), yours untouched" \
    bash -c '[ "$(cat "$1")" = "remove_profile github" ]' _ "$T/calls"
rm -f "$T/tick"
out=$(choose)
check "...Cancel changes nothing" bash -c '[ ! -s "$1" ] && grep -q "Nothing changed" <<<"$2"' _ "$T/calls" "$out"
X=$HERE/extras/firefox-sandbox.sh
check "the sandboxed Firefox's install asks once (default no), then says the command" \
    bash -c 'grep -qF "Make some ready-made profiles now (a Firefox of its own for GitHub, mail, chess...)?\" n" "$1" && grep -qF "if [ ! -e \"\$ASKED_PROFILES\" ]" "$1" && grep -qF "note \"Ready-made profiles, to make or remove later: firefox --choose-profiles\"" "$1"' _ "$X"
check "firefox --choose-profiles opens them" grep -q 'new_profile --choose' "$HERE/bin/firefox"

[ "$fails" -eq 0 ]
