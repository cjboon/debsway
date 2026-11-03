# OnionShare (`extras/onionshare.sh`)

## SYNOPSIS

```
wrenctl install onionshare                     install it (asks about a bridge, and the graphical app)
wrenctl remove onionshare                      remove it (settings and received files stay)
wrenctl manual onionshare                      print the manual steps below

onionshare-cli report.pdf photos/      share files; stops after the first download
onionshare-cli --no-autostop-sharing report.pdf    keep sharing after downloads
onionshare-cli --auto-stop-timer 3600 report.pdf   stop after an hour
onionshare-cli --receive               let people send you files (to ~/OnionShare)
onionshare-cli --website ~/site/       host a static website
onionshare-cli --chat                  a private chat room
onionshare-cli --public report.pdf     no private key: anyone with the address can open it
onionshare-cli --qr report.pdf         also show the address as a QR code
onionshare                             the graphical app (or Super+d)
```

OnionShare, from Debian, shares files, receives files, hosts a website or
runs a chat room over Tor, straight from this laptop, with no account and no
server in between. It prints an .onion address and, unless `--public`, a
private key; the other person opens the address in Tor Browser. It starts its
own private tor. Debian's package also installs the system tor service, which
would connect to Tor the moment it is installed, so that is masked first
(unless apt over Tor, remote access or the onion site runs it). If you need a
bridge to reach Tor (built-in obfs4, your own obfs4 lines, or Snowflake), it
goes into OnionShare's settings before its first start, so its first
connection already uses it.

## LIMITS

- Anyone with the address (and the key, unless `--public`) can open what you share: send them over a channel you trust.
- While it runs, this laptop is the server: shut the lid or lose the network and the share stops.
- Files you receive can be anything: don't open them on this computer without care.
- Tor hides your address from the other side, not what you put in the files.

## MANUAL INSTALL

```
# Keep the system tor service from starting (skip this if apt over Tor,
# remote access or the onion site uses it: systemctl is-enabled tor@default.service)
sudo systemctl mask tor.service tor@default.service

# OnionShare's command line, obfs4 for bridges; add snowflake-client for a
# Snowflake bridge, and "onionshare qt6-wayland" for the graphical app
sudo apt install --no-install-recommends onionshare-cli obfs4proxy

# Its settings before its first start: its own tor, and the bridge.
# Run ONE of these four lines:
# no bridge
python3 -c 'import json,os,sys; p=sys.argv[1]; os.makedirs(os.path.dirname(p),exist_ok=True); json.dump({"connection_type":"bundled","bridges_enabled":False},open(p,"w"),indent=2)' ~/.config/onionshare/onionshare.json
# the built-in obfs4 bridges
python3 -c 'import json,os,sys; p=sys.argv[1]; os.makedirs(os.path.dirname(p),exist_ok=True); json.dump({"connection_type":"bundled","bridges_enabled":True,"bridges_type":"built-in","bridges_builtin_pt":"obfs4"},open(p,"w"),indent=2)' ~/.config/onionshare/onionshare.json
# Snowflake (needs snowflake-client, above)
python3 -c 'import json,os,sys; p=sys.argv[1]; os.makedirs(os.path.dirname(p),exist_ok=True); json.dump({"connection_type":"bundled","bridges_enabled":True,"bridges_type":"built-in","bridges_builtin_pt":"snowflake"},open(p,"w"),indent=2)' ~/.config/onionshare/onionshare.json
# your own obfs4 lines (from bridges.torproject.org), one per line in ~/bridges.txt
python3 -c 'import json,os,sys; p=sys.argv[1]; os.makedirs(os.path.dirname(p),exist_ok=True); json.dump({"connection_type":"bundled","bridges_enabled":True,"bridges_type":"custom","bridges_custom":open(sys.argv[2]).read().strip()},open(p,"w"),indent=2)' ~/.config/onionshare/onionshare.json ~/bridges.txt
# Only you may read it (bridge lines are private)
chmod 600 ~/.config/onionshare/onionshare.json

# The system tor must not be running now: this must say "inactive"
systemctl is-active tor@default.service
```

To undo (your settings stay in `~/.config/onionshare`, received files in `~/OnionShare`):

```
# OnionShare (add onionshare qt6-wayland if you installed the app)
sudo apt purge onionshare-cli
# obfs4 and Snowflake, marked "automatic": autoremove takes them out only if nothing needs them
sudo apt-mark auto obfs4proxy snowflake-client
sudo apt autoremove --purge
# Let the system tor service start again, if you want it
sudo systemctl unmask tor.service tor@default.service
```
