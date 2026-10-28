#!/bin/bash
# Checks the claude and claude-session scripts (bin/) with a pretend sudo, so
# no user is made and nothing is run as anyone else. Run by test.sh, or:
#   bash tools/test-claude.sh
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
fails=0
check() { # DESCRIPTION CONDITION-COMMAND...
    local what=$1
    shift
    if "$@" >/dev/null 2>&1; then printf '  ok    %s\n' "$what"; else printf '  FAIL  %s\n' "$what"; fails=$((fails + 1)); fi
}

mkdir -p "$T/fake" "$T/home/projects/app" "$T/home/other"
# a pretend sudo: "-l" says whether the rule exists (when $T/rule is there), else it writes down the call
cat >"$T/fake/sudo" <<EOF
#!/bin/sh
case "\$*" in *" -l "*) [ -e "$T/rule" ] ;; *) echo "sudo \$*" >>"$T/calls" ;; esac
EOF
chmod +x "$T/fake/sudo"
export PATH="$T/fake:$PATH" HOME="$T/home"
run() { (cd "$1" && shift && bash "$HERE/bin/claude" "$@"); }

check "claude says what to do when the sandbox isn't set up" bash -c "! out=\$(cd '$T/home/projects/app' && bash '$HERE/bin/claude' 2>&1) && [[ \$out == *extras/claude-code.sh* ]]"
touch "$T/rule"
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
check "claude-unsandboxed runs the real thing as you" grep -q 'exec /usr/bin/claude "\$@"' "$HERE/bin/claude-unsandboxed"

[ "$fails" -eq 0 ]
