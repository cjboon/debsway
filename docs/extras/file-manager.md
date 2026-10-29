# Thunar, a file manager (`extras/file-manager.sh`)

You get Thunar, a light graphical program for browsing, copying and deleting files and folders, with a Trash and picture thumbnails. It becomes the program that opens folders.

## The problem it solves

sway has no built-in file browser. Without one, you work in the terminal with commands like `ls` and `cp`. Thunar gives you windows and icons, and also catches "open containing folder" in Firefox.

## The ideas behind it

**A file manager** shows folders as windows you click through, like the Finder on a Mac or Explorer on Windows. **The Trash** is a holding folder, so a deleted file can be brought back. **Thumbnails** are small previews of images. In this setup, `gvfs` provides the Trash and `tumbler` draws the thumbnails. Thunar is a GTK program, so it runs directly on Wayland, sway's window system.

USB sticks are already mounted by `udiskie` (`extras/udiskie.sh`), so Thunar does not need its own volume manager.

## How it works, step by step

1. `apt_install thunar gvfs tumbler` installs three packages under the marker package `debsway-file-manager`.
2. `set_default_app thunar.desktop inode/directory` writes a line into `~/.config/mimeapps.list`. That file records which program opens which kind of file, and `inode/directory` is the type "folder".
3. It prints a short list of keys.

## What it changes on your computer

- Packages: `thunar`, `gvfs`, `tumbler` and their dependencies.
- `~/.config/mimeapps.list`: `inode/directory=thunar.desktop`.
- Nothing in `~/.local/bin`, and no sway key bindings.

## Using it

- `thunar`: open your home folder (or Super+d, then `thunar`).
- `thunar ~/Downloads`: open a given folder.
- Ctrl+L: type a path. Ctrl+H: show hidden files. Ctrl+T: new tab.
- F2: rename. Delete: move to Trash. Shift+Delete: delete for good.
- Alt+Up: parent folder. Ctrl+1, 2, 3: icon, list or compact view.

## What it protects against

Nothing. It is a convenience. One safety detail is that Delete moves files to the Trash rather than erasing them. Shift+Delete erases them for good.

## What it doesn't protect against

- **Anything running as you.** Thunar runs as you with all your files. It adds no isolation.
- **Thumbnails of untrusted files.** `tumbler` reads image and document files to draw previews, so opening a folder holding files you do not trust makes a program parse them. debsway does not sandbox it. This is general, not something the script claims to fix.
- **Secure erasure.** Emptying the Trash does not make the data unrecoverable.
- **Untrusted USB sticks.** `THREAT-MODEL.md` says to avoid plugging in sticks you do not trust.

## Removing it

`bash extras/file-manager.sh --remove` removes `thunar` and `tumbler` (and, through the marker package, `gvfs` and anything else only this script needed), and deletes the lines in `~/.config/mimeapps.list` that point at `thunar.desktop`. Your files are untouched.
