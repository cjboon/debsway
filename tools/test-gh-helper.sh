#!/bin/bash
# Checks gh-helper.sh with a pretend gh: the token is read hidden and reaches gh
# only in its environment or on its input, never on a command line; nothing is
# saved unless you say so; the rules on main are added only when missing, as
# meant (only admins update it; nobody force-pushes or deletes it, no bypass),
# and checked against what GitHub says it applies; a wrong token or a refusal
# changes nothing. Changes nothing outside a temp folder. Run by test.sh, or:
#   bash tools/test-gh-helper.sh
# shellcheck disable=SC2016  # the inner shells expand their own variables
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
export HOME=$T/home
mkdir -p "$HOME" "$T/bin"
TOK=github_pat_11AAAAAAA0abcdefghijkl_mnopqrstuvwxyz0123456789
# The pretend gh: every call's arguments and GH_TOKEN go in calls, its input in
# input.N; $T/state says what it answers (logged-in, have-rules, applied, refuse)
cat >"$T/bin/gh" <<'GH'
#!/bin/bash
S=${GH_STATE:?}
n=$(($(wc -l <"$S/calls" 2>/dev/null || echo 0) + 1))
printf '%s | token=%s\n' "$*" "${GH_TOKEN:-}" >>"$S/calls"
case "$*" in
    "auth status --hostname github.com") [ -e "$S/logged-in" ] ;;
    "auth login --hostname github.com --with-token") cat >"$S/input.$n"; : >"$S/logged-in" ;;
    "auth logout --hostname github.com") rm -f "$S/logged-in" ;;
    "api repos/"*"/rulesets --jq .[].name") cat "$S/have-rules" 2>/dev/null; true ;;
    "api -X POST repos/"*"/rulesets --input -") cat >"$S/input.$n"; [ ! -e "$S/refuse" ] ;;
    "api repos/"*"/rules/branches/main --jq .[].type") cat "$S/applied" 2>/dev/null; true ;;
    *) exit 3 ;;
esac
GH
chmod +x "$T/bin/gh"
# A copy of Wren Linux whose server is on GitHub
C=$T/c
mkdir -p "$C"
(cd "$HERE" && git ls-files -co --exclude-standard | tar -cf - -T -) | tar -C "$C" -xf -
git -C "$C" init -q -b main && git -C "$C" remote add origin https://github.com/someone/wren-linux.git
# run ANSWERS-FILE ARGS...: gh-helper.sh, its questions answered from that file
run() {
    local a=$1
    shift
    rm -f "$T/s/calls" "$T/s"/input.*
    GH_STATE=$T/s WREN_GH=$T/bin/gh WREN_TEST_ANSWERS=$a bash "$C/gh-helper.sh" "$@" 2>&1
}
fresh() { rm -rf "$T/s"; mkdir -p "$T/s"; }
printf '%s\n' "$TOK" >"$T/tok"
printf '%s\n' update non_fast_forward deletion >"$T/all-applied"

# rulesets, not logged in: a token for this run alone
fresh
cp "$T/all-applied" "$T/s/applied"
out=$(run "$T/tok" rulesets)
check "rulesets: this copy's GitHub repository" grep -q 'api repos/someone/wren-linux/rulesets' "$T/s/calls"
check "...the token reaches gh in its environment" grep -q "token=$TOK" "$T/s/calls"
check "...never on a command line" not grep -q "$TOK |" "$T/s/calls"
check "...nor saved (no gh login)" not grep -q 'auth login' "$T/s/calls"
check "...both rules added" test "$(grep -c 'api -X POST' "$T/s/calls")" = 2
j1=$(grep -l '"update"' "$T/s"/input.*)
j2=$(grep -l non_fast_forward "$T/s"/input.*)
check "...only the owner (the admin role) updates main" bash -c '
    python3 -I -c "import json,sys; r=json.load(open(sys.argv[1]))
