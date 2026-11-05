# Sandboxed wallets (`extras/wallet-sandbox.sh`)

**Retired.** Whonix is the safer place for wallets (Feather and Electrum come in its Workstation, behind Tor): wrenctl install whonix. Feather and Sparrow also have a Tor setting of their own. `update.sh` offers to take it out (`wrenctl remove wallet-sandbox`); it is no longer offered to install.

## SYNOPSIS

```
wrenctl install wallet-sandbox      set it up (it asks once about each wallet)
wrenctl remove wallet-sandbox       take it out (your wallets stay)
wrenctl manual wallet-sandbox       print the manual steps below

wallet feather                      open Feather in its sandbox (also sparrow, electrum)
wallet clip                         move one line of text in or out (also Super+Ctrl+w)
```

Runs Feather, Sparrow and Electrum for a computer that can't run VMs: on one that
can, [Whonix](whonix.md) is safer, and the install says so first. Each wallet runs
as its own user, with no password or login, and can't read your files or another
wallet's. A firewall rule lets that user reach Tor's port on this computer and
nothing else, and the wallet checks this from its own side at every start and
while it runs: without the rule it won't open, and it closes if the rule goes. It
opens in a window of its own (cage) with a private X server, so it can't read your
screen or your keys. Nothing crosses by itself: `wallet clip` shows you one line of
plain text before moving it, and files go through `~/Wallets/NAME`. A hardware
wallet and a camera for QR codes are each offered once per wallet, off by default.

## LIMITS

- **Whonix is stronger.** A wallet here shares this computer's kernel, and a flaw in
  it, in X or in cage could get a hacked wallet out. A VM is a much higher wall.
- **Not yet run for real:** the full install under real sudo, opening each wallet,
  the clipboard through a real X server, the Tor settings Wren Linux gives Sparrow
  and Electrum. The hardware wallet and camera options need real devices, and no one
  has tried them yet.
- **A hacked wallet can show you a false address.** The clipboard can't check that.
  Compare an address with where it came from, and on a hardware wallet with its own
  screen.
- **`feather`, `sparrow` and `electrum` started by name still run as you**, outside
  all of this. Open them with `wallet NAME`.
- **Wallets you already have aren't moved.** Restore from the seed in the sandbox, or
  copy the wallet file through `~/Wallets/NAME`, and don't keep using the old copy as
  you.
- **Your backup doesn't cover `/var/lib/wren-wallet`.** Write down each seed. To copy
  a wallet file out, save it to the `transfer` folder from inside the wallet.
- **Feather:** set its proxy to Tor at `127.0.0.1:9050` and turn off starting its own
  Tor, in its network settings. Until then it can't connect, which is the point.
- **Wallets share Tor.** They can use the same circuit, so a server seeing both could
  link your Monero and Bitcoin use. Don't open them at the same time if that matters.
- **Files in `~/Wallets` come from the wallet.** Treat them, and any link among them,
  as untrusted.
- **If Tor is down,** something else on this computer could listen on its port and
  get a wallet's connection. The wallet checks at its start that a port answers, not
  whose it is.
- **The firewall covers the network, not this computer's Unix sockets.** A wallet can
  still talk to local services open to every user, such as the system message bus,
  as Wren Linux's other sandboxes can. So "Tor and nothing else" is about the network.
- **It needs Linux 6.12 or newer** (Landlock), and sway.

## MANUAL INSTALL

The script does these as your user, with sudo. They are many; read the script's
comments for why each one is there.

