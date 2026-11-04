# Remote access over Tor (`extras/remote-access.sh`)

## SYNOPSIS

```
wrenctl install remote-access                     set it up, repair it, see the address, or authorize another computer
wrenctl remove remote-access                      take it out (deletes the onion address for good; asks first)
wrenctl manual remote-access                      print the manual steps below

ssh wren        on the other computer, once it has the client key and ~/.ssh/config lines
```

ssh into this computer from another one over a Tor onion service, with no
port open on the firewall. sshd listens on 127.0.0.1 only, with key login
only, for your user only, and a shell and file copies only: no forwarding of
ports, sockets, your agent or X11. Tor makes an outgoing connection to the
Tor network and passes ssh through it to this computer's .onion address. The
onion service also needs a client key (Tor's client authorization), so nobody
without it can even see that the service exists; its private half is shown
once, for you to copy to the computer you'll connect from. If you need a
bridge to reach Tor, it goes into tor's settings before tor first starts. The
script asks sshd what it will really do (`sshd -T`) and stops ssh if another
setting overrides one of these.

## LIMITS

- Anyone with your ssh key and the client key can log in as you: keep both safe on the other computer.
- Whoever has `/var/lib/tor/wren-ssh` can be this address: back it up as root, and keep it private.
- Your network sees that this computer uses Tor, unless a bridge hides it.
- While logged in over ssh, you have everything your user has.

## MANUAL INSTALL

```
# The public key of the computer you'll connect from (its ~/.ssh/id_ed25519.pub:
# one line starting with ssh-ed25519, nothing in front) in your authorized_keys
mkdir -p ~/.ssh && chmod 700 ~/.ssh
echo 'ssh-ed25519 AAAA... name' >>~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys

# sshd's settings before it is installed, so it never listens anywhere else.
# 00-: sshd takes the first value it finds, reading these files in name order.
sudo mkdir -p /etc/ssh/sshd_config.d
sudo tee /etc/ssh/sshd_config.d/00-wren-remote-access.conf <<EOF
ListenAddress 127.0.0.1
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
AllowUsers $USER
AllowTcpForwarding no
AllowStreamLocalForwarding no
GatewayPorts no
AllowAgentForwarding no
X11Forwarding no
PermitTunnel no
PermitUserEnvironment no
MaxAuthTries 3
LoginGraceTime 30
EOF

# Debian starts tor the moment it is installed: hold it until it is set up
sudo systemctl mask tor.service tor@default.service
# sshd, tor, and openssl to make the client key (add obfs4proxy or
# snowflake-client for a bridge; for webtunnel, lyrebird: see
# docs/install-base.md, "webtunnel for the system Tor")
sudo apt install --no-install-recommends openssh-server tor openssl
# Debian can start sshd from a socket, which ignores ListenAddress
sudo systemctl disable --now ssh.socket
sudo systemctl enable ssh.service

# sshd accepts the settings, and really uses them: this must print
# listenaddress 127.0.0.1:22, passwordauthentication no, permitrootlogin no,
# allowusers YOU, allowtcpforwarding no, x11forwarding no
sudo sshd -t
sudo sshd -T | grep -E '^(listenaddress|passwordauthentication|kbdinteractiveauthentication|permitrootlogin|allowusers|allowtcpforwarding|allowagentforwarding|x11forwarding|permittunnel) '
sudo systemctl restart ssh.service
# Only 127.0.0.1:22 may be listed here
ss -Hltn 'sport = :22'

# A bridge, if you need one, at the end of /etc/tor/torrc (obfs4 lines from
# bridges.torproject.org; for Snowflake see data/snowflake-bridges.txt):
#   UseBridges 1
#   ClientTransportPlugin obfs4 exec /usr/bin/obfs4proxy
#   Bridge obfs4 1.2.3.4:443 FINGERPRINT cert=... iat-mode=0

# The onion service: ssh on this computer, as port 22 of the .onion address
printf '%s\n' '# >>> Wren Linux remote-access >>>' 'HiddenServiceDir /var/lib/tor/wren-ssh/' 'HiddenServiceVersion 3' \
    'HiddenServicePort 22 127.0.0.1:22' '# <<< Wren Linux remote-access <<<' | sudo tee -a /etc/tor/torrc
sudo install -d -m 0700 -o debian-tor -g debian-tor /var/lib/tor/wren-ssh /var/lib/tor/wren-ssh/authorized_clients
# A mark that tells Wren Linux's other scripts this uses the system tor (so
# OnionShare doesn't block it, and removing apt over Tor doesn't stop it)
echo 'Written by Wren Linux extras/remote-access.sh: ssh over a Tor onion service.' | sudo tee /etc/tor/.wren-remote-access

# A client key: tor gets the public half; keep the private half for the other computer
openssl genpkey -algorithm x25519 -outform DER -out /tmp/client.der
PRIV=$(tail -c 32 /tmp/client.der | base32 | tr -d =)
PUB=$(openssl pkey -inform DER -in /tmp/client.der -pubout -outform DER | tail -c 32 | base32 | tr -d =)
rm /tmp/client.der
echo "descriptor:x25519:$PUB" | sudo install -o debian-tor -g debian-tor -m 0600 /dev/stdin /var/lib/tor/wren-ssh/authorized_clients/client.auth

# Start tor now and at every boot, wait for the address, and show it
sudo systemctl unmask tor.service tor@default.service
sudo systemctl enable tor.service tor@default.service
sudo systemctl restart tor@default.service
sleep 30
ONION=$(sudo cat /var/lib/tor/wren-ssh/hostname)
echo "$ONION"
echo "the client key: ${ONION%.onion}:descriptor:x25519:$PRIV"
```

On the computer you'll connect from (it needs `tor` and `netcat-openbsd`):

```
# The client key, where its tor looks for it (the "client key" line from above)
sudo install -d -m 0700 -o debian-tor -g debian-tor /var/lib/tor/onion_auth
echo 'ADDRESS:descriptor:x25519:PRIVATE' | sudo tee /var/lib/tor/onion_auth/wren.auth_private
echo 'ClientOnionAuthDir /var/lib/tor/onion_auth' | sudo tee -a /etc/tor/torrc
sudo systemctl restart tor@default
# ssh through tor's SOCKS port
printf '%s\n' 'Host wren' '    HostName ADDRESS.onion' '    User YOU' '    ProxyCommand nc -X 5 -x 127.0.0.1:9050 %h %p' >>~/.ssh/config
ssh wren
```

To undo (this computer's onion address is gone for good):

```
# sshd back to Debian's settings
sudo rm /etc/ssh/sshd_config.d/00-wren-remote-access.conf
# The onion service's lines in torrc, and its keys
sudo sed -i '/^# >>> Wren Linux remote-access >>>$/,/^# <<< Wren Linux remote-access <<<$/d' /etc/tor/torrc
sudo rm -rf /var/lib/tor/wren-ssh
sudo rm /etc/tor/.wren-remote-access
# Stop tor (unless apt over Tor or the onion site uses it), and sshd
sudo systemctl disable --now tor@default.service tor.service
sudo apt purge openssh-server
sudo apt-mark auto tor openssl obfs4proxy lyrebird snowflake-client
sudo apt autoremove --purge
# Once lyrebird is gone (webtunnel; not if apt over Tor or the onion site
# still use it), the Tor Project's repository too
dpkg -s lyrebird >/dev/null 2>&1 || sudo rm -f /etc/apt/sources.list.d/wren-torproject.list \
    /etc/apt/preferences.d/wren-torproject.pref /usr/share/keyrings/wren-torproject.asc /etc/apt/apt.conf.d/52wren-torproject
```
