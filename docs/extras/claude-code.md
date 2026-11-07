# Claude Code, as its own user (`extras/claude-code.sh`)

**Retired.** An AI agent belongs behind the strongest wall Wren Linux has, and on this one it shares your kernel and your ~/projects: wrenctl install claude-vm. Its --remove leaves your files in ~/projects. `update.sh` offers to take it out (`wrenctl remove claude-code`); it is no longer offered to install. A computer that can't run VMs has no sandboxed Claude Code from Wren Linux.

## SYNOPSIS

```
wrenctl install claude-code                         install it and the claude-agent user
wrenctl remove claude-code                          remove it (asks before deleting the user)
wrenctl manual claude-code                          print the manual steps below
wrenctl install claude-code --account NAME          another account, apart from the first
wrenctl install claude-code --remove-account NAME   remove it (asks before deleting its user)

claude                           Claude Code; asks which if you set up more than one (Enter: the most walled off)
cd ~/projects/NAME && claude-sandbox   Claude Code as claude-agent, in that folder
cd ~/projects-NAME/X && claude-sandbox --account NAME   the other account, in its own folder
claude-unsandboxed               Claude Code as you, with all your files
claude-pull                      in your copy of a repository: shows what Claude pushed, brings it in on y
```

Claude Code, Anthropic's coding assistant for the terminal, from Anthropic's signed apt repository
(its key must be exactly `ANTHROPIC_FPR` in `pins.sh`; unattended-upgrades installs its updates).

`claude-sandbox` (or `claude`) runs it as its own user, `claude-agent`, which has no password and no
login and can't read your home folder, keys, passwords or browser profiles. It works in
`~/projects`, which you share with it through ACLs.

Your user may run exactly one thing as it, the script that starts Claude Code (`bin/claude-session`,
through a rule in `/etc/sudoers.d`), and a firewall rule matching only that user
(`data/claude-firewall.nft`, loaded at every boot) keeps it off this computer and your local
network: it can reach the internet, nothing else.

It gets its own ssh key and git identity, and Debian's git, ssh, ripgrep, jq, shellcheck and python
venv.

Because it can change any file in `~/projects`, your own git gets a guard there (`bin/git`) that
refuses a bare repository you did not name, and a repository whose `.git/config` or hooks could run
a program as you.

This is the lighter of the two Claude Code sandboxes: it shares your kernel; `extras/claude-vm.sh`
is the stronger.

Another account (a second Claude login: work and personal, say) gets a user of its own,
`claude-agent-NAME`, with its own home (login, settings, memories), ssh key, sudo rule and firewall
line, and its own folder, `~/projects-NAME`: no account can enter another's home or folder, the
first one's included.

## LIMITS

- Signing in: the sandboxed Firefox can't finish the link that comes back to this computer
  (`localhost`); its firewall is what stops it.

  Open the link printed in the terminal instead and paste the code it gives you (it says so before
  the first sign-in, and waits for Enter). `firefox-esr` works too, but runs as you.
- It shares your kernel: a kernel bug could let it out of its user.
- It reaches the internet, so what it reads in `~/projects` can leave this computer.
- Treat what it leaves in `~/projects` as untrusted before you run it; the git guard checks git's
  own files, not the code.
- `/usr/bin/git` skips the guard, and `claude-unsandboxed` has all your files.
- Accounts are kept apart by Linux users, on one kernel: the same kernel-bug limit applies between
  them. Anything you copy from one account's folder to another's crosses over.

## MANUAL INSTALL

