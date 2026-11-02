# Mousepad text editor (`extras/mousepad.sh`)

## SYNOPSIS

```
bash ~/debsway/extras/mousepad.sh            install it and set its look
bash ~/debsway/extras/mousepad.sh --remove   remove it (your Mousepad settings stay)
bash ~/debsway/extras/mousepad.sh --manual   print the manual steps below

mousepad [FILE]       open it (or Super+d); text files open in it too
```

Mousepad is a simple graphical text editor from Xfce, from Debian, made the
default for plain text, Markdown, logs and shell scripts. debsway sets its
look: white text on black in the terminal's colors (the scheme
`data/mousepad-dark.xml`), dark menus (the `mousepad` command, `bin/mousepad`,
starts it with GTK's dark theme), DejaVu Sans Mono 14, line numbers, matching
braces highlighted, a line at column 80, and tabs of 4 spaces
(`data/mousepad.settings`, set with gsettings). Run again, the script sets
them only if debsway's settings changed since, so your own changes stay.

## LIMITS

- It runs as you and can open and change any of your files.
- Showing a script in an editor doesn't make it safe to run: read it first.

## MANUAL INSTALL

```
# Mousepad, and gsettings to set its preferences
sudo apt install --no-install-recommends mousepad libglib2.0-bin
# The colour scheme, where Mousepad looks for schemes
install -D -m 0644 @DEBSWAY_DIR@/data/mousepad-dark.xml ~/.local/share/gtksourceview-4/styles/debsway-dark.xml
# The mousepad command with dark menus
install -D -m 0755 @DEBSWAY_DIR@/bin/mousepad ~/.local/bin/mousepad
# The settings: one "gsettings set" per line of data/mousepad.settings
grep -v '^#' @DEBSWAY_DIR@/data/mousepad.settings | grep . | while read -r schema key value; do
    gsettings set "$schema" "$key" "$value"
done
# The default for text files (in ~/.config/mimeapps.list, under [Default Applications])
mkdir -p ~/.config && touch ~/.config/mimeapps.list
grep -qx '\[Default Applications\]' ~/.config/mimeapps.list || echo '[Default Applications]' >>~/.config/mimeapps.list
for t in text/plain text/markdown text/x-log application/x-shellscript; do
    sed -i "\\|^$t=|d; /^\\[Default Applications\\]\$/a $t=org.xfce.mousepad.desktop" ~/.config/mimeapps.list
done
```

To undo:

```
# Forget it as the default for text files
sed -i '/=org\.xfce\.mousepad\.desktop$/d' ~/.config/mimeapps.list
# The command and the colour scheme
rm ~/.local/bin/mousepad ~/.local/share/gtksourceview-4/styles/debsway-dark.xml
# Its settings back to Mousepad's own
gsettings reset-recursively org.xfce.mousepad.preferences
# Mousepad; gsettings (libglib2.0-bin) is marked "automatic" instead of purged,
# since other programs can need it: autoremove takes it out only if nothing does
sudo apt purge mousepad
sudo apt-mark auto libglib2.0-bin
sudo apt autoremove --purge
```
