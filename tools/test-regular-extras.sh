#!/bin/bash
# Checks extras/claude-regular.sh, and what keeps it from getting in the way
# of the sandboxed Claude Code:
#  - lib/claude-settings.py adds Wren Linux's Claude Code settings next to yours
#    and takes out only what it added;
#  - lib/claude-repo.sh keeps Anthropic's repository while either extra uses it.
# The extras run with a pretend sudo (it only logs), a pretend dpkg-query (their
# packages "already installed") and a pretend repository, in a temp home, so
# nothing on this computer changes. Run by test.sh, or:
#   bash tools/test-regular-extras.sh
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
jq_has() { python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if eval(sys.argv[2]) else 1)' "$@"; }

# ---- lib/claude-settings.py ----
M=$HERE/lib/claude-settings.py
OURS=$HERE/data/claude-regular-settings.json
S=$T/s/settings.json ST=$T/s/state.json
python3 -I "$M" add "$S" "$OURS" "$ST"
check "settings: into an empty home, the sandbox is on" jq_has "$S" 'd["sandbox"]["enabled"] is True'
check "...with the deny rules" jq_has "$S" '"Read(~/.ssh/**)" in d["permissions"]["deny"] and "Bash(sudo *)" in d["permissions"]["deny"]'
check "...and only you may read the file" test "$(stat -c %a "$S")" = 600
check "...every folder and file closed to its commands is closed to its file tools too" python3 -I -c '
import json, sys
d = json.load(open(sys.argv[1]))
deny = d["permissions"]["deny"]
for p in d["sandbox"]["filesystem"]["denyRead"]:
    assert "Read(%s/**)" % p in deny or "Read(%s)" % p in deny, p
' "$OURS"
python3 -I "$M" remove "$S" "$OURS" "$ST"
check "...and remove leaves an empty settings file" jq_has "$S" 'd == {}'
printf '%s\n' '{"model": "opus", "sandbox": {"enabled": false}, "permissions": {"deny": ["Read(~/secret)", "Read(~/.ssh/**)"], "allow": ["Bash(make *)"]}}' >"$S"
python3 -I "$M" add "$S" "$OURS" "$ST"
python3 -I "$M" add "$S" "$OURS" "$ST"
check "settings: your own values stay (your sandbox off stays off)" jq_has "$S" 'd["sandbox"]["enabled"] is False and d["model"] == "opus"'
check "...your rules stay, and Wren Linux's are added once, even run twice" \
    jq_has "$S" 'd["permissions"]["deny"].count("Read(~/.gnupg/**)") == 1 and "Read(~/secret)" in d["permissions"]["deny"] and d["permissions"]["allow"] == ["Bash(make *)"]'
python3 -I "$M" remove "$S" "$OURS" "$ST"
check "...remove takes out only Wren Linux's" \
    jq_has "$S" 'd == {"model": "opus", "sandbox": {"enabled": False}, "permissions": {"deny": ["Read(~/secret)", "Read(~/.ssh/**)"], "allow": ["Bash(make *)"]}}'
check "...a rule you had before stays, though Wren Linux has it too" jq_has "$S" '"Read(~/.ssh/**)" in d["permissions"]["deny"]'
echo '[1, 2]' >"$S"
check "settings that aren't a JSON object are left alone" not python3 -I "$M" add "$S" "$OURS" "$ST"
check "...unchanged" test "$(cat "$S")" = '[1, 2]'

# ---- lib/claude-repo.sh: the repository stays while either extra uses it ----
repo() { # MARKS...: which marks exist; prints what was run as root
    (
        . "$HERE/lib.sh" >/dev/null 2>&1
        . "$HERE/lib/claude-repo.sh"
        set +e
        SUDO='echo'
        CLAUDE_SANDBOX_MARK=$T/m/sandbox CLAUDE_REGULAR_MARK=$T/m/regular
        rm -rf "$T/m" && mkdir -p "$T/m"
        for m in "$@"; do : >"$T/m/$m"; done
        note() { :; }
        remove_claude_repo_if_unused
    )
}
check "repository: kept while the sandboxed claude is set up" test -z "$(repo sandbox)"
check "...kept while claude-regular is" test -z "$(repo regular)"
check "...removed when neither is" grep -q "rm -f /etc/apt/sources.list.d/claude-code.list /etc/apt/keyrings/claude-code.asc" <<<"$(repo)"
check "claude-code.sh --remove keeps it for claude-regular" grep -q '^    remove_claude_repo_if_unused$' "$HERE/extras/claude-code.sh"
check "...and no longer deletes it itself" not grep -q 'rm -f "\$LIST" "\$KEY"' "$HERE/extras/claude-code.sh"