```
# Anthropic's signing key. Check it is exactly the pinned one: this must
# print one "pub" key with the fingerprint @ANTHROPIC_FPR@
wget -O /tmp/claude-code.asc @ANTHROPIC_KEY_URL@
gpg --show-keys --with-fingerprint /tmp/claude-code.asc
sudo install -D -m 0644 /tmp/claude-code.asc /etc/apt/keyrings/claude-code.asc
rm /tmp/claude-code.asc
# The repository, trusted with that key only, and its updates installed by unattended-upgrades
echo "deb [signed-by=/etc/apt/keyrings/claude-code.asc] https://downloads.claude.ai/claude-code/apt/stable stable main" |
    sudo tee /etc/apt/sources.list.d/claude-code.list
echo 'Unattended-Upgrade::Origins-Pattern:: "site=downloads.claude.ai";' |
    sudo tee /etc/apt/apt.conf.d/52wren-claude-code

# Claude Code; acl for sharing ~/projects; nftables for the firewall rule; its tools
sudo apt update
sudo apt install --no-install-recommends claude-code acl nftables git openssh-client ripgrep jq shellcheck python3-venv

# The claude-agent user, locked (no password: nobody can log in as it)
sudo useradd --create-home --home-dir /home/claude-agent --shell /bin/bash --user-group --comment "Wren Linux Claude Code" claude-agent
sudo usermod --lock claude-agent
sudo chmod 700 /home/claude-agent
# Its notes on how it is set up, and its own git identity
sudo install -d -o claude-agent -g claude-agent -m 0700 /home/claude-agent/.claude
sudo install -o claude-agent -g claude-agent -m 0644 @WREN_DIR@/data/claude-agent-CLAUDE.md /home/claude-agent/.claude/CLAUDE.md
printf '[user]\n\tname = Claude\n\temail = noreply@anthropic.com\n[init]\n\tdefaultBranch = main\n[safe]\n\tdirectory = *\n' |
    sudo install -o claude-agent -g claude-agent -m 0644 /dev/stdin /home/claude-agent/.gitconfig
# Its own ssh key (no passphrase: it uses it by itself), and GitHub's host keys (pinned in pins.sh)
sudo install -d -o claude-agent -g claude-agent -m 0700 /home/claude-agent/.ssh
sudo -u claude-agent -H bash -c 'cd && ssh-keygen -q -t ed25519 -N "" -C "claude-agent@$(hostname)" -f .ssh/id_ed25519'
bash -c '. @WREN_DIR@/pins.sh; printf "%s\n" "$GITHUB_HOST_KEYS"' |
    sudo install -o claude-agent -g claude-agent -m 0644 /dev/stdin /home/claude-agent/.ssh/known_hosts

# The firewall rule: claude-agent reaches the internet only, not this
# computer or your network. Loaded at every boot before the network comes up.
sudo install -D -o root -g root -m 0644 @WREN_DIR@/data/claude-firewall.nft /etc/wren/claude.nft
printf '%s\n' '[Unit]' 'Description=Keep the claude-agent user off the local network' \
    'Before=network-pre.target' 'Wants=network-pre.target' '' '[Service]' \
    'Type=oneshot' 'RemainAfterExit=yes' 'ExecStart=/usr/sbin/nft -f /etc/wren/claude.nft' \
    'ExecStop=/usr/sbin/nft delete table inet wren_claude' '' '[Install]' 'WantedBy=multi-user.target' |
    sudo tee /etc/systemd/system/wren-claude-firewall.service
sudo systemctl daemon-reload
sudo systemctl enable --now wren-claude-firewall.service

# ~/projects, shared: it may pass through your home (not list or read it),
# and read and write in ~/projects; new files there are open to both of you
mkdir -p ~/projects
setfacl -m u:claude-agent:--x ~
setfacl -R -m "u:claude-agent:rwX,u:$(id -un):rwX" ~/projects
setfacl -R -d -m "u:claude-agent:rwX,u:$(id -un):rwX,m::rwX" ~/projects

# The script that starts Claude Code as claude-agent, and the wrapper it
# uses to keep it off X11's abstract socket
sudo install -d -o root -g root -m 0755 /usr/local/libexec
sudo install -o root -g root -m 0755 @WREN_DIR@/bin/claude-session /usr/local/libexec/claude-session
sudo install -o root -g root -m 0755 @WREN_DIR@/bin/no-abstract-sockets /usr/local/libexec/wren-no-abstract-sockets
# The check that its firewall really holds: it won't start without it, and ends if it goes
sudo install -o root -g root -m 0755 @WREN_DIR@/bin/sandbox-net-check /usr/local/libexec/wren-sandbox-net-check
# Your user may run that script, and nothing else, as claude-agent. visudo
# checks the rule first: never put a rule in /etc/sudoers.d it hasn't passed.
printf '%s ALL=(claude-agent) NOPASSWD: /usr/local/libexec/claude-session\n' "$(id -un)" >/tmp/wren-claude
sudo visudo -cf /tmp/wren-claude
sudo install -o root -g root -m 0440 /tmp/wren-claude /etc/sudoers.d/wren-claude
rm /tmp/wren-claude

# The commands, and the git guard for ~/projects
for c in claude claude-sandbox claude-unsandboxed claude-pull git; do install -D -m 0755 @WREN_DIR@/bin/$c ~/.local/bin/$c; done

# Its public key, to add on GitHub (a deploy key on one repository is the narrowest)
sudo cat /home/claude-agent/.ssh/id_ed25519.pub
cd ~/projects && mkdir -p NAME && cd NAME && claude
```

Another account, NAME (small letters and digits), after the steps above:

