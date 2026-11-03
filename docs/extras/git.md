# git and gh (`extras/git.sh`)

## SYNOPSIS

```
debsway install git                     install git (it asks about gh, your name and email)
debsway remove git                      remove git and gh (~/.gitconfig and ~/.config/gh stay)
debsway manual git                      print the manual steps below

git clone URL / git status / git commit -a / git push
gh auth login && gh auth setup-git      log in to GitHub later
```

git keeps the history of a folder of files, and gh is GitHub's command line
tool; both come from Debian. The script installs git, offers gh, asks for the
name and email to put on your commits (Enter skips each), makes `main` the
first branch of new repositories, and, with gh, offers to log in to GitHub (it
shows a code to enter at github.com/login/device).

## LIMITS

- A repository you clone can hold scripts and build files: read what you download before you run it.
- Your name and email on a commit are no proof of who made it.
- Anything you push to a public site is public, and history keeps it after you delete the file.
- Anything running as you can read your GitHub login in `~/.config/gh`.

## MANUAL INSTALL

```
# git (add gh for GitHub's command line tool)
sudo apt install --no-install-recommends git gh
# The name and email on your commits
git config --global user.name "Your Name"
git config --global user.email "you@example.org"
# New repositories start on a branch called main
git config --global init.defaultBranch main
# With gh: log in to GitHub, and let git use that login for https
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