# ---- the extras, with pretend programs ----
mkdir -p "$T/bin" "$T/home"
cat >"$T/bin/sudo" <<EOF
#!/bin/sh
[ "\$1" = -v ] && exit 0
echo "sudo \$*" >>"$T/calls"
EOF
# Every package "installed", held by the running script's marker
cat >"$T/bin/dpkg-query" <<'EOF'
#!/bin/sh
case "$*" in
    *Status*) echo 'install ok installed' ;;
    *Depends*) echo 'firefox-esr, libavcodec61, webext-ublock-origin-firefox, claude-code, bubblewrap, socat, git, ripgrep, python3' ;;
esac
EOF
chmod +x "$T/bin/"*
R=$T/r
mkdir -p "$R/extras" "$R/lib"
sed 's|^export PATH=.*|export PATH="$REGULAR_TEST_PATH"|' "$HERE/lib.sh" >"$R/lib.sh"
grep -q REGULAR_TEST_PATH "$R/lib.sh" || { echo "  FAIL  lib.sh's PATH line wasn't found"; exit 1; }
for f in pins.sh packages.sh data bin docs; do ln -s "$HERE/$f" "$R/$f"; done
for f in "$HERE"/lib/*; do ln -s "$f" "$R/lib/${f##*/}"; done
# A pretend repository: the real one fetches Anthropic's key
rm "$R/lib/claude-repo.sh"
cat >"$R/lib/claude-repo.sh" <<EOF
CLAUDE_SANDBOX_MARK=$T/sandbox-mark
CLAUDE_REGULAR_MARK=\$HOME/.local/bin/claude-regular
add_claude_repo() { echo add-repo >>"$T/calls"; }
remove_claude_repo_if_unused() { echo remove-repo-if-unused >>"$T/calls"; }
EOF
cp "$HERE/extras/claude-regular.sh" "$R/extras/"
# shellcheck disable=SC2031  # (the PATH set in repo() above stays in its subshell)
export REGULAR_TEST_PATH="$T/bin:$PATH"
[ "$(bash -c '. "$1/lib.sh"; command -v sudo' _ "$R")" = "$T/bin/sudo" ] || { echo "  FAIL  the real sudo would run; stopping"; exit 1; }
run() { # SCRIPT ARG ANSWER...: ARG is --remove or empty; one answer per question
    local script=$1 arg=$2
    shift 2
    : >"$T/calls"
    printf '%s\n' "$@" >"$T/answers"
    HOME=$T/home XDG_STATE_HOME='' WREN_TEST_ANSWERS=$T/answers bash "$R/extras/$script" ${arg:+"$arg"} >"$T/out" 2>&1
}
H=$T/home

mkdir -p "$H/.claude"
echo '{"permissions": {"deny": ["Read(~/mine)"]}}' >"$H/.claude/settings.json"
run claude-regular.sh ''
check "claude-regular: Anthropic's repository through the shared library" grep -qx add-repo "$T/calls"
check "...its sandbox on, in your settings" jq_has "$H/.claude/settings.json" 'd["sandbox"]["enabled"] is True and "~/.ssh" in d["sandbox"]["filesystem"]["denyRead"]'
check "...next to your own rules" jq_has "$H/.claude/settings.json" '"Read(~/mine)" in d["permissions"]["deny"] and "Edit(~/.profile)" in d["permissions"]["deny"]'
check "...and the claude-regular command" grep -qx 'exec /usr/bin/claude "\$@"' "$H/.local/bin/claude-regular"
check "...says claude is it, without the sandboxed claude" grep -q 'Run it with: claude ' "$T/out"
: >"$T/sandbox-mark"
run claude-regular.sh ''
check "...with the sandboxed claude, says claude-regular" grep -q 'claude asks which one' "$T/out"
run claude-regular.sh --remove
check "--remove: only Wren Linux's settings go" jq_has "$H/.claude/settings.json" 'd == {"permissions": {"deny": ["Read(~/mine)"]}}'
check "...the command goes, and the repository only if unused" bash -c '[ ! -e "$1/.local/bin/claude-regular" ] && grep -qx remove-repo-if-unused "$2"' _ "$H" "$T/calls"

