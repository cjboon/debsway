#!/bin/bash
# OnionShare (from Debian): share files, receive files, host a website or
# run a chat room over Tor, straight from this laptop, with no account and
# no server in between. The other side opens the address in Tor Browser.
#
# OnionShare starts its own private tor. Debian's package also installs
# the system tor service, which would connect to Tor directly the moment
# it's installed, so that service is masked (blocked) first and never runs.
# It first asks whether you need a bridge to reach Tor (built-in obfs4,
# your own obfs4 lines, or Snowflake; OnionShare can't use webtunnel or
# meek on Debian). The choice is written into OnionShare's settings before
# its first start, so its first connection goes through the bridge.
# Usage: bash onionshare.sh [--remove]
# summary: Share files, sites and chat over Tor
# status: apt:onionshare-cli apt:onionshare
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
need_user

SETTINGS="$HOME/.config/onionshare/onionshare.json"

if [ "${1:-}" = --remove ]; then
    apt_purge onionshare onionshare-cli
    note "Your settings stay in ~/.config/onionshare; received files in ~/OnionShare."
    note "The system tor service stays masked: sudo systemctl unmask tor.service tor@default.service"
    exit
fi

# Asked first, before anything is installed
say "Bridges"
old=()
if [ -f "$SETTINGS" ] && command -v python3 >/dev/null; then
    mapfile -t old < <(python3 -I - "$SETTINGS" <<'PY' 2>/dev/null
import json, sys
s = json.load(open(sys.argv[1]))
if s.get("bridges_enabled") and s.get("bridges_type") == "custom":
    print("\n".join(l for l in s.get("bridges_custom", "").split("\n") if l.strip()))
PY
    )
fi
if [ ${#old[@]} -gt 0 ] && ask "Keep the ${#old[@]} bridge line(s) OnionShare already has?" y; then
    BRIDGES=("${old[@]}")
    BRIDGE_TYPE=obfs4
    BRIDGE_WANTED=true
else
    pick_bridges onionshare
fi

say "Blocking the system tor service"
if system_tor_wanted; then
    # parts/apt-tor.sh or extras/remote-access.sh runs it, with your bridge
    note "The system tor service stays on: apt over Tor or remote access uses it."
else
    sudo systemctl mask tor.service tor@default.service >/dev/null
    note "Masked tor.service and tor@default.service: installing tor won't start it."
fi

say "Installing OnionShare"
pkgs=(onionshare-cli obfs4proxy)
# OnionShare finds the Snowflake program by name
[ "$BRIDGE_TYPE" != snowflake ] || pkgs+=(snowflake-client)
if ask "Also install the graphical OnionShare app?" y; then
    # qt6-wayland: lets the Qt 6 app run on Wayland without XWayland
    pkgs+=(onionshare qt6-wayland)
fi
apt_install "${pkgs[@]}"
if ! system_tor_wanted && systemctl is-active --quiet tor.service tor@default.service; then
    warn "The system tor service is running anyway. Stop it: sudo systemctl stop tor@default.service"
fi

# Only these settings are written; OnionShare fills in the rest. Its own
# tor then connects through the bridge, from its very first start.
mkdir -p "$(dirname -- "$SETTINGS")"
python3 -I - "$SETTINGS" "$BRIDGE_TYPE" "${BRIDGES[@]}" <<'PY'
import json, os, sys
path, kind, lines = sys.argv[1], sys.argv[2], sys.argv[3:]
try:
    s = json.load(open(path))
except (OSError, ValueError):
    s = {}
s["connection_type"] = "bundled"
s["bridges_enabled"] = kind != "none"
if kind == "obfs4" and lines:
    s["bridges_type"] = "custom"
    s["bridges_custom"] = "\n".join(lines)
elif kind in ("obfs4-builtin", "snowflake"):
    s["bridges_type"] = "built-in"
    s["bridges_builtin_pt"] = kind.replace("-builtin", "")
tmp = path + ".tmp"
with open(tmp, "w") as f:
    json.dump(s, f, indent=2)
os.chmod(tmp, 0o600)
os.replace(tmp, path)
PY
if [ "$BRIDGE_TYPE" != none ]; then
    note "OnionShare's tor connects through a bridge: $(bridge_summary)."
elif $BRIDGE_WANTED; then
    warn "You said you need a bridge but none was set up: OnionShare connects to Tor directly. Run this again."
else
    note "No bridge: OnionShare's tor connects directly."
fi

cat <<'EOF'

    How to use onionshare-cli (it prints an .onion address and, unless
    --public, a private key; send both to the other person, who opens the
    address in Tor Browser):
      onionshare-cli report.pdf photos/      share files and folders; stops
                                             after the first download
      onionshare-cli --no-autostop-sharing report.pdf
                                             keep sharing after downloads
      onionshare-cli --auto-stop-timer 3600 report.pdf
                                             stop sharing after an hour
      onionshare-cli --receive               let people send you files
                                             (saved in ~/OnionShare)
      onionshare-cli --website ~/site/       host a static website
      onionshare-cli --chat                  start a private chat room
      onionshare-cli --public report.pdf     no private key: anyone with the
                                             address can open it
      onionshare-cli --qr report.pdf         also show the address as a QR code
    Press Ctrl+C to stop sharing.
EOF
if is_installed onionshare; then
    note "The graphical app: onionshare   (or Super+d)"
fi
