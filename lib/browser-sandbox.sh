# shellcheck shell=bash
# lib/browser-sandbox.sh: what extras/tor-browser.sh and extras/mullvad-browser-sandbox.sh
# share. Each browser runs as a user of its own: no password, no login, its own home, and none
# of your files. bin/browser-sandbox starts it, bin/browser-session is what your user may run as
# that user, and data/NAME-firewall.nft keeps it off this computer and your network.
# Sourced after lib.sh.

BROWSER_CMD=/usr/local/bin/browser-sandbox
BROWSER_SESSION=/usr/local/libexec/browser-session
BROWSER_FILES=/var/lib/wren-browsers
BROWSER_NAMES=(tor-browser mullvad-browser)

# as_browser NAME COMMAND...: COMMAND as that user, from a folder it can enter. Everything in
# its home is done this way: root writing in a folder a hacked browser can change could be
# led through a link to any file on this computer.
as_browser() {
    local name=$1
    shift
    (cd / && sudo -u "$name" -- "$@")
}

# browser_user NAME COMMENT: a system user with no password or login, whose home only it can
# enter. In /home: Tor Browser's AppArmor profile only attaches to a browser under it.
browser_user() {
    local name=$1 comment=$2 home=/home/$1
    if id "$name" >/dev/null 2>&1; then
        [ "$(id -u "$name")" -lt 1000 ] ||
            die "A regular user account called $name already exists; this needs a system user. Rename or remove it first."
    else
        sudo useradd --system --user-group --create-home --home-dir "$home" \
            --shell /usr/sbin/nologin --comment "$comment" "$name"
    fi
    sudo usermod --lock --shell /usr/sbin/nologin "$name"
    # Kept from before a --remove, it may have had another user number. Nothing runs as that
    # user now (--remove ended it all), so this can't be led astray. -h: a link is changed itself.
    if [ "$(sudo stat -c %u "$home")" != "$(id -u "$name")" ]; then
        sudo chown -Rh "$name:$name" "$home"
    fi
    sudo chmod 0700 "$home"
    # cage's Wayland backend opens the GPU's render node even with the software renderer.
    # render, not video: no modesetting.
    if getent group render >/dev/null; then sudo usermod -aG render "$name"; fi
    note "$name: no password, no login; home $home, which only it can enter."
}

# browser_files NAME: the folder you and it share, outside your home: it gets no passage through
# your home. Root's, so it can't change who else gets in. ~/Browsers/NAME on your side.
browser_files() {
    local name=$1 dir=$BROWSER_FILES/$1
    sudo install -d -o root -g root -m 0755 "$BROWSER_FILES"
    sudo install -d -o root -g root -m 0770 "$dir"
    sudo setfacl -P -m "u:$(id -un):rwx,u:$name:rwx" "$dir"
    sudo setfacl -P -d -m "u:$(id -un):rwx,u:$name:rwx" "$dir"
    if [ -e "$HOME/Browsers" ] && [ ! -L "$HOME/Browsers" ]; then
        warn "$HOME/Browsers is already there, so the folders you share with these browsers are only at $BROWSER_FILES."
    else
        ln -sfn "$BROWSER_FILES" "$HOME/Browsers"
    fi
}

# browser_commands NAME: the command, by NAME, and the session script, root's
browser_commands() {
    sudo install -d -o root -g root -m 0755 /usr/local/libexec
    sudo install -o root -g root -m 0755 "$WREN_DIR/bin/browser-sandbox" "$BROWSER_CMD"
    sudo install -o root -g root -m 0755 "$WREN_DIR/bin/browser-session" "$BROWSER_SESSION"
    sudo ln -sfn browser-sandbox "/usr/local/bin/$1"
}