# ---- another account: ~/.claude-work, the same settings, each kept out of the other's folder
runa() { # ANSWER-FILE-LINES... -- SCRIPT ARGS...
    local answers=()
    while [ "$1" != -- ]; do answers+=("$1"); shift; done
    shift
    : >"$T/calls"
    printf '%s\n' "${answers[@]}" >"$T/answers"
    local script=$1
    shift
    HOME=$T/home XDG_STATE_HOME='' WREN_TEST_ANSWERS=$T/answers bash "$R/extras/$script" "$@" >"$T/out" 2>&1
}
echo '{"permissions": {"deny": ["Read(~/mine)"]}}' >"$H/.claude/settings.json"
runa -- claude-regular.sh --account work
check "--account before claude-regular is set up: refused" bash -c '! [ -e "$1/.claude-work" ] && grep -q "Set up claude-regular first" "$2"' _ "$H" "$T/out"
run claude-regular.sh ''
before=$(cat "$H/.claude/settings.json")
runa -- claude-regular.sh --account work
check "--account work: its own settings folder, with Wren Linux's settings" jq_has "$H/.claude-work/settings.json" 'd["sandbox"]["enabled"] is True and "Edit(~/.profile)" in d["permissions"]["deny"]'
check "...kept out of the first account's folder (file tools and sandboxed commands)" jq_has "$H/.claude-work/settings.json" '"Read(~/.claude/**)" in d["permissions"]["deny"] and "~/.claude" in d["sandbox"]["filesystem"]["denyRead"]'
check "...and the first account kept out of its folder" jq_has "$H/.claude/settings.json" '"Read(~/.claude-work/**)" in d["permissions"]["deny"] and "~/.claude-work" in d["sandbox"]["filesystem"]["denyRead"] and "Read(~/mine)" in d["permissions"]["deny"]'
check "...it says this isn't a wall" grep -q "not a wall" "$T/out"
check "...its folder is yours alone" test "$(stat -c %a "$H/.claude-work")" = 700
sed 's|exec /usr/bin/claude|echo "CLAUDE_CONFIG_DIR=${CLAUDE_CONFIG_DIR:-}"; exit; exec /usr/bin/claude|' "$HERE/bin/claude-regular" >"$T/cr"
check "claude-regular --account work: Claude Code with that folder" bash -c '[ "$(HOME=$1 bash "$2" --account work)" = "CLAUDE_CONFIG_DIR=$1/.claude-work" ]' _ "$H" "$T/cr"
check "...without --account: its usual folder" bash -c '[ "$(HOME=$1 CLAUDE_CONFIG_DIR= bash "$2")" = "CLAUDE_CONFIG_DIR=" ]' _ "$H" "$T/cr"
check "...an account that isn't set up, or a name that isn't one: refused" bash -c '
    ! HOME=$1 bash "$2" --account home 2>/dev/null && ! HOME=$1 bash "$2" --account ../x 2>/dev/null' _ "$H" "$T/cr"
runa y -- claude-regular.sh --remove-account work
check "--remove-account (y): its folder goes, the first account's settings are as before" bash -c '
    [ ! -e "$1/.claude-work" ] && [ "$(python3 -I -c "import json,sys; print(json.load(open(sys.argv[1])))" "$1/.claude/settings.json")" = "$(python3 -I -c "import json,sys; print(json.loads(sys.argv[1]))" "$2")" ]' _ "$H" "$before"
runa -- claude-regular.sh --account work
runa n -- claude-regular.sh --remove
check "--remove takes the accounts' settings out too (n: their login stays)" bash -c '
    [ -d "$1/.claude-work" ] && ! grep -q "claude-work" "$1/.claude/settings.json" && ! grep -q "claude/\*\*" "$1/.claude-work/settings.json" 2>/dev/null' _ "$H"


[ "$fails" -eq 0 ]