```
sudo apt install cage xwayland xclip acl nftables python3 tor wl-clipboard
# Install each wallet you want: wrenctl manual feather-wallet (or sparrow-wallet, electrum)

# The users: all three, for the firewall
for w in feather sparrow electrum; do
    sudo useradd --system --user-group --no-create-home --home-dir /var/lib/wren-wallet/$w \
        --shell /usr/sbin/nologin --comment "Wren Linux $w wallet sandbox" wallet-$w
    sudo usermod --lock wallet-$w
    sudo usermod -aG render wallet-$w
done

# For each wallet you want (here w=electrum): its home, and the folder you share
w=electrum
sudo install -d -o root -g root -m 0755 /var/lib/wren-wallet /var/lib/wren-wallet/files
sudo install -d -o wallet-$w -g wallet-$w -m 0700 /var/lib/wren-wallet/$w
sudo install -d -o root -g root -m 0770 /var/lib/wren-wallet/files/$w
sudo setfacl -P -m "u:$USER:rwx,u:wallet-$w:rwx" /var/lib/wren-wallet/files/$w
sudo setfacl -P -d -m "u:$USER:rwx,u:wallet-$w:rwx" /var/lib/wren-wallet/files/$w
ln -sfn /var/lib/wren-wallet/files ~/Wallets
sudo install -d -o root -g root -m 0755 /etc/wren/wallets
printf 'enabled=yes\nhardware=no\ncamera=no\n' | sudo tee /etc/wren/wallets/$w.conf

# Feather only: its files, where its user can read them
sudo install -d -o root -g root -m 0755 /usr/local/lib/wren-wallet
sudo cp -r --no-preserve=all ~/.local/opt/feather /usr/local/lib/wren-wallet/feather
sudo chown -R root:root /usr/local/lib/wren-wallet/feather
sudo chmod -R u+rwX,go+rX,go-w /usr/local/lib/wren-wallet/feather

# The programs
install -D -m 0755 @WREN_DIR@/bin/wayland-restrict ~/.local/bin/wayland-restrict
sudo install -d -o root -g root -m 0755 /usr/local/libexec
sudo install -o root -g root -m 0755 @WREN_DIR@/bin/no-abstract-sockets /usr/local/libexec/wren-no-abstract-sockets
sudo install -o root -g root -m 0755 @WREN_DIR@/bin/wallet /usr/local/bin/wallet
sudo install -o root -g root -m 0755 @WREN_DIR@/bin/wallet-session /usr/local/libexec/wallet-session
sudo install -o root -g root -m 0755 @WREN_DIR@/bin/wallet-net-check /usr/local/libexec/wallet-net-check
sudo install -o root -g root -m 0755 @WREN_DIR@/bin/wallet-camera /usr/local/libexec/wallet-camera

# What you may run as them: only the session script, only the wallets you want
echo "$USER ALL=(wallet-$w) NOPASSWD: /usr/local/libexec/wallet-session" | sudo tee /tmp/wren-wallet.rule
sudo visudo -cf /tmp/wren-wallet.rule
sudo install -o root -g root -m 0440 /tmp/wren-wallet.rule /etc/sudoers.d/wren-wallet
sudo rm /tmp/wren-wallet.rule

# The limits
for u in feather sparrow electrum; do
    printf 'wallet-%s hard nproc 4096\nwallet-%s hard core 0\n' $u $u
done | sudo tee /etc/security/limits.d/50-wren-wallet.conf

# The firewall, at every boot
sudo install -d -o root -g root -m 0755 /etc/wren
sudo install -o root -g root -m 0644 @WREN_DIR@/data/wallet-firewall.nft /etc/wren/wallet.nft
sudo tee /etc/systemd/system/wren-wallet-firewall.service <<'EOF'
[Unit]
Description=Keep the sandboxed wallets on Tor (Wren Linux)
Before=network-pre.target
Wants=network-pre.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/sbin/nft -f /etc/wren/wallet.nft
ExecStop=/usr/sbin/nft delete table inet wren_wallet

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable --now wren-wallet-firewall.service
sudo systemctl enable --now tor.service tor@default.service
```

The clipboard key, in `~/.config/sway/config.d/wallet-sandbox.conf`:

```
bindsym $mod+Ctrl+w exec foot -e /usr/local/bin/wallet clip-window
```

To undo (your wallets stay in `/var/lib/wren-wallet`; only root can read them):

```
sudo systemctl disable --now wren-wallet-firewall.service
sudo rm -f /etc/sudoers.d/wren-wallet /etc/security/limits.d/50-wren-wallet.conf \
    /usr/local/bin/wallet /usr/local/libexec/wallet-session /usr/local/libexec/wallet-net-check \
    /usr/local/libexec/wallet-camera /etc/wren/wallet.nft \
    /etc/systemd/system/wren-wallet-firewall.service /etc/udev/rules.d/71-wren-wallet-*.rules
sudo rm -rf /usr/local/lib/wren-wallet /etc/wren/wallets
sudo systemctl daemon-reload
for w in feather sparrow electrum; do sudo userdel wallet-$w; done
rm -f ~/Wallets ~/.config/sway/config.d/wallet-sandbox.conf
sudo apt-mark auto cage xwayland xclip tor
```
