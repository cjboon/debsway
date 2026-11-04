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
run() { (cd "$1" && shift && bash "$HERE/bin/claude-sandbox" "$@"); }

check "claude says what to do when the sandbox isn't set up" bash -c "! out=\$(cd '$T/home/projects/app' && bash '$HERE/bin/claude-sandbox' 2>&1) && [[ \$out == *'wrenctl install claude-code'* ]]"
touch "$T/rule-claude-agent"
check "claude refuses to start outside ~/projects" bash -c "! out=\$(cd '$T/home/other' && bash '$HERE/bin/claude-sandbox' 2>&1) && [[ \$out == *'only works inside ~/projects'* ]]"
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
    ! out=\$(cd '$W' && bash '$HERE/bin/claude-sandbox' --account work 2>&1) && [[ \$out == *'wrenctl install claude-code --account work'* ]] && [ ! -s '$T/calls' ]"
touch "$T/rule-claude-agent-work"
run "$W" --account work --resume foo
check "--account work: the session runs as claude-agent-work, in ~/projects-work, with the other arguments" \
    grep -qx "sudo -n -u claude-agent-work /usr/local/libexec/claude-session $W --resume foo" "$T/calls"
: >"$T/calls"
run "$W" --account=work >/dev/null 2>&1
check "...--account=work too" grep -q "^sudo -n -u claude-agent-work .* $W$" "$T/calls"
: >"$T/calls"
check "...it refuses ~/projects (the first account's)" bash -c "! (cd '$T/home/projects/app' && bash '$HERE/bin/claude-sandbox' --account work) 2>/dev/null"
check "...and the first account refuses ~/projects-work" bash -c "! (cd '$W' && bash '$HERE/bin/claude-sandbox') 2>/dev/null"
check "...a name that isn't one (../x, capitals) is refused" bash -c "
    ! (cd '$W' && bash '$HERE/bin/claude-sandbox' --account ../x) 2>/dev/null && ! (cd '$W' && bash '$HERE/bin/claude-sandbox' --account Work) 2>/dev/null"
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

# ---- the claude command: what is set up, which is asked, Enter takes the most walled off
C=$T/ch
mkdir -p "$C/home/.local/bin" "$C/home/projects/app" "$C/home/projects-work" "$C/elsewhere"
for c in claude-vm claude-sandbox claude-regular; do
    printf '#!/bin/sh\necho "%s $* in $(pwd)" >"%s/ran"\n' "$c" "$C" >"$C/$c"
    chmod +x "$C/$c"
done
: >"$C/passwd"
have() { rm -f "$C/home/.local/bin/"claude-*; for c; do cp "$C/$c" "$C/home/.local/bin/$c"; done; }
# ch ANSWER ARGS...: in a terminal (script gives one), answering ANSWER (no-terminal: none)
ch() {
    local a=$1; shift; rm -f "$C/ran"
    if [ "$a" = no-terminal ]; then
        (cd "$C/elsewhere" && env -u WAYLAND_DISPLAY HOME="$C/home" WREN_PASSWD="$C/passwd" bash "$HERE/bin/claude" "$@" </dev/null >"$C/out" 2>&1)
    else
        printf '%s\n' "$a" | (cd "$C/elsewhere" && env -u WAYLAND_DISPLAY HOME="$C/home" WREN_PASSWD="$C/passwd" script -qec "bash $HERE/bin/claude $*" /dev/null >"$C/out" 2>&1)
    fi
}
ran() { cat "$C/ran" 2>/dev/null; }
have
ch no-terminal
check "claude with nothing set up: it says how" grep -q 'wrenctl install claude-vm' "$C/out"
have claude-regular
ch no-terminal
check "one way set up: that one, without asking" bash -c '[[ $1 == "claude-regular  in "* ]]' _ "$(ran)"
have claude-sandbox
ch no-terminal
check "the sandboxed one starts in ~/projects when you are elsewhere" bash -c '[[ $1 == "claude-sandbox  in "*/home/projects ]]' _ "$(ran)"
have claude-vm claude-sandbox claude-regular
ch ''
check "several: it asks, and lists them most walled off first" bash -c '
    grep -q "1) in its own virtual machine" "$1" && grep -q "2) as its own user" "$1" && grep -q "3) as you" "$1"' _ "$C/out"
