# Claude Code in its own user (`extras/claude-code.sh`)

You get Claude Code, Anthropic's coding assistant for the terminal, installed from Anthropic's signed apt repository. The `claude` command runs it as a separate Linux user, `claude-agent`, which has no password and cannot read your home folder, ssh keys, passwords or browser profiles. It works in `~/projects`, which you share with it, and a firewall rule keeps it off your local network.

## The problem it solves

A coding assistant reads files, writes files and runs commands. That is its job, and it is also a risk: it can be misled by text it reads, or simply make a mistake. If it runs as you, a mistake or a trick can touch everything you own, including your ssh keys and password database.

This extra gives it a smaller space to work in. It does not make the assistant trustworthy. It limits what a mistake can reach.

## The ideas behind it

**A Linux user.** Each account on a Linux computer is a user, and files have owners. A program running as another user cannot read your private files. Normally every program you start runs as you.

**A locked user.** `claude-agent` has no password, so nobody can log in as it. It exists to own its own files and run one program.

**sudo and a sudoers rule.** `sudo` lets one user run a command as another. A sudoers rule, a line in `/etc/sudoers.d/debsway-claude`, says who may run what. This one lets your user run exactly one script as `claude-agent`, without a password. It is checked with `visudo` first, because a broken sudoers file can lock you out of sudo.

**A sandbox.** A box around a program that limits what it can touch. This is the lighter of debsway's two Claude Code sandboxes: it shares your computer's kernel (the core of the operating system). `extras/claude-vm.sh` is the stronger one and puts the assistant in a virtual machine; see `docs/extras/claude-vm.md`.

**An ACL.** An access-control list adds a permission for one named user on a file or folder. It lets `claude-agent` walk through your home folder to `~/projects` without being able to list or read anything else there.

**A firewall rule.** An instruction to the network layer to allow or refuse certain connections. This one applies only to `claude-agent`.

**A git hook.** Git can run a program automatically at certain moments (a hook), and some settings can name programs to run. Since `claude-agent` can edit any repository in `~/projects`, including the hidden `.git` folder, it could plant something that your own git would run as you.

**An ssh key.** A pair of files used to prove who you are to a server such as GitHub. The public half is shared, the private half stays secret.

## How it works, step by step

When you run `bash extras/claude-code.sh`:

1. It adds Anthropic's apt repository. The signing key is fetched and used only if its fingerprint is exactly the one pinned in `pins.sh`. It also allows unattended-upgrades to install updates from `downloads.claude.ai`.
2. It installs `claude-code`, `acl`, `nftables`, `git`, `openssh-client`, `ripgrep`, `jq`, `shellcheck` and `python3-venv`.
3. It creates the user `claude-agent` (home `/home/claude-agent`, mode 700, own group only) and locks its password.
4. It gives it `~/.claude/CLAUDE.md` (from `data/claude-agent-CLAUDE.md`, a note telling the assistant how it is set up) and a `~/.gitconfig` (name Claude, email noreply@anthropic.com, `safe.directory = *`). Files you have edited yourself are kept: it only overwrites those that still carry the "written by debsway" mark.
5. It makes an ssh key for the agent with no passphrase, so the agent can use it by itself. It also writes GitHub's published host keys into its `known_hosts`, fetched over https from `api.github.com/meta`.
6. It installs the firewall rule `/etc/debsway/claude.nft` and the service `debsway-claude-firewall`, loaded at every boot. For `claude-agent` it accepts DNS and the internet, and rejects connections to this computer itself and to private address ranges.
7. It creates `~/projects` and uses ACLs so `claude-agent` can pass through your home folder, and read and write `~/projects`, including files created later. You keep access to what it creates.
8. It installs `/usr/local/libexec/claude-session`, `debsway-no-abstract-sockets`, the sudoers rule, and the commands `claude`, `claude-unsandboxed`, `claude-pull` and `git` in `~/.local/bin`. It prints the agent's public ssh key.

When you run `claude`:

1. It checks that the sandbox is set up and that you are in a folder inside `~/projects`. Elsewhere it refuses (only `--version` and `--help` work anywhere).
2. It runs `claude-session` as `claude-agent` through sudo, in that folder. That script sets a clean `HOME` and `PATH`, and starts Claude Code through `debsway-no-abstract-sockets`, which uses the kernel's Landlock feature to stop the program connecting to X11's "abstract" sockets that any user could otherwise reach.
3. The first time, Claude Code shows a login link; open it in your browser. The login lives in `/home/claude-agent`, apart from your own `~/.claude`.

