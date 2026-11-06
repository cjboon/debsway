# git (`extras/git.sh`)

## SYNOPSIS

```
wrenctl install git                     install git
wrenctl remove git                      remove git (~/.gitconfig stays)
wrenctl manual git                      print the manual steps below

git clone URL / git status / git commit -a / git push
wrenctl git [DIR]                       your name, email and push login (DIR, or the repository you are in)
wrenctl gh rulesets [OWNER/REPO]        on GitHub: only you update main, nobody force-pushes or deletes it
```

git keeps the history of a folder of files; it comes from Debian. It also offers GitHub's command
line tool, gh, from Debian (Enter means yes). gh is only installed then, and stays logged out: git
needs no more than a token to push, and logging in is yours to choose, with `wrenctl gh`.

The script installs git and makes `main` the first branch of new repositories. It asks nothing else:
your name and email on commits, and how git logs in to push, are `git-helper.sh`'s, run when you
want them (`wrenctl git`).

It asks for your name and email (and, for GitHub, offers your no-reply address, looked up from your
public profile, since GitHub refuses pushes that carry an email you keep private), then how git logs
in over https: a token you paste at each push (nothing saved), the same kept in memory for an hour,
or, if you installed gh, gh's login through a web page (saved in plain text).

`wrenctl git DIR`, or `wrenctl git` inside a repository, does this for any repository of yours, on
any server. `wrenctl gh` (`gh-helper.sh`) installs gh, from Debian, when you want it, with a
fine-grained token you make for the job: nothing is saved unless you say so.

`wrenctl gh rulesets` gives a GitHub repository's main branch the rules that keep it yours: only you
(its admins) update it, so a deploy key you gave a helper can push its own branch and never main,
and nobody force-pushes or deletes it.

The token for that needs Administration, Read and write, on that repository alone; made for this, a
day's expiry is enough, and it is asked for hidden and not saved.

## LIMITS

- A repository you clone can hold scripts and build files: read what you download before you run it.
- Your name and email on a commit are no proof of who made it.
- Anything you push to a public site is public, and history keeps it after you delete the file.
- Anything running as you can read gh's GitHub login in `~/.config/gh`, if you installed gh and
  chose it. A token kept in memory can be read by a program of yours in that hour; one pasted at
  each push is in no file, but in whatever you copy it from.

## MANUAL INSTALL

```
# git
sudo apt install --no-install-recommends git
# GitHub's gh, if you like (it stays logged out until you log it in: wrenctl gh)
sudo apt install --no-install-recommends gh
# New repositories start on a branch called main
git config --global init.defaultBranch main
```

What `git-helper.sh` then sets, by hand:

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
# ...or, with gh installed by you, its login instead (saved in plain text in
# ~/.config/gh)
gh auth login --hostname github.com --git-protocol https
gh auth setup-git
```

To undo (your settings stay in `~/.gitconfig`):

```
# git is marked "automatic" instead of purged, since other programs can need
# it: autoremove takes it out only if nothing does
sudo apt-mark auto git gh
sudo apt autoremove --purge
```
