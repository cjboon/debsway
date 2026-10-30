"""Sets debsway's values in Transmission's settings.json (extras/torrent.sh).

    python3 -I torrent-settings.py SETTINGS.JSON DOWNLOAD-DIR INCOMPLETE-DIR < PASSWORD

Run as root while transmission-daemon is stopped (it writes the file back when
it stops). The remote-control password comes on standard input, so it never
shows in a list of processes; Transmission stores a hash of it when it starts.
Every other setting is kept as it was.
"""
import json
import os
import sys

path, download_dir, incomplete_dir = sys.argv[1:4]
password = sys.stdin.readline().strip()
if len(password) < 16:
    sys.exit("torrent-settings: no password (at least 16 characters) on standard input")

with open(path) as f:
    settings = json.load(f)

settings.update({
    # finished downloads, in a folder you can read; unfinished ones apart
    "download-dir": download_dir,
    "incomplete-dir": incomplete_dir,
    "incomplete-dir-enabled": True,
    # files: rw for the daemon, readable by your group, nothing for others
    "umask": 23,  # 027 in octal
    # the remote control: this computer only, with a password of its own
    "rpc-enabled": True,
    "rpc-bind-address": "127.0.0.1",
    "rpc-whitelist-enabled": True,
    "rpc-whitelist": "127.0.0.1,::1",
    "rpc-host-whitelist-enabled": True,
    "rpc-authentication-required": True,
    "rpc-username": "debsway",
    "rpc-password": password,
    # no opening of ports on your router (UPnP, NAT-PMP), no looking for
    # peers on your local network
    "port-forwarding-enabled": False,
    "lpd-enabled": False,
    "peer-port-random-on-start": False,
    # prefer encrypted connections to peers
    "encryption": 1,
})

tmp = path + ".debsway-new"
with open(tmp, "w") as f:
    json.dump(settings, f, indent=4, sort_keys=True)
    f.write("\n")
st = os.stat(path)
os.chown(tmp, st.st_uid, st.st_gid)
os.chmod(tmp, st.st_mode & 0o7777)
os.replace(tmp, path)
