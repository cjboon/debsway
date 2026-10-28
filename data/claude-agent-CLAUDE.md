<!-- Written by debsway extras/claude-code.sh. Delete this line to keep your own edits. -->
# How this machine is set up

You run as the user `claude-agent`, not as the person you are working for.
That is deliberate: it keeps their files and keys out of your reach.

- Work in `~/projects/` on their machine (the folder you were started in). You
  can read and write there, and nowhere else of theirs. You have no sudo.
  Don't try to get around that; if you need something outside it, say so.
- Your own home is `/home/claude-agent`. Your ssh key is `~/.ssh/id_ed25519`
  and your git identity is in `~/.gitconfig`; you have none of theirs. The
  person has to add your public key on the host (GitHub, say) before you can
  push: ask them, and prefer a deploy key on a single repository.
- You have git, ssh, ripgrep, jq, shellcheck and python3 with venv. You can't
  install packages; things you install in your home (a Python venv, `pip
  install --user`) are fine, and `~/.local/bin` is on your PATH.
- You can reach the internet, but not the local network or servers running on
  this machine, localhost included. A refused connection to `localhost` or a
  `192.168.x.x` address is the firewall, not a bug.
- Files you create in `~/projects` are owned by `claude-agent`; the person can
  read and change them.
- **git:** you can change `.git/config` and `.git/hooks` in any repository in
  `~/projects`, and the person's own git would run what is in them as them.
  So their git checks both before every command, and refuses to run if it
  finds a hook, or a setting that can run a program (`core.fsmonitor`,
  `alias.*`, `core.sshCommand`, `credential.helper`, `filter.*`, `url.*.insteadOf`,
  an unusual remote address...). Don't add any of those to a repository there.
  If they tell you git refused ("not running here"), explain what it found and
  offer to remove it. Never suggest switching the check off, and never
  suggest `safe.directory '*'`.
- **How your work reaches them:** keep your own clone in `~/projects/NAME`,
  commit and push there (run the project's tests first). Their copy lives
  outside `~/projects`, where you can't reach it, and they bring your work in
  with `claude-pull`, which shows your commits and asks before it merges.
  Don't suggest pulling automatically, git hooks, or making their `.git`
  writable for you: each would let your changes run as them unread.
- They run what you write in `~/projects` as themselves, so keep scripts
  short and readable, and say plainly what a script does before they run it,
  above all anything that uses sudo, deletes files, or touches ssh keys.
