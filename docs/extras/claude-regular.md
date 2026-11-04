# Claude Code as you (`extras/claude-regular.sh`)

## SYNOPSIS

```
wrenctl install claude-regular                         install it, with its sandbox on
wrenctl remove claude-regular                          remove it (your Claude login and settings stay)
wrenctl manual claude-regular                          print the manual steps below
wrenctl install claude-regular --account NAME          another account (its own login and memories)
wrenctl install claude-regular --remove-account NAME   take it out (asks before deleting its login)

cd ~/code/project && claude-regular   Claude Code as you, in that folder
claude                                the same; asks which if you set up more than one
claude-regular --account NAME         that account, its settings in ~/.claude-NAME
/sandbox                              inside Claude Code: see or change its sandbox
```

Claude Code as your own user, set up to be easy and still careful: it works
in any folder you start it from, with your tools, without the walls of the
sandboxed `claude` (its own user, `extras/claude-code.sh`) or `claude-vm` (a
VM). It comes from Anthropic's signed apt repository, whose key must be
exactly `ANTHROPIC_FPR` in `pins.sh`, shared with `extras/claude-code.sh`, so
removing one keeps the other's updates; unattended-upgrades updates it.
Claude Code's own sandbox is turned on: the shell commands it runs go through
bubblewrap, may write only in the folder you started it in (and a temp
folder), and can't read your ssh and gpg keys, passwords, keyring, browser
profiles or wallets; sandboxed commands run without asking each time. Its
file tools are kept from the same files, and from changing what runs at login
(`~/.profile`, sway's config, systemd units, `~/.local/bin`), and it may not
run sudo. These settings go into your `~/.claude/settings.json` next to your
own (`data/claude-regular-settings.json`, merged by `lib/claude-settings.py`),
and `--remove` takes out only what it added. Another account gets its own
settings folder, `~/.claude-NAME` (Claude Code's `CLAUDE_CONFIG_DIR`), with
the same settings, and rules keeping its file tools and sandboxed commands
out of `~/.claude`, and the first account's out of `~/.claude-NAME`.

## LIMITS

- Signing in: the sandboxed Firefox can't finish the link that comes back to this computer (`localhost`); its firewall is what stops it. Open the link printed in the terminal instead and paste the code it gives you. `firefox-esr` works too, but runs as you.
- It runs as you: anything its sandbox and rules don't name (your documents, other projects) it can read, and what it reads can go to the internet.
- Claude Code enforces these rules itself; you can turn them off in it (`/sandbox`, `/permissions`), and a bug in it could miss one.
- A command it can't run in the sandbox may be retried outside it, after asking you: read what you approve.
- Treat what it writes in your project as untrusted until you've read it.
- Accounts aren't walled off: both run as you, Claude Code's own rules are all that keeps each out of the other's folder, and two extra accounts aren't kept from each other. For a wall, use the sandboxed `claude --account` or `claude-vm --account`.

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

# Claude Code; bubblewrap and socat for its sandbox; git and ripgrep; python3 for the merge
sudo apt update
sudo apt install --no-install-recommends claude-code bubblewrap socat git ripgrep python3
# The claude-regular command
install -D -m 0755 @WREN_DIR@/bin/claude-regular ~/.local/bin/claude-regular
install -D -m 0755 @WREN_DIR@/bin/claude ~/.local/bin/claude

# Its sandbox on, and the rules, merged into your own settings (and what was
# added remembered, for the undo below)
python3 -I @WREN_DIR@/lib/claude-settings.py add ~/.claude/settings.json \
    @WREN_DIR@/data/claude-regular-settings.json ~/.local/state/wren/claude-regular-settings.json
# They are there: this shows "sandbox" and "permissions"
cat ~/.claude/settings.json
cd ~/code/project && claude-regular
```

Another account, NAME: `mkdir -m 700 ~/.claude-NAME`, the same `add` into
`~/.claude-NAME/settings.json` (with its own state file), then add
`"Read(~/.claude/**)"`, `"Edit(~/.claude/**)"` to its `permissions.deny` and
`"~/.claude"` to its `sandbox.filesystem.denyRead`, and the same three for
`~/.claude-NAME` to `~/.claude/settings.json`. Run it with
`CLAUDE_CONFIG_DIR=~/.claude-NAME claude` (what `claude-regular --account NAME`
does). This also works for a Claude Code installed without Wren Linux.

To undo (your Claude login and settings stay in `~/.claude`):

```
# Take out only the settings Wren Linux added
python3 -I @WREN_DIR@/lib/claude-settings.py remove ~/.claude/settings.json \
    @WREN_DIR@/data/claude-regular-settings.json ~/.local/state/wren/claude-regular-settings.json
# The command
rm ~/.local/bin/claude-regular
# (the claude command only if no other Claude Code is set up)
rm ~/.local/bin/claude
# Only if the sandboxed claude (extras/claude-code.sh) isn't set up: Claude
# Code, its repository, key and update rule
sudo apt purge claude-code
sudo rm /etc/apt/sources.list.d/claude-code.list /etc/apt/keyrings/claude-code.asc /etc/apt/apt.conf.d/52wren-claude-code
# The tools, marked "automatic": autoremove takes them out only if nothing needs them
sudo apt-mark auto bubblewrap socat ripgrep
sudo apt autoremove --purge
```
