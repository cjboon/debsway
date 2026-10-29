#!/bin/bash
# Runs as root INSIDE the onion site's VM, once, right after the unattended
# Debian install (mockvps-kvm --provision), while the VM still has a network.
# extras/onion-site.sh fills in @APP@ (any or python) and @VM_USER@ first.
#
# Afterwards the VM runs with no network at all: visitors reach nginx only
# through Tor on the host, and apt reaches Debian only through the host's Tor,
# during "onion-site update". So nothing the site does can give away the
# host's address, and nothing here may expect the internet later.
#
#   nginx (port 80)  serves /srv/site/static, and passes everything else to the
#                    app on 127.0.0.1:8000; no version banner, no access log
#   any              you run your own app server on 127.0.0.1:8000
#   python           gunicorn runs the Flask app in /srv/site/app (app.py, app)
#                    as a locked-down service, site-app
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

APP='@APP@'
SITE_USER='@VM_USER@'
SITE=/srv/site

log() { printf '\n[onion-site guest] %s\n' "$*"; }
die() { printf '[onion-site guest] ERROR: %s\n' "$*" >&2; exit 1; }
case $APP in any | python) ;; *) die "unknown app kind '$APP'" ;; esac
getent passwd "$SITE_USER" >/dev/null || die "user $SITE_USER not found"

log "The time zone is UTC (a local one would tell visitors where the host is)"
ln -sf /usr/share/zoneinfo/UTC /etc/localtime
echo UTC >/etc/timezone

pkgs=(nginx)
[ "$APP" != python ] || pkgs+=(gunicorn python3-flask)
log "Installing ${pkgs[*]}"
apt-get update
apt-get install -y --no-install-recommends "${pkgs[@]}"

log "The site's folders (owned by $SITE_USER; the web server only reads)"
install -d -o "$SITE_USER" -g "$SITE_USER" -m 0755 "$SITE" "$SITE/static" "$SITE/app"
install -d -o "$SITE_USER" -g "$SITE_USER" -m 0700 "$SITE/data"
if [ ! -e "$SITE/static/index.html" ]; then
    printf '%s\n' '<!doctype html><title>It works</title>' \
        '<p>This onion site works. Put your own files here with: onion-site upload static FOLDER</p>' \
        >"$SITE/static/index.html"
    chown "$SITE_USER:$SITE_USER" "$SITE/static/index.html"
fi
install -d -m 0755 /usr/share/debsway-site
printf '%s\n' '<!doctype html><title>Not running</title>' \
    '<p>The site'"'"'s app isn'"'"'t answering yet (nothing on 127.0.0.1:8000 in the VM).</p>' \
    >/usr/share/debsway-site/no-app.html

log "nginx"
cat >/etc/nginx/sites-available/onion-site <<'EOF'
# Written by debsway extras/onion-site.sh. Every visitor comes through Tor, so
# the logs would only hold times, and those are left out.
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;
    server_tokens off;
    access_log off;
    client_max_body_size 10m;
    root /srv/site/static;
    add_header X-Content-Type-Options nosniff always;
    add_header Referrer-Policy no-referrer always;
    add_header X-Frame-Options SAMEORIGIN always;

    # A file in /srv/site/static if there is one, else the app
    location / {
        try_files $uri $uri/index.html @app;
    }
    location @app {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-Proto http;
        proxy_hide_header X-Powered-By;
        proxy_hide_header Server;
    }
    error_page 502 503 504 /no-app.html;
    location = /no-app.html {
        internal;
        root /usr/share/debsway-site;
    }
}
EOF
rm -f /etc/nginx/sites-enabled/default
ln -sf /etc/nginx/sites-available/onion-site /etc/nginx/sites-enabled/onion-site
nginx -t
systemctl enable nginx >/dev/null
systemctl restart nginx

if [ "$APP" = python ]; then
    log "The Python app: gunicorn, as $SITE_USER, locked down"
    if [ ! -e "$SITE/app/app.py" ]; then
        cat >"$SITE/app/app.py" <<'EOF'
# A starting point (debsway extras/onion-site.sh). Replace it with your own
# Flask app, keeping the name: the service runs app:app from this folder.
# Write anything you keep to /srv/site/data; the rest is read-only to the app.
from flask import Flask

app = Flask(__name__)


@app.route("/hello")
def hello():
    return "Hello from the onion site's Python app.\n"
EOF
        chown "$SITE_USER:$SITE_USER" "$SITE/app/app.py"
    fi
    cat >/etc/systemd/system/site-app.service <<EOF
# Written by debsway extras/onion-site.sh
[Unit]
Description=The onion site's Python app (gunicorn)
After=network.target

[Service]
User=$SITE_USER
Group=$SITE_USER
WorkingDirectory=$SITE/app
ExecStart=/usr/bin/gunicorn --bind 127.0.0.1:8000 --workers 2 app:app
Restart=on-failure
NoNewPrivileges=yes
PrivateTmp=yes
ProtectSystem=strict
ProtectHome=yes
ReadWritePaths=$SITE/data
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectControlGroups=yes
RestrictSUIDSGID=yes
LockPersonality=yes

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable --now site-app.service
fi

log "$SITE_USER may restart the site's services without a password"
printf '%s\n' "# Written by debsway extras/onion-site.sh" \
    "$SITE_USER ALL=(root) NOPASSWD: /usr/bin/systemctl restart site-app.service, /usr/bin/systemctl reload nginx.service" \
    >/etc/sudoers.d/onion-site
chmod 0440 /etc/sudoers.d/onion-site
visudo -cf /etc/sudoers.d/onion-site >/dev/null || { rm -f /etc/sudoers.d/onion-site; die "the sudoers rule didn't pass visudo"; }

log "From now on apt reaches Debian only through the host's Tor (during onion-site update)"
printf '%s\n' '// Written by debsway extras/onion-site.sh: this VM has no network; during' \
    '// "onion-site update" 10.0.2.100:9050 leads to the host'"'"'s Tor.' \
    'Acquire::http::Proxy "socks5h://10.0.2.100:9050";' \
    'Acquire::https::Proxy "socks5h://10.0.2.100:9050";' >/etc/apt/apt.conf.d/90debsway-tor
# The daily apt timers would only fail without a network
systemctl disable --now apt-daily.timer apt-daily-upgrade.timer >/dev/null 2>&1 || true

log "Provisioning finished."
