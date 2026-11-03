# Thunar file manager (`extras/file-manager.sh`)

## SYNOPSIS

```
debsway install file-manager                     install it
debsway remove file-manager                      remove it
debsway manual file-manager                      print the manual steps below

thunar                 open your home folder (or Super+d, then thunar)
thunar ~/Downloads     open a folder
  Ctrl+L type a path   Ctrl+H hidden files   Ctrl+T new tab   F2 rename
  Delete to Trash   Shift+Delete delete for good   Alt+Up parent folder
```

Thunar is a light graphical file manager from Xfce, from Debian. It is GTK, so
it runs natively on Wayland. gvfs gives it the Trash, and tumbler draws
thumbnails. It is made the default for folders, so "open containing folder" in
Firefox opens it. USB drives are mounted by udiskie (`extras/udiskie.sh`), so
Thunar's own volume manager isn't needed.

## LIMITS

- It runs as you with all your files; it adds no isolation.
- tumbler reads the files in a folder you open to draw previews, unsandboxed: be careful opening folders of files you don't trust.
- Emptying the Trash doesn't make the data unrecoverable.

## MANUAL INSTALL

```
# Thunar, the Trash (gvfs) and thumbnails (tumbler)
sudo apt install --no-install-recommends thunar gvfs tumbler
# Make it the default for folders (in ~/.config/mimeapps.list, under
# [Default Applications], replacing an older default)
mkdir -p ~/.config && touch ~/.config/mimeapps.list
grep -qx '\[Default Applications\]' ~/.config/mimeapps.list || echo '[Default Applications]' >>~/.config/mimeapps.list
sed -i '/^inode\/directory=/d; /^\[Default Applications\]$/a inode/directory=thunar.desktop' ~/.config/mimeapps.list
```

To undo:

```
# Thunar; the thumbnailer and the Trash (gvfs) are marked "automatic" instead
# of purged, since other programs can need them: autoremove takes them out
# only if nothing does
sudo apt purge thunar
sudo apt-mark auto tumbler gvfs
sudo apt autoremove --purge
# Forget it as the default for folders
sed -i '/=thunar\.desktop$/d' ~/.config/mimeapps.list
```
