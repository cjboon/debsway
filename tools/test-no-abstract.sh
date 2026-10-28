#!/bin/bash
# Checks bin/no-abstract-sockets: a program started through it can't connect
# to an abstract Unix socket made outside it (XWayland's X11 socket is one),
# but ordinary sockets and its own abstract sockets still work. Needs a kernel
# with Landlock ABI 6 (Linux 6.12); on an older one the checks are skipped.
# Run by test.sh, or:  bash tools/test-no-abstract.sh
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
WRAP=$HERE/bin/no-abstract-sockets

fails=0
check() { # DESCRIPTION CONDITION-COMMAND...
    local what=$1
    shift
    if "$@" >/dev/null 2>&1; then printf '  ok    %s\n' "$what"; else printf '  FAIL  %s\n' "$what"; fails=$((fails + 1)); fi
}

if err=$("$WRAP" true 2>&1); then :; elif grep -q "can't stop a program" <<<"$err"; then
    printf '  ok    skipped: this kernel has no Landlock scoping (%s)\n' "$(uname -r)"
    exit 0
fi

# The "outside" program holds the abstract socket and runs the wrapped
# programs; each one prints what happened.
out=$(python3 -I - "$WRAP" <<'PY'
import socket, subprocess, sys
wrap = sys.argv[1]
srv = socket.socket(socket.AF_UNIX)
srv.bind("\0debsway-test-no-abstract")
srv.listen(1)
child = r'''
import socket, sys, tempfile
def connects(addr):
    c = socket.socket(socket.AF_UNIX)
    try:
        c.connect(addr)
        return True
    except OSError:
        return False
outside = connects("\0debsway-test-no-abstract")
own = socket.socket(socket.AF_UNIX); own.bind("\0debsway-own"); own.listen(1)
own_ok = connects("\0debsway-own")
path = tempfile.mkdtemp() + "/s"
ps = socket.socket(socket.AF_UNIX); ps.bind(path); ps.listen(1)
print("outside=%s own=%s path=%s" % (outside, own_ok, connects(path)))
'''
for name, cmd in (("plain", []), ("wrapped", [wrap])):
    r = subprocess.run(cmd + [sys.executable, "-c", child], capture_output=True, text=True)
    print(name, r.stdout.strip())
r = subprocess.run([wrap, "/nonexistent"], capture_output=True)
print("missing", r.returncode)
r = subprocess.run([wrap, "sh", "-c", "exit 7"])
print("status", r.returncode)
PY
)
check "without the wrapper the outside abstract socket is reachable (the test is real)" \
    grep -qx 'plain outside=True own=True path=True' <<<"$out"
check "through the wrapper the outside abstract socket is refused" \
    grep -qx 'wrapped outside=False own=True path=True' <<<"$out"
check "a missing command exits 127" grep -qx 'missing 127' <<<"$out"
check "the command's exit status is passed on" grep -qx 'status 7' <<<"$out"

[ "$fails" -eq 0 ]
