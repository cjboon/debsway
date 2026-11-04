#!/bin/bash
# Checks the claude and claude-session scripts (bin/) with a pretend sudo, so
# no user is made and nothing is run as anyone else; and another account's
# parts (claude --account, lib/claude-accounts.sh's firewall lines, the
# install script's order). Run by test.sh, or:
#   bash tools/test-claude.sh
# shellcheck disable=SC2016  # the inner shells expand their own variables
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
fails=0
check() { # DESCRIPTION CONDITION-COMMAND...
    local what=$1
    shift
    if "$@" >/dev/null 2>&1; then printf '  ok    %s\n' "$what"; else printf '  FAIL  %s\n' "$what"; fails=$((fails + 1)); fi
}

mkdir -p "$T/fake" "$T/home/projects/app" "$T/home/projects-work/app" "$T/home/other"
# a pretend sudo: "-l" says whether the rule for the user after -u exists
# ($T/rule-USER), else it writes down the call
cat >"$T/fake/sudo" <<EOF
#!/bin/sh
case "\$*" in *" -l "*) [ -e "$T/rule-\$3" ] ;; *) echo "sudo \$*" >>"$T/calls" ;; esac
EOF
chmod +x "$T/fake/sudo"
export PATH="$T/fake:$PATH" HOME="$T/home"
run() { (cd "$1" && shift && bash "$HERE/bin/claude" "$@"); }

check "claude says what to do when the sandbox isn't set up" bash -c "! out=\$(cd '$T/home/projects/app' && bash '$HERE/bin/claude' 2>&1) && [[ \$out == *'wrenctl install claude-code'* ]]"
touch "$T/rule-claude-agent"
check "claude refuses to start outside ~/projects" bash -c "! out=\$(cd '$T/home/other' && bash '$HERE/bin/claude' 2>&1) && [[ \$out == *'only works inside ~/projects'* ]]"
check "a refusal starts nothing" test ! -e "$T/calls"

run "$T/home/projects/app" --resume foo
check "inside a project it runs the session as claude-agent with the folder and the arguments" \
    grep -qx "sudo -n -u claude-agent /usr/local/libexec/claude-session $(cd "$T/home/projects/app" && pwd -P) --resume foo" "$T/calls"
: >"$T/calls"
run "$T/home/projects/app" >/dev/null 2>&1
run "$T/home/projects" --version
check "the projects folder itself is allowed" grep -q "claude-session $(cd "$T/home/projects" && pwd -P) --version" "$T/calls"
: >"$T/calls"
run "$T/home/other" --version
check "--version works from anywhere" grep -q "claude-session $(cd "$T/home/projects" && pwd -P) --version" "$T/calls"
check "claude-session refuses anyone but claude-agent" bash -c "! bash '$HERE/bin/claude-session' '$T' 2>/dev/null"
check "the GitHub host keys come with wget, which Wren Linux has (curl isn't installed)" bash -c '
    ! grep -q "curl " "$1" && ! grep -q "curl " "$2" && grep -q "api.github.com/meta" "$1"' _ "$HERE/extras/claude-code.sh" "$HERE/docs/extras/claude-code.md"
check "claude-unsandboxed runs the real thing as you" grep -q 'exec /usr/bin/claude "\$@"' "$HERE/bin/claude-unsandboxed"

# ---- Another account
W=$(cd "$T/home/projects-work/app" && pwd -P)
: >"$T/calls"
check "--account: not set up yet, it says how, and starts nothing" bash -c "
    ! out=\$(cd '$W' && bash '$HERE/bin/claude' --account work 2>&1) && [[ \$out == *'wrenctl install claude-code --account work'* ]] && [ ! -s '$T/calls' ]"
touch "$T/rule-claude-agent-work"
run "$W" --account work --resume foo
check "--account work: the session runs as claude-agent-work, in ~/projects-work, with the other arguments" \
    grep -qx "sudo -n -u claude-agent-work /usr/local/libexec/claude-session $W --resume foo" "$T/calls"
