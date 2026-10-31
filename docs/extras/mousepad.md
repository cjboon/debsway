# Mousepad, a plain text editor (`extras/mousepad.sh`)

You get Mousepad, a simple graphical editor for plain text. It opens text files by default, and the first time it is installed it also gets a set look: dark colours, large type, line numbers.

## The problem it solves

Editing a config file or a note needs an editor. A terminal editor takes time to learn. Mousepad works like Notepad: open, type, save.

## The ideas behind it

**Plain text** is a file with just letters and symbols, no fonts or pictures: notes, config files, scripts. **A default application** is the program that opens a kind of file when you double-click or follow a link. debsway records these in `~/.config/mimeapps.list`. **gsettings** is the GNOME-family settings store. Mousepad keeps its preferences there.

## How it works, step by step

1. `apt_install mousepad` installs the editor under the marker package `debsway-mousepad`.
2. It makes Mousepad the default for `text/plain`, `text/markdown`, `text/x-log` and `application/x-shellscript` (shell scripts).
3. If the file `~/.local/state/debsway/mousepad-settings` does not exist, it applies the settings in `data/mousepad.settings` with `gsettings set`: solarized-dark colours, `Monospace 16` font, tabs 4 wide made of spaces, matching braces, line numbers and a right margin line. If it succeeds, it writes the date into that file.
4. If the file exists, it leaves your settings alone. If Mousepad's settings cannot be found, it skips the look with a warning. If only some failed, it warns and retries next run.

## What it changes on your computer

- Package `mousepad`.
- `~/.config/mimeapps.list`: the four types above.
- Mousepad's gsettings under `org.xfce.mousepad.preferences.view`.
- `~/.local/state/debsway/mousepad-settings`: a marker recording the date the look was applied.

## Using it

- `mousepad`, or Super+d, then `mousepad`: open it. Text files now open in it too.
- `mousepad FILE`: open a file.

## What it protects against

Nothing. It is a convenience. The one detail: re-running the script does not undo changes you made inside Mousepad.

## What it doesn't protect against

- **Anything running as you.** Mousepad runs as you and can open and change any of your files.
- **Opening untrusted files.** A text editor shows what is in the file. It does not make a script safe to run. Read scripts before you run them.

## Removing it

`bash extras/mousepad.sh --remove` removes the `mousepad` package, the default-application lines pointing at it, and the marker file in `~/.local/state/debsway`. It leaves your Mousepad settings as they are. `gsettings reset -r org.xfce.mousepad.preferences` clears them. Your files are untouched.