assert r[\"conditions\"][\"ref_name\"][\"include\"]==[\"refs/heads/main\"] and r[\"enforcement\"]==\"active\"
assert r[\"rules\"]==[{\"type\":\"update\"}]
assert r[\"bypass_actors\"]==[{\"actor_id\":5,\"actor_type\":\"RepositoryRole\",\"bypass_mode\":\"always\"}]" "$1"' _ "$j1"
check "...nobody force-pushes or deletes it, no bypass for anyone" bash -c '
    python3 -I -c "import json,sys; r=json.load(open(sys.argv[1]))
assert r[\"conditions\"][\"ref_name\"][\"include\"]==[\"refs/heads/main\"] and r[\"enforcement\"]==\"active\"
assert sorted(x[\"type\"] for x in r[\"rules\"])==[\"deletion\",\"non_fast_forward\"]
assert \"bypass_actors\" not in r" "$1"' _ "$j2"
check "...and it says what GitHub applies, and to delete a token made for this" bash -c '
    grep -q "only you update it" <<<"$1" && grep -q "Delete it" <<<"$1"' _ "$out"

# Already there: nothing added; another repository named
fresh
cp "$T/all-applied" "$T/s/applied"
printf '%s\n' "main: only the owner updates it" "main: no force-push, no delete" >"$T/s/have-rules"
: >"$T/s/logged-in"
run /dev/null rulesets other/repo >/dev/null
check "rules already there: nothing added (and a saved login used, no token asked)" bash -c '
    ! grep -q "api -X POST" "$1" && grep -q "api repos/other/repo/rulesets" "$1" && ! grep -q "token=github_pat" "$1"' _ "$T/s/calls"

# What GitHub applies lacks a rule: said, not claimed
fresh
printf '%s\n' non_fast_forward deletion >"$T/s/applied"
out=$(run "$T/tok" rulesets)
check "GitHub doesn't apply a rule to main: it says so, and fails" bash -c '
    grep -q "doesn.t apply \"update\"" <<<"$1" && ! grep -q "only you update it" <<<"$1"' _ "$out"
# GitHub refuses the first rule: the second isn't tried
fresh
: >"$T/s/refuse"
out=$(run "$T/tok" rulesets)
check "GitHub refuses a rule: it stops there" bash -c '
    grep -q "GitHub refused" <<<"$1" && [ "$(grep -c "api -X POST" "$2")" = 1 ]' _ "$out" "$T/s/calls"
# Not a token: gh never called with it
fresh
printf '%s\n' 'github_pat_short;rm' >"$T/bad"
out=$(run "$T/bad" rulesets)
check "something that isn't a token: nothing asked of GitHub" bash -c '
    grep -q "isn.t a GitHub token" <<<"$1" && ! grep -q "rulesets" "$2"' _ "$out" "$T/s/calls"
check "OWNER/REPO with anything else in it: refused" bash -c '
    grep -q "isn.t OWNER/REPO" <<<"$1"' _ "$(run /dev/null rulesets '../x/y')"

# Setting up: nothing saved unless you say so; saved, the token goes on gh's input
fresh
run /dev/null >/dev/null
check "setup, no answer: nothing saved" not grep -q 'auth login' "$T/s/calls"
fresh
printf '%s\n' y "$TOK" >"$T/save"
run "$T/save" >/dev/null
check "setup, yes: gh logs in with the token on its input" bash -c '
    grep -q "^auth login --hostname github.com --with-token" "$1" && grep -qx "$2" "$3"/input.*' _ "$T/s/calls" "$TOK" "$T/s"
check "...not on its command line" not grep -q "$TOK |" "$T/s/calls"
run /dev/null --logout >/dev/null
check "--logout: gh forgets it" bash -c 'grep -q "auth logout" "$1" && [ ! -e "$2/logged-in" ]' _ "$T/s/calls" "$T/s"
check "wrenctl gh runs it" bash -c 'grep -q "gh-helper.sh" "$1"' _ "$HERE/bin/wrenctl"

[ "$fails" -eq 0 ]
