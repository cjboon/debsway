# git, to track changes to files (`extras/git.sh`)

You get `git`, the tool most programmers use to keep a history of their work, and optionally `gh`, GitHub's command line tool. The script also asks for the name and email to put on your commits and, if you want, logs you in to GitHub.

## The problem it solves

Without a tool like git, you copy files by hand ("report-final-2") to keep older versions, and you have no easy way to share work with others. git does this properly, and downloading code from sites such as GitHub needs it.

## The ideas behind it

**git** keeps a history of a folder. Each time you save a snapshot, called a **commit**, it records what changed, who changed it and when. You can go back to any snapshot. A folder tracked this way is a **repository**.

**Your name and email** are written into each commit as its author. They are only labels. Nobody checks them.

**A branch** is a separate line of work inside the same repository. The default one here is called `main`.

**GitHub** is a website that stores repositories and lets people share them. **gh** is its command line tool, for things like logging in.

**Logging in** with `gh auth login` shows a short code to enter at `github.com/login/device`, so you approve the login in a browser.

## How it works, step by step

1. `apt_install git`, plus `gh` if you say yes to "Also install gh?". The packages are recorded under the marker package `debsway-git`.
2. If git has no `user.name` yet, it asks for one (Enter skips). It does the same for `user.email`. If they are already set, it leaves them alone.
3. It runs `git config --global init.defaultBranch main`, so new repositories start on `main`. It does this every time, even if you had set something else.
4. If `gh` is installed and you are not logged in, it asks whether to log in now. If yes, it runs `gh auth login --hostname github.com --git-protocol https` and `gh auth setup-git`, so git can use that login for GitHub over HTTPS. If no, it prints the commands for later.

## What it changes on your computer

- Packages: `git`, and `gh` if you chose it.
- `~/.gitconfig`: your name, your email and `init.defaultBranch`.
- If you log in: `gh` settings in `~/.config/gh`, and a git setting that lets git use `gh` for GitHub.
- Nothing in `~/.local/bin` or the sway config.

## Using it

- `git init`: start tracking the current folder.
- `git add FILE` then `git commit -m "message"`: save a snapshot.
- `git status` and `git log`: see what changed and the history.
- `git clone URL`: download a repository.
- `gh auth login`: log in to GitHub later.

## What it protects against

Mainly a convenience. It installs a standard tool and writes your name and email once. It protects nothing by itself.

One real safety detail concerns `~/projects`. `extras/claude-code.sh`, not this script, installs a guard (`bin/git`) that runs in front of your git inside `~/projects`. It refuses to run in a repository whose `.git/config` or `.git/hooks` could run a program as you. A hook is a script git runs at certain moments. If you did not install that extra, you do not have the guard.

## What it doesn't protect against

- **Untrusted repositories.** A repository you clone can contain scripts and build files. Read what you download before you run it.
- **The guard being bypassed.** `/usr/bin/git` skips it. A file could also change between the guard's check and the run (`bin/git` says so).
- **Wrong labels.** Your name and email on commits are not proof of who made them.
- **Leaked secrets.** Anything you commit and push to a public site is public. History keeps it, even if you delete the file later.
- **Anything running as you**, which can read your GitHub login in `~/.config/gh`.

## Removing it

`bash extras/git.sh --remove` removes `gh` and `git` (and what only they needed). Your settings stay in `~/.gitconfig` and `~/.config/gh`, and your repositories are untouched.
