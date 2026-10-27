#!/bin/bash
# OnionShare (from Debian): share files, receive files, host a website or
# run a chat room over Tor, straight from this laptop, with no account and
# no server in between. The other side opens the address in Tor Browser.
#
# OnionShare starts its own private tor. Debian's package also installs
# the system tor service, which would connect to Tor directly the moment
# it's installed, so that service is masked (blocked) first and never runs.
# Your obfs4 bridges are written into OnionShare's settings before its
# first start, so its first connection goes through them.
# Usage: bash onionshare.sh [--remove]
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
need_user

SETTINGS="$HOME/.config/onionshare/onionshare.json"

if [ "${1:-}" = --remove ]; then
    apt_purge onionshare onionshare-cli
    note "Your settings stay in ~/.config/onionshare; received files in ~/OnionShare."
    note "The system tor service stays masked: sudo systemctl unmask tor.service tor@default.service"
    exit
fi

say "Blocking the system tor service"
sudo systemctl mask tor.service tor@default.service >/dev/null
note "Masked tor.service and tor@default.service: installing tor won't start it."

say "Installing OnionShare"
pkgs=(onionshare-cli obfs4proxy)
if ask "Also install the graphical OnionShare app?" y; then
    # qt6-wayland: lets the Qt 6 app run on Wayland without XWayland
    pkgs+=(onionshare qt6-wayland)
fi
apt_install "${pkgs[@]}"
if systemctl is-active --quiet tor.service tor@default.service; then
    warn "The system tor service is running anyway. Stop it: sudo systemctl stop tor@default.service"
fi

say "Bridges"
mapfile -t old < <(python3 -I - "$SETTINGS" <<'PY' 2>/dev/null
import json, sys
s = json.load(open(sys.argv[1]))
if s.get("bridges_enabled") and s.get("bridges_type") == "custom":
    print("\n".join(l for l in s.get("bridges_custom", "").split("\n") if l.strip()))
PY
)
if [ ${#old[@]} -gt 0 ] && ask "Keep the ${#old[@]} bridge line(s) OnionShare already has?" y; then
    BRIDGES=("${old[@]}")
else
    read_bridges obfs4
fi

# Only these settings are written; OnionShare fills in the rest
mkdir -p "$(dirname -- "$SETTINGS")"
python3 -I - "$SETTINGS" "${BRIDGES[@]}" <<'PY'
import json, os, sys
path, bridges = sys.argv[1], sys.argv[2:]
try:
    s = json.load(open(path))
except (OSError, ValueError):
    s = {}
s["connection_type"] = "bundled"
s["bridges_enabled"] = bool(bridges)
if bridges:
    s["bridges_type"] = "custom"
    s["bridges_custom"] = "\n".join(bridges)
tmp = path + ".tmp"
with open(tmp, "w") as f:
    json.dump(s, f, indent=2)
os.chmod(tmp, 0o600)
os.replace(tmp, path)
PY
if [ ${#BRIDGES[@]} -gt 0 ]; then
    note "OnionShare's tor connects through your ${#BRIDGES[@]} obfs4 bridge(s)."
else
    warn "No bridges: OnionShare connects to Tor directly. Run this again to add some."
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
