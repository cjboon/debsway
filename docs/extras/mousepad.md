# Mousepad, a plain text editor (`extras/mousepad.sh`)

You get Mousepad, a simple graphical editor for plain text. It opens text files by default, and it gets a set look: white text on black in the terminal's colours, with dark menus, the terminal's font at 14 pt, line numbers, matching braces highlighted, a line at column 80 and tabs of 4 spaces.

## The problem it solves

Editing a config file or a note needs an editor. A terminal editor takes time to learn. Mousepad works like Notepad: open, type, save.

## The ideas behind it

**Plain text** is a file with just letters and symbols, no fonts or pictures: notes, config files, scripts. **A default application** is the program that opens a kind of file when you double-click or follow a link. debsway records these in `~/.config/mimeapps.list`. **gsettings** is the GNOME-family settings store. Mousepad keeps its preferences there.

## How it works, step by step

1. `apt_install mousepad libglib2.0-bin` installs the editor and `gsettings` (which sets its preferences) under the marker package `debsway-mousepad`. Before, `gsettings` wasn't installed with it, so on a debsway system the look was skipped with only a warning.
2. It makes Mousepad the default for `text/plain`, `text/markdown`, `text/x-log` and `application/x-shellscript` (shell scripts).
3. It installs `~/.local/bin/mousepad` (`bin/mousepad`), which starts Mousepad with GTK's dark theme (`GTK_THEME=Adwaita:dark`), so the menus and toolbar are dark too. Only Mousepad is affected.
4. It installs debsway's colour scheme, `data/mousepad-dark.xml`, as `~/.local/share/gtksourceview-4/styles/debsway-dark.xml`: black page, light grey text, the terminal's colours (`data/foot.ini`) for code.
5. It applies `data/mousepad.settings` with `gsettings set`: that scheme, `DejaVu Sans Mono 14`, tabs 4 wide made of spaces, automatic indenting, matching braces, line numbers and a line at column 80. If it succeeds, it writes a fingerprint (SHA-256) of the settings and the scheme into `~/.local/state/debsway/mousepad-settings`.
6. Run again, it sets them only if debsway's settings or scheme changed since, so your own changes in Mousepad stay. If Mousepad's settings cannot be found, it warns, sets nothing and tries again on the next run.

## What it changes on your computer

- Packages `mousepad` and `libglib2.0-bin`.
- `~/.local/bin/mousepad` and `~/.local/share/gtksourceview-4/styles/debsway-dark.xml`.
- `~/.config/mimeapps.list`: the four types above.
- Mousepad's gsettings under `org.xfce.mousepad.preferences.view`.
- `~/.local/state/debsway/mousepad-settings`: a marker recording which settings were applied.

## Using it

- `mousepad`, or Super+d, then `mousepad`: open it. Text files now open in it too.
- `mousepad FILE`: open a file.

## What it protects against

Nothing. It is a convenience. The one detail: re-running the script does not undo changes you made inside Mousepad, unless debsway's own settings changed since.

## What it doesn't protect against

- **Anything running as you.** Mousepad runs as you and can open and change any of your files.
- **Opening untrusted files.** A text editor shows what is in the file. It does not make a script safe to run. Read scripts before you run them.

## Removing it

`bash extras/mousepad.sh --remove` removes the `mousepad` package (and `libglib2.0-bin` if nothing else needs it), the default-application lines pointing at it, the `mousepad` command and colour scheme debsway wrote, and the marker file in `~/.local/state/debsway`. It leaves your Mousepad settings as they are. `gsettings reset -r org.xfce.mousepad.preferences` clears them. Your files are untouched.