**The git guard.** `bin/git` is installed as your `git` in `~/.local/bin`. Inside `~/projects`, before git runs, it reads the repository's `.git/config` and `.git/hooks`. It accepts only a list of harmless settings (user name, remotes with ordinary addresses, branch tracking and so on) and refuses if it finds a hook or any other setting, such as `core.fsmonitor`. It then tells you what it found. When the check passes for a repository the agent made, it tells git to trust that one for that one command, so you do not get git's "dubious ownership" warning. Outside `~/projects` it is plain git; `/usr/bin/git` skips the guard.

**Getting its work.** `claude-pull`, run in your own copy of a repository, fetches what the agent pushed, shows the commits, and asks `Bring these in? [y/N]` before merging (fast-forward only).

## What it changes on your computer

- The apt repository file `/etc/apt/sources.list.d/claude-code.list`, the key `/etc/apt/keyrings/claude-code.asc`, and `/etc/apt/apt.conf.d/52debsway-claude-code`.
- Packages: `claude-code`, `acl`, `nftables`, `git`, `openssh-client`, `ripgrep`, `jq`, `shellcheck`, `python3-venv`.
- The user `claude-agent` and `/home/claude-agent` (its `.claude`, `.gitconfig`, `.ssh`).
- `/etc/sudoers.d/debsway-claude`; `/usr/local/libexec/claude-session` and `debsway-no-abstract-sockets`.
- `/etc/debsway/claude.nft` and `/etc/systemd/system/debsway-claude-firewall.service`.
- ACL entries for `claude-agent` on your home folder (pass through only) and on `~/projects`.
- `~/projects` if it did not exist.
- Commands in `~/.local/bin`: `claude`, `claude-unsandboxed`, `claude-pull`, `git`.

## Using it

- `cd ~/projects/NAME && claude`: Claude Code as `claude-agent`. Use `mkdir` for a new project.
- `claude-unsandboxed`: Claude Code as you, with all your files. No protection.
- `claude-pull`: in your own clone, show and (if you answer y) bring in what Claude pushed.
- Add the printed public key (or `sudo cat /home/claude-agent/.ssh/id_ed25519.pub`) on GitHub so the agent can push. A deploy key on one repository is the narrowest; a key on your account lets it push to all of them.
- The note at the top of `/etc/debsway/claude.nft` says how to let it reach servers on this machine. By default it cannot, including its own dev servers.
- The agent has no sudo and cannot install packages. Add Node, Rust or Go with apt yourself.

## What it protects against

- **Reading your private files.** It cannot read your home folder, ssh keys, passwords or browser profiles.
- **Reaching things on your network.** Your router, printers, other computers and programs listening on this machine are refused.
- **Using your ssh identity.** It has its own key and git identity.
- **Snooping on X11 windows** through the abstract socket.
- **Planted git settings or hooks running as you** in `~/projects`, because of the git guard.

## What it doesn't protect against

- **A kernel bug.** It shares your kernel. If this computer has KVM, `claude-vm` is the stronger wall.
- **Anything in `~/projects`.** You share it both ways. Read scripts it leaves before you run them, and look at `.git/config` and `.git/hooks` before telling your own git to trust a repository. Do not set git's `safe.directory '*'` for yourself.
- **The internet.** It can still send anything it can read to anywhere online.
- **A race against the guard.** A file could change between the check and the git command, so the guard stops a confused assistant, not one racing your keystrokes.
- **`claude-unsandboxed` and `/usr/bin/git`**, which skip the protections.
- **Files readable by every user.** `claude-agent` is an ordinary user.
- **A bad idea carried out with its own access.** If it deletes things in `~/projects`, they are gone.

## Removing it

`bash extras/claude-code.sh --remove` removes the commands, the firewall service and rule, the sudoers rule and the session script, takes back the ACL entries on your home folder and `~/projects`, and asks whether to delete the user `claude-agent` and its home (its Claude login, ssh keys and settings); the default is no. If you say yes, files it made in `~/projects` are handed to you first. It then purges the packages it installed (unless another extra needs them), the apt repository file and key, and the update rule. `claude-pull` stays if `claude-vm` is still set up. Your own `~/.claude` and `~/projects` are untouched.
