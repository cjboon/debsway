# Remote access over Tor (`extras/remote-access.sh`)

This lets you log in to your computer from another one with `ssh`, over a Tor onion service, without opening any port on your firewall or router. Only a computer that holds the client key you are given can connect.

## The problem it solves

If you want to reach your computer from elsewhere, the usual way is to open a port so that the internet can knock on its door. That shows your address to the world, and any scanner can try the door. Here, your computer makes an outgoing connection to Tor, and visitors reach you through it. Nothing on your local network or the wider internet can connect directly.

## The ideas behind it

**SSH.** A tool for logging in to another computer in a terminal, with encrypted traffic. `sshd` is the program that waits for logins on the computer you connect to.

**SSH keys.** A pair of files: a private half you keep, and a public half you put on the computer you want to log in to. It replaces a password. The script allows keys only.

**A port.** A numbered door on a computer. SSH normally uses port 22. A firewall decides which doors accept connections from outside.

**127.0.0.1 (loopback).** An address meaning "this computer itself". When sshd listens only on 127.0.0.1, nothing outside can reach it directly.

**Tor and an onion service.** Tor is a network of volunteer relays that hides who is talking to whom. An onion service is a server reachable through Tor at a `.onion` address, without anyone learning where it really is. See `docs/extras/tor-browser.md`.

**Client authorization.** A Tor feature: the onion service answers only visitors who hold a matching key, so without it the service cannot even be seen. The key has two halves; the public half stays on this computer, the private half goes to the computer you connect from.

**A bridge.** A Tor relay not on the public list, for networks that block Tor. See "Bridges" in `docs/install-base.md`. Only obfs4 and Snowflake are offered here.

## How it works, step by step

1. **Asks first,** before installing anything. If you are logged in over ssh now, it warns you that ssh will move to 127.0.0.1 and ends that way in. It then needs an ssh public key: if `~/.ssh/authorized_keys` has none, it asks you to paste one, checks it with `ssh-keygen` and adds it.
2. **Asks about a bridge,** on a first install when Tor is not already set up by something else. If you say you need one but none was set up, it warns and asks whether to go on.
3. **Writes sshd's settings** to `/etc/ssh/sshd_config.d/00-debsway-remote-access.conf`: `ListenAddress 127.0.0.1`, `PasswordAuthentication no`, `KbdInteractiveAuthentication no`, `PermitRootLogin no`, `AllowUsers` your user. The file is named `00-` because sshd takes the first value it finds.
4. **Installs `openssh-server`, `tor` and `openssl`** (plus `obfs4proxy` or `snowflake-client` for a bridge). Tor is kept from starting until its settings are in.
5. **Checks sshd.** It switches off `ssh.socket` (which ignores `ListenAddress`), runs `sshd -t`, then `sshd -T` to see what sshd will really do. If a setting is wrong (another file overrides debsway's), it stops ssh and tells you. It restarts ssh and checks that it listens only on 127.0.0.1.
6. **Sets up the onion service** in `/etc/tor/torrc` (`HiddenServiceDir /var/lib/tor/debsway-ssh/`, `HiddenServicePort 22 127.0.0.1:22`) and a marker file `/etc/tor/.debsway-remote-access`.
7. **Makes a client key** (x25519, with `openssl`) unless one exists. The public half goes to `/var/lib/tor/debsway-ssh/authorized_clients/`; the private half is shown once and not stored here.
8. **Starts Tor** and waits up to 3 minutes for it to connect. It then prints the `.onion` address and the exact lines to paste on the other computer: install `tor` and `netcat-openbsd`, put the key line in Tor's `ClientOnionAuthDir`, and add a `Host` block with `ProxyCommand nc -X 5 -x 127.0.0.1:9050 %h %p` to `~/.ssh/config`.

## What it changes on your computer

- Packages: `openssh-server`, `tor`, `openssl`, and for a bridge `obfs4proxy` or `snowflake-client`.
- `/etc/ssh/sshd_config.d/00-debsway-remote-access.conf`; `ssh.socket` disabled and `ssh.service` enabled.
- `/etc/tor/torrc`: blocks between `# >>> debsway remote-access >>>` and its end line, plus a bridge block if you chose one.
- `/var/lib/tor/debsway-ssh/` (the onion address and keys) and `/etc/tor/.debsway-remote-access`.
- `tor@default.service` enabled.
- `~/.ssh/authorized_keys`, if you pasted a key.
- The firewall (`ufw`) is unchanged. Nothing in `~/.local/bin`.

## Using it

- Run `bash extras/remote-access.sh` again to see the address, repair it, or authorize another computer (a new client key).
- From the other computer: `ssh debsway` (the host name you put in `~/.ssh/config`). The first connection through Tor can take a few seconds.
- Back up `/var/lib/tor/debsway-ssh` as root: it holds the address.

## What it protects against

- **An open port.** No port is open to your network or the internet.
- **Password guessing.** Keys only, root login off, only your user.
- **Strangers finding the service,** since Tor client authorization hides it from anyone without the key.
- **Your address being shown** to the person connecting.
- **A hidden override of sshd's settings.** The script reads what sshd will actually do and stops if it differs.

## What it doesn't protect against

- **It is still a listening service** (`THREAT-MODEL.md`). A hole in sshd or Tor, or a stolen client key together with your ssh key, would be a way in. Turn it off when you do not need it.
- **A lost or copied private client key,** which lets someone find the service.
- **Your network seeing that you use Tor,** unless you chose a bridge.
- **The computer you connect from** being hacked.
- **Anything about what you do once logged in.**
- **A determined, well-funded attacker.**

## Removing it

`bash extras/remote-access.sh --remove` asks first, because it deletes the onion address for good (a new setup gets another, and every computer needs the new address and key). It removes the sshd settings, the Tor blocks, the service folder and the marker, then stops and disables Tor unless apt over Tor or the onion site needs it. It restarts ssh and uninstalls what it installed. The ssh server stays if you had it before this script. If OnionShare is installed and nothing else uses the system tor, it masks the system tor again. Your `~/.ssh/authorized_keys` is not touched.