check "...Enter takes the VM" bash -c '[[ $1 == "claude-vm "* ]]' _ "$(ran)"
ch 3
check "...3 takes the third" bash -c '[[ $1 == claude-regular* ]]' _ "$(ran)"
ch no-terminal
check "...no terminal to ask on: the most walled off" bash -c '[[ $1 == "claude-vm "* ]]' _ "$(ran)"
ch '' --resume foo
check "...options of Claude's: the VM takes none, so it isn't offered" bash -c '[[ $1 == "claude-sandbox --resume foo in "* ]]' _ "$(ran)"
ch no-terminal --version
check "...--version asks nothing, and starts no VM" bash -c '[[ $1 == "claude-sandbox --version in "*elsewhere ]]' _ "$(ran)"
have claude-sandbox
printf '%s\n' 'claude-agent:x:1:1::/x:/bin/sh' 'claude-agent-work:x:2:2::/x:/bin/sh' 'claude-agent-Bad:x:3:3::/x:/bin/sh' >"$C/passwd"
ch ''
check "a second account: it asks, not offering names that aren't one" bash -c 'grep -q "account work" "$1" && ! grep -q Bad "$1"' _ "$C/out"
ch 2
check "...2 takes that account, in its own folder" bash -c '[[ $1 == "claude-sandbox --account work in "*/home/projects-work ]]' _ "$(ran)"
ch no-terminal --account work
check "--account: that account, without asking" bash -c '[[ $1 == "claude-sandbox --account work "* ]]' _ "$(ran)"
ch no-terminal --account ../x
check "...a name that isn't one starts nothing" test ! -e "$C/ran"
: >"$C/passwd"; mkdir -p "$C/home/.claude-home"; : >"$C/home/.claude-home/settings.json"
have claude-regular
ch 2
check "claude-regular's second account (~/.claude-NAME) is offered too" bash -c '[[ $1 == "claude-regular --account home "* ]]' _ "$(ran)"
for x in claude-code claude-vm claude-regular; do
    check "extras/$x.sh installs the claude command and takes it out with the last one" bash -c '
        grep -qx "install_bin claude" "$1" && grep -q "remove_claude_chooser" "$1"' _ "$HERE/extras/$x.sh"
done
# remove_claude_chooser, on a temp folder
rc() { rm -rf "$C/rc"; mkdir -p "$C/rc"; printf '#!/bin/sh\n# written by Wren Linux\n' >"$C/rc/claude"; [ -z "$1" ] || : >"$C/rc/$1"
    bash -c 'BIN=$1; eval "$(sed -n "/^remove_bin() {/,/^}/p" "$2/lib/core.sh")"; . "$2/lib/claude-accounts.sh"; remove_claude_chooser' _ "$C/rc" "$HERE"; [ -e "$C/rc/claude" ]; }
check "...it stays while another is set up" rc claude-regular
nochooser() { ! rc ""; }
check "...and goes with the last" nochooser

# ---- Claude Code's theme: Auto (it follows the terminal), unless one was chosen
th() { bash -c 'eval "$(sed -n "/^seed_theme() {/,/^}/p" "$1")"; seed_theme "$2"' _ "$HERE/bin/claude-session" "$1"; }
J=$T/j.json
th "$J"
check "the theme: Auto where nothing is set" python3 -I -c 'import json,sys; assert json.load(open(sys.argv[1]))["theme"] == "auto"' "$J"
check "...the file yours alone" test "$(stat -c %a "$J")" = 600
printf '{"theme": "light", "numStartups": 3}' >"$J"
th "$J"
check "...a theme chosen already stays" python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d == {"theme": "light", "numStartups": 3}' "$J"
printf '{"numStartups": 3}' >"$J"
th "$J"
check "...what else is in the file stays" python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d == {"numStartups": 3, "theme": "auto"}' "$J"
echo 'not json' >"$J"
th "$J"
check "...a file it can't read is left alone" grep -qx 'not json' "$J"
check "...the same in the sandbox, as you and in the VM" bash -c '
    a=$(sed -n "/^seed_theme() {/,/^}/p" "$1/bin/claude-session"); [ -n "$a" ] && [ "$a" = "$(sed -n "/^seed_theme() {/,/^}/p" "$1/bin/claude-regular")" ] &&
    grep -q "seed_theme \"\$HOME/.claude.json\"" "$1/bin/claude-session" && grep -q "seed_theme \"\${CLAUDE_CONFIG_DIR:-\$HOME}/.claude.json\"" "$1/bin/claude-regular" &&
    grep -qF "\"theme\": \"auto\"" "$1/data/claude-vm-provision.sh"' _ "$HERE"

[ "$fails" -eq 0 ]
