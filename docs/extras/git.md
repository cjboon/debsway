# git (`extras/git.sh`)

## SYNOPSIS

```
wrenctl install git                     install git
wrenctl remove git                      remove git (~/.gitconfig stays)
wrenctl manual git                      print the manual steps below

git clone URL / git status / git commit -a / git push
wrenctl git [DIR]                       your name and email, and pushing to GitHub over ssh (DIR, or the repository you are in)
```

git keeps the history of a folder of files; it comes from Debian. The script installs it and makes
`main` the first branch of new repositories. It asks nothing else: your name and email on commits,
and how you push, are `git-helper.sh`'s, run when you want them (`wrenctl git`).

That asks for your name and email (and, for GitHub, offers your no-reply address, looked up from
your public profile, since GitHub refuses pushes that carry an email you keep private). Then, for a
GitHub repository, it sets up pushing over ssh with a key of your own, made for GitHub alone: on a
security key if one is plugged in (each push then wants a touch), otherwise a key file with a
passphrase that ssh asks for at every push, since no ssh-agent is allowed to hold it. GitHub's host
keys come from `pins.sh`, in a file of their own, checked strictly. You add the public key to your
GitHub account once; it tests the key before it changes anything, and only the push address
changes: fetching stays on the public address, so updates need no key. No token is made, asked for
or kept, and the https logins of earlier versions are offered for removal.

GitHub can take two things only on its website, once each: your ssh key (Settings, SSH and GPG keys,
New SSH key), and the rules that keep a repository's main branch yours. For those: the repository's
Settings, Rules, Rulesets, New branch ruleset; Enforcement active; Target branches: Include default
branch; Bypass list: Repository admin; and Restrict updates, Restrict deletions and Block force
pushes ticked. Only you update main then, and nobody force-pushes or deletes it.

## LIMITS

- A repository you clone can hold scripts and build files: read what you download before you run it.
- Your name and email on a commit are no proof of who made it.
- Anything you push to a public site is public, and history keeps it after you delete the file.
- An ssh key on your GitHub account can push to every repository of yours, not only this one. A
  key file is as safe as its passphrase: a program running as you could catch it as it goes to ssh.
  A security key wants a touch for each push, which no program can give.

## MANUAL INSTALL

```
# git
sudo apt install --no-install-recommends git
# New repositories start on a branch called main
git config --global init.defaultBranch main
```

What `git-helper.sh` then sets, by hand:

```
# The name and email on your commits (for GitHub, your no-reply address,
# NUMBER+NAME@users.noreply.github.com, under github.com/settings/emails)
git config --global user.name "Your Name"
git config --global user.email "you@example.org"
# A key for GitHub alone: on a security key (ed25519-sk), or a file with a passphrase
ssh-keygen -t ed25519 -C wren-github -f ~/.ssh/id_wren_github
# GitHub's host keys, from GITHUB_HOST_KEYS in pins.sh
cat >~/.ssh/known_hosts_github <<'EOF'
@GITHUB_HOST_KEYS@
EOF
# At the top of ~/.ssh/config:
#   Host github.com
#       HostName github.com
#       User git
#       IdentityFile ~/.ssh/id_wren_github
#       IdentitiesOnly yes
#       IdentityAgent none
#       AddKeysToAgent no
#       UserKnownHostsFile ~/.ssh/known_hosts_github
#       StrictHostKeyChecking yes
# Add ~/.ssh/id_wren_github.pub on GitHub (Settings, SSH and GPG keys), then check:
ssh -T git@github.com
# Push over ssh; fetch from the public address as before
git remote set-url --push origin git@github.com:OWNER/REPO.git
```

To undo (your settings stay in `~/.gitconfig`):

```
# git is marked "automatic" instead of purged, since other programs can need
# it: autoremove takes it out only if nothing does
sudo apt-mark auto git
sudo apt autoremove --purge
```
