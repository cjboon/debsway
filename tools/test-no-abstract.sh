#!/bin/bash
# Checks bin/no-abstract-sockets: a program started through it can't connect
# to an abstract Unix socket made outside it (XWayland's X11 socket is one),
# but ordinary sockets and its own abstract sockets still work. Needs a kernel
# with Landlock ABI 6 (Linux 6.12); on an older one the checks are skipped.
# Run by test.sh, or:  bash tools/test-no-abstract.sh
# shellcheck disable=SC2016  # the bash -c lines expand their own variables
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
srv.bind("\0wren-test-no-abstract")
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
outside = connects("\0wren-test-no-abstract")
own = socket.socket(socket.AF_UNIX); own.bind("\0wren-own"); own.listen(1)
own_ok = connects("\0wren-own")
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

# --userns: the same wall without no_new_privs, which would stop AppArmor starting Tor
# under its own profile from Tor Browser's. It must give nothing back in exchange.
if [ "$(id -u)" = 0 ]; then
    check "--userns refuses root (root would keep its rights inside)" bash -c '! "$1" --userns true 2>/dev/null' _ "$WRAP"
elif ! err=$("$WRAP" --userns true 2>&1) && grep -q "user namespace" <<<"$err"; then
    printf '  ok    skipped --userns: no user namespaces here\n'
else
    out=$(python3 -I - "$WRAP" <<'PY'
import socket, subprocess, sys
wrap = sys.argv[1]
srv = socket.socket(socket.AF_UNIX)
srv.bind("\0wren-test-no-abstract-userns")
srv.listen(1)
child = r"""
import os, socket
c = socket.socket(socket.AF_UNIX)
try:
    c.connect("\0wren-test-no-abstract-userns"); print("outside=True")
except OSError:
    print("outside=False")
st = dict(l.split(":", 1) for l in open("/proc/self/status") if ":" in l)
print("nnp=%s" % st["NoNewPrivs"].strip())
for k in ("CapEff", "CapPrm", "CapAmb"):
    print("%s=%d" % (k, int(st[k], 16)))
m = open("/proc/self/uid_map").read().split()
print("map=%s" % ("own" if m == [str(os.getuid()), str(os.getuid()), "1"] else m))
"""
r = subprocess.run([wrap, "--userns", sys.executable, "-c", child], capture_output=True, text=True)
print(r.stdout.strip())
r = subprocess.run([wrap, "--userns", "sudo", "-n", "id", "-u"], capture_output=True, text=True)
print("sudo=%s" % r.stdout.strip())
r = subprocess.run([wrap, "--userns", "sh", "-c", "exit 7"])
print("status %d" % r.returncode)
PY
)
    check "--userns: the outside abstract socket is refused" grep -qx 'outside=False' <<<"$out"
    check "...without no_new_privs (what AppArmor would refuse Tor for)" grep -qx 'nnp=0' <<<"$out"
    check "...with no capability left after the exec" bash -c 'for k in CapEff CapPrm CapAmb; do grep -qx "$k=0" <<<"$1" || exit 1; done' _ "$out"
    check "...only this user's own number exists: root isn't mapped" grep -qx 'map=own' <<<"$out"
    check "...so setuid gives nothing: sudo doesn't become root" bash -c '! grep -qx "sudo=0" <<<"$1"' _ "$out"
    check "...and the command's exit status is passed on" grep -qx 'status 7' <<<"$out"
fi

[ "$fails" -eq 0 ]