: >"$T/calls"
run "$W" --account=work >/dev/null 2>&1
check "...--account=work too" grep -q "^sudo -n -u claude-agent-work .* $W$" "$T/calls"
: >"$T/calls"
check "...it refuses ~/projects (the first account's)" bash -c "! (cd '$T/home/projects/app' && bash '$HERE/bin/claude' --account work) 2>/dev/null"
check "...and the first account refuses ~/projects-work" bash -c "! (cd '$W' && bash '$HERE/bin/claude') 2>/dev/null"
check "...a name that isn't one (../x, capitals) is refused" bash -c "
    ! (cd '$W' && bash '$HERE/bin/claude' --account ../x) 2>/dev/null && ! (cd '$W' && bash '$HERE/bin/claude' --account Work) 2>/dev/null"
check "...and none of those started anything" test ! -s "$T/calls"

# The firewall gets a line, by number, for each account user, after claude-agent's
printf '%s\n' 'root:x:0:0::/root:/bin/sh' 'claude-agent:x:900:900::/home/claude-agent:/bin/bash' \
    'claude-agent-work:x:901:901::/home/claude-agent-work:/bin/bash' 'claude-agent-Bad:x:902:902::/x:/bin/sh' \
    'claude-agentx:x:903:903::/x:/bin/sh' 'claude-agent-home2:x:904:904::/home/claude-agent-home2:/bin/bash' >"$T/passwd"
fw=$(WREN_PASSWD=$T/passwd bash -c '. "$1/lib/claude-accounts.sh"; claude_firewall_text "$1/data/claude-firewall.nft"' _ "$HERE")
check "firewall: a line for each account (by number), after claude-agent's" bash -c '
    grep -A2 "meta skuid \"claude-agent\" jump claude" <<<"$1" | grep -qx "        meta skuid 901 jump claude  # claude-agent-work" &&
    grep -qx "        meta skuid 904 jump claude  # claude-agent-home2" <<<"$1"' _ "$fw"
check "...none for users that only look like one" bash -c '! grep -qE "skuid (902|903)" <<<"$1"' _ "$fw"
check "...and the rest as it was" bash -c 'diff <(grep -v "skuid [0-9]" <<<"$1") "$2"' _ "$fw" "$HERE/data/claude-firewall.nft"
# (nft reads regular files only; claude-agent doesn't exist here, and nft
# resolves names, so the check uses this user's)
: >"$T/empty.nft"
if unshare -rn /usr/sbin/nft -c -f "$T/empty.nft" >/dev/null 2>&1; then
    sed "s/\"claude-agent\"/\"$(id -un)\"/" <<<"$fw" >"$T/fw.nft"
    check "...which nft accepts" unshare -rn /usr/sbin/nft -c -f "$T/fw.nft"
else
    echo "  skip  nft can't check rules here (no user namespaces)"
fi

# The install script: --account needs the first set up; the rule is checked before it is used;
# removing an account writes the firewall again after the user is gone
c=$HERE/extras/claude-code.sh
check "install: an account needs the sandboxed Claude set up first" grep -q 'die "Set up the sandboxed Claude first' "$c"
check "...the firewall rule is checked by nft before it replaces the old one" bash -c '
    s=$(sed -n "/^write_firewall() {/,/^}/p" "$1"); [[ $s == *"nft -c -f"*"install -o root"* ]]' _ "$c"
check "...removing an account: its user goes first, then the firewall is written" bash -c '
    s=$(sed -n "/--remove-account \] ; then\|= --remove-account \]; then/,/exit/p" "$1"); [[ $s == *remove_account*write_firewall* ]]' _ "$c"
check "...each account has its own sudo rule, checked by visudo" bash -c '
    grep -q "ACCOUNT_SUDOERS=/etc/sudoers.d/wren-claude-\$1" "$1" && grep -q "sudoers_rule \"\$ACCOUNT_SUDOERS\"" "$1" &&
    sed -n "/^sudoers_rule() {/,/^}/p" "$1" | grep -q "visudo -cf"' _ "$c"
check "claude-session lets in the account users only (pattern)" grep -qF '[[ $me == claude-agent || $me =~ ^claude-agent-[a-z][a-z0-9]{0,14}$ ]]' "$HERE/bin/claude-session"

[ "$fails" -eq 0 ]
