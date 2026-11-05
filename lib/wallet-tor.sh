# shellcheck shell=bash
# lib/wallet-tor.sh: offering Tor to a wallet when it is installed
# (extras/feather-wallet.sh, extras/sparrow-wallet.sh, extras/electrum.sh).
# Sourced after lib.sh. Each wallet keeps its settings in a JSON file of its
# own; only the network keys are set, everything else in it stays.

# The system tor service's SOCKS port (parts/apt-tor.sh, remote access, the
# onion site start it)
WALLET_TOR_SOCKS=127.0.0.1:9050

# system_tor_runs: the system tor service is up, so its SOCKS port is there
system_tor_runs() { systemctl is-active --quiet tor@default.service 2>/dev/null; }

# wallet_json_set FILE JSON: merges the object JSON into the object in FILE
# (made, only you can read it, if it isn't there). A FILE that isn't a JSON
# object is left alone, and this fails.
wallet_json_set() {
    mkdir -p "${1%/*}"
    python3 -I - "$1" "$2" <<'PY'
import json, os, sys
path, new = sys.argv[1], json.loads(sys.argv[2])
cur = {}
if os.path.exists(path):
    with open(path) as f:
        text = f.read()
    if text.strip():
        cur = json.loads(text)
if not isinstance(cur, dict):
    sys.exit(1)
cur.update(new)
tmp = path + ".wren-new"
fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
with os.fdopen(fd, "w") as f:
    json.dump(cur, f, indent=4)
os.replace(tmp, path)
PY
}

# wallet_offer_tor NAME PROCESS FILE JSON WHAT HOW: before NAME's first run
# (no FILE yet), asks (yes by default) whether it goes through Tor, and if so
# writes JSON into FILE. PROCESS is its program's name, WHAT says through which
# Tor, HOW where in NAME the setting is. Once NAME has settings of its own
# they are yours: this only says where the setting is.
wallet_offer_tor() {
    local name=$1 proc=$2 file=$3 json=$4 what=$5 how=$6
    if [ -e "$file" ] || pgrep -u "$(id -u)" -x "$proc" >/dev/null 2>&1; then
        note "Tor for $name: $how"
        return 0
    fi
    say "Tor for $name"
    note "$what"
    if ! ask "Send $name through Tor?" y; then
        note "Left as it is. Later: $how"
        return 0
    fi
    if wallet_json_set "$file" "$json"; then
        note "Set in $file."
    else
        warn "Couldn't write $file. Switch it on in $name: $how"
    fi
}
