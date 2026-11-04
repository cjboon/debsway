# git and gh (`extras/git.sh`)

## SYNOPSIS

```
wrenctl install git                     install git (it asks about gh)
wrenctl remove git                      remove git and gh (~/.gitconfig and ~/.config/gh stay)
wrenctl manual git                      print the manual steps below

git clone URL / git status / git commit -a / git push
bash git-init.sh [DIR]   (in Wren Linux's folder) your name, email and push login; DIR: any repository
```

git keeps the history of a folder of files, and gh is GitHub's command line
tool; both come from Debian. The script installs git, offers gh, and makes
`main` the first branch of new repositories. It asks nothing else: your name
and email on commits, and how git logs in to push, are `git-init.sh`'s, run
when you want them. It asks for your name and email (and, for GitHub, offers
your no-reply address, looked up from your public profile, since GitHub
refuses pushes that carry an email you keep private), then how git logs in
over https: a token you paste at each push (nothing saved), the same kept in
memory for an hour, or gh's login through a web page (saved in plain text).
`bash git-init.sh DIR` does this for any repository of yours, on any server.

## LIMITS

- A repository you clone can hold scripts and build files: read what you download before you run it.
- Your name and email on a commit are no proof of who made it.
- Anything you push to a public site is public, and history keeps it after you delete the file.
- Anything running as you can read gh's GitHub login in `~/.config/gh`, if you chose it. A token kept in memory can be read by a program of yours in that hour; one pasted at each push is in no file, but in whatever you copy it from.

## MANUAL INSTALL

```
# git (add gh for GitHub's command line tool)
sudo apt install --no-install-recommends git gh
# New repositories start on a branch called main
git config --global init.defaultBranch main
```

What `git-init.sh` then sets, by hand:

```
# The name and email on your commits (for GitHub, your no-reply address,
# NUMBER+NAME@users.noreply.github.com, under github.com/settings/emails)
git config --global user.name "Your Name"
git config --global user.email "you@example.org"
# Log in with a token pasted at each push: no helper but git's own, and your
# user name (a token: github.com/settings/personal-access-tokens/new)
git config --global --replace-all credential.https://github.com.helper ''
git config --global credential.https://github.com.username NAME
# ...or kept in memory for an hour after you paste it:
git config --global --add credential.https://github.com.helper 'cache --timeout=3600'
# ...or gh's login instead (saved in plain text in ~/.config/gh)
gh auth login --hostname github.com --git-protocol https
gh auth setup-git
```

To undo (your settings stay in `~/.gitconfig` and `~/.config/gh`):

```
# Log out of GitHub first, if you logged in
gh auth logout
# gh; git is marked "automatic" instead of purged, since other programs can
# need it: autoremove takes it out only if nothing does
sudo apt purge gh
sudo apt-mark auto git
sudo apt autoremove --purge
```