```
# Its user, locked, with its own home, notes, git identity and ssh key
sudo useradd --create-home --home-dir /home/claude-agent-NAME --shell /bin/bash --user-group --comment "Wren Linux Claude Code" claude-agent-NAME
sudo usermod --lock claude-agent-NAME && sudo chmod 700 /home/claude-agent-NAME
sudo install -d -o claude-agent-NAME -g claude-agent-NAME -m 0700 /home/claude-agent-NAME/.claude /home/claude-agent-NAME/.ssh
sed "s|~/projects|~/projects-NAME|g" @WREN_DIR@/data/claude-agent-CLAUDE.md | sudo install -o claude-agent-NAME -g claude-agent-NAME -m 0644 /dev/stdin /home/claude-agent-NAME/.claude/CLAUDE.md
sudo cp /home/claude-agent/.gitconfig /home/claude-agent-NAME/.gitconfig && sudo chown claude-agent-NAME: /home/claude-agent-NAME/.gitconfig
sudo -u claude-agent-NAME -H bash -c 'cd && ssh-keygen -q -t ed25519 -N "" -C "$(id -un)@$(hostname)" -f .ssh/id_ed25519'
# Its line in the firewall rule, by number (nft refuses the whole file over a
# user name that doesn't exist): below the claude-agent line in
# /etc/wren/claude.nft add, with the number from: id -u claude-agent-NAME
#         meta skuid NUMBER jump claude  # claude-agent-NAME
sudo nft -c -f /etc/wren/claude.nft && sudo systemctl restart wren-claude-firewall
# Its folder, shared with you only
mkdir -p ~/projects-NAME
setfacl -m u:claude-agent-NAME:--x ~
setfacl -R -m "u:claude-agent-NAME:rwX,u:$(id -un):rwX" ~/projects-NAME
setfacl -R -d -m "u:claude-agent-NAME:rwX,u:$(id -un):rwX,m::rwX" ~/projects-NAME
# Your user may run the start script, and nothing else, as it (checked first)
printf '%s ALL=(claude-agent-NAME) NOPASSWD: /usr/local/libexec/claude-session\n' "$(id -un)" >/tmp/wren-claude-NAME
sudo visudo -cf /tmp/wren-claude-NAME && sudo install -o root -g root -m 0440 /tmp/wren-claude-NAME /etc/sudoers.d/wren-claude-NAME
rm /tmp/wren-claude-NAME
cd ~/projects-NAME && mkdir -p X && cd X && claude --account NAME
```

To undo an account: `sudo rm /etc/sudoers.d/wren-claude-NAME`, its `setfacl -x` on `~` and
`~/projects-NAME` (as below, with its user name), `sudo pkill -KILL -u claude-agent-NAME`,
`sudo userdel -r claude-agent-NAME`, then its line out of `/etc/wren/claude.nft` and
`sudo systemctl restart wren-claude-firewall`. `~/projects-NAME` stays.

To undo:

```
# The commands and the git guard (keep claude-pull and claude-share if claude-vm is set up)
rm ~/.local/bin/claude ~/.local/bin/claude-unsandboxed ~/.local/bin/claude-pull ~/.local/bin/claude-share ~/.local/bin/git
# The firewall rule
sudo systemctl disable --now wren-claude-firewall.service
sudo rm /etc/systemd/system/wren-claude-firewall.service /etc/wren/claude.nft
sudo systemctl daemon-reload
# The sudo rule and the start script (the no-abstract-sockets wrapper and the firewall check only if
# incognito, claude-vm and the Firefox sandbox don't use it)
sudo rm /etc/sudoers.d/wren-claude /usr/local/libexec/claude-session
sudo rm /usr/local/libexec/wren-no-abstract-sockets
sudo rm /usr/local/libexec/wren-sandbox-net-check
# Its access to your home and ~/projects
setfacl -x u:claude-agent ~
setfacl -R -x "u:claude-agent,d:u:claude-agent" ~/projects
# The user and its home (its Claude login, ssh key and settings); what it
# made in ~/projects becomes yours first
sudo pkill -KILL -u claude-agent
sudo find ~/projects -user claude-agent -exec chown -h "$(id -un):$(id -gn)" {} +
sudo userdel -r claude-agent
# Claude Code, its repository, key and update rule
sudo apt purge claude-code
sudo rm /etc/apt/sources.list.d/claude-code.list /etc/apt/keyrings/claude-code.asc /etc/apt/apt.conf.d/52wren-claude-code
# The tools, marked "automatic": autoremove takes them out only if nothing needs them
sudo apt-mark auto acl nftables ripgrep jq shellcheck python3-venv
sudo apt autoremove --purge
```