# browser_allow NAME: your user may run the session script as NAME, and nothing else. A broken
# sudoers file locks you out of sudo, so visudo checks it first. A limit on processes keeps a
# runaway page from filling the machine.
browser_allow() {
    local name=$1 rule
    rule=$(mktemp)
    printf '# Written by Wren Linux lib/browser-sandbox.sh. %s may run the browser session script,\n# and nothing else, as the user %s.\n%s ALL=(%s) NOPASSWD: %s\n' \
        "$(id -un)" "$name" "$(id -un)" "$name" "$BROWSER_SESSION" >"$rule"
    if ! sudo visudo -cf "$rule" >/dev/null; then
        rm -f "$rule"
        die "The sudoers rule didn't pass visudo's check, so it wasn't installed."
    fi
    sudo install -o root -g root -m 0440 "$rule" "/etc/sudoers.d/wren-$name"
    rm -f "$rule"
    printf '# Written by Wren Linux lib/browser-sandbox.sh\n%s hard nproc 4096\n%s hard core 0\n' "$name" "$name" |
        sudo tee "/etc/security/limits.d/50-wren-$name.conf" >/dev/null
}

# browser_firewall NAME: its rule, loaded before the network comes up, at every boot
browser_firewall() {
    local name=$1 file=/etc/wren/$1.nft table=wren_${1//-/_} unit=wren-$1-firewall.service
    sudo install -d -o root -g root -m 0755 /etc/wren
    sudo install -o root -g root -m 0644 "$WREN_DIR/data/$name-firewall.nft" "$file"
    # (loading it empties its resolvers set: filled again right after, parts/sandbox-dns.sh)
    printf '%s\n' '# Written by Wren Linux lib/browser-sandbox.sh' '[Unit]' \
        "Description=Keep the $name user off this computer and your network (Wren Linux)" \
        'Before=network-pre.target' 'Wants=network-pre.target' '' '[Service]' \
        'Type=oneshot' 'RemainAfterExit=yes' \
        "ExecStart=/usr/sbin/nft -f $file" \
        'ExecStartPost=-/usr/local/libexec/wren-sandbox-dns' \
        "ExecStop=/usr/sbin/nft delete table inet $table" '' '[Install]' \
        'WantedBy=multi-user.target' | sudo tee "/etc/systemd/system/$unit" >/dev/null
    sudo systemctl daemon-reload
    # Restart, not just enable --now: a changed rule file is only loaded by a restart
    sudo systemctl enable "$unit" >/dev/null && sudo systemctl restart "$unit" ||
        warn "Couldn't load the firewall rule, so it won't start; check: systemctl status $unit"
}

# browser_clip_key: the key that moves a line of text in or out (bin/browser-sandbox)
browser_clip_key() {
    put_snippet browser-sandbox <<SNIPPET
# Move one line of text in or out of a sandboxed browser (Wren Linux lib/browser-sandbox.sh)
bindsym \$mod+Ctrl+b exec foot -e $BROWSER_CMD clip-window
SNIPPET
}

# browser_remove NAME: all but its packages. Its home and the folder you share are asked about
# or kept: they can hold bookmarks and downloads. The shared command goes with the last browser.
browser_remove() {
    local name=$1 home=/home/$1 other left=false
    sudo systemctl disable --now "wren-$name-firewall.service" >/dev/null 2>&1 || true
    sudo nft delete table inet "wren_${name//-/_}" 2>/dev/null || true
    sudo rm -f "/etc/sudoers.d/wren-$name" "/etc/security/limits.d/50-wren-$name.conf" \
        "/usr/local/bin/$name" "/etc/wren/$name.nft" "/etc/systemd/system/wren-$name-firewall.service"
    sudo systemctl daemon-reload >/dev/null 2>&1 || true
    for other in "${BROWSER_NAMES[@]}"; do
        [ ! -e "/usr/local/bin/$other" ] || left=true
    done
    if ! $left; then
        remove_snippet browser-sandbox
        sudo rm -f "$BROWSER_CMD" "$BROWSER_SESSION"
        if [ -L "$HOME/Browsers" ]; then rm -f "$HOME/Browsers"; fi
    fi
    if id "$name" >/dev/null 2>&1; then
        sudo pkill -KILL -u "$name" 2>/dev/null || true
        if sudo test -d "$home" && ask "Also delete this browser's bookmarks and settings ($home)?" n; then
            sudo userdel -r "$name" 2>/dev/null || { sudo userdel "$name"; sudo rm -rf "$home"; }
        else
            sudo userdel "$name"
            sudo test ! -d "$home" || note "Kept $home (only root can read it now)."
        fi
        note "Removed the user $name."
    fi
    if sudo test -d "$BROWSER_FILES/$name"; then
        note "What it saved stays in $BROWSER_FILES/$name; delete it yourself when you don't need it."
    fi
}
