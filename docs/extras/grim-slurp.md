# Screenshots (`extras/grim-slurp.sh`)

You get a `screenshot` command and keys for it. Print takes a picture of the whole screen, Shift+Print lets you drag a box, and Ctrl+Print puts a dragged box on the clipboard.

## The problem it solves

sway has no screenshot tool. This adds a small one, using the Wayland programs `grim` (takes the picture) and `slurp` (lets you drag a region).

## The ideas behind it

**Wayland** is the window system sway uses. For safety, ordinary programs cannot capture the screen on it, so a screenshot tool has to ask sway directly. **The clipboard** is the temporary place copy and paste use; `wl-copy` (from the `wl-clipboard` package, set up elsewhere by `parts/wl-clipboard.sh`) is how a picture is put there.

## How it works, step by step

1. `apt_install grim slurp`.
2. `install_bin screenshot` copies `bin/screenshot` to `~/.local/bin/screenshot`.
3. `put_snippet screenshots` writes `~/.config/sway/config.d/screenshots.conf`. sway checks it, and the old file is put back if sway rejects it. The stock Print binding in the sway config is removed so the two do not clash.

What `screenshot` does:
- `full`: `grim` saves the whole screen to `~/Pictures/screenshot-DATE_TIME.png`, making the folder if needed.
- `region`: `slurp` lets you drag; `grim` saves that box. Escape cancels, and nothing is saved.
- `clip`: the box goes to the clipboard through `wl-copy`. If `wl-copy` is not installed, it saves a file instead.

## What it changes on your computer

- Packages `grim` and `slurp`.
- `~/.local/bin/screenshot`.
- `~/.config/sway/config.d/screenshots.conf`, with these keys:
  - Print or Super+Shift+p: whole screen
  - Shift+Print or Super+Shift+s: drag a region
  - Ctrl+Print or Super+Shift+x: drag a region to the clipboard
- `~/Pictures/` when you take the first shot.

## Using it

- `screenshot full`, `screenshot region`, `screenshot clip`: the same from a terminal.
- Print and the Super+Shift keys, as above. Keyboards without a Print key use the Super+Shift ones.

## What it protects against

Nothing. It is a convenience. One thing to know: a screenshot records everything visible on the screen, including passwords or private windows.

## What it doesn't protect against

- **Sensitive content on the screen.** A screenshot of a wallet seed or a chat can be found later in `~/Pictures`. Delete it when done.
- **Windows meant to stay private.** `THREAT-MODEL.md` notes that the `incognito` window is visible to your screenshots, as any window is.
- **Anything running as you**, which can read `~/Pictures`.

## Removing it

`bash extras/grim-slurp.sh --remove` deletes the sway snippet, the `screenshot` command and the two packages. It leaves the pictures in `~/Pictures`.
