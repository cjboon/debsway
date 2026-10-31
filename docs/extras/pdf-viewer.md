# PDF viewer in a sandbox (`extras/pdf-viewer.sh`)

You get `zathura`, a small keyboard-driven PDF viewer. It is started inside the same kind of sandbox as `imv` and `mpv`: it sees only the files you name, read-only, with an empty home folder and no network.

## The problem it solves

Nothing else on a fresh debsway opens a PDF (Firefox can, if you installed it). A PDF is a complicated file that a viewer must interpret, and crafted ones are a common way to attack a computer. A viewer that runs as you with all your files can be turned into a thief; one in a sandbox can only see the one file it was given.

## The ideas behind it

See [media.md](media.md) for the sandbox ideas: bubblewrap, read-only, and the restricted Wayland socket. `zathura` is started through the same `media-sandbox` command; the PDF reading itself is done by `zathura-pdf-poppler`, a plugin.

## How it works, step by step

1. `apt_install zathura zathura-pdf-poppler bubblewrap python3`.
2. Puts `wayland-restrict`, `media-sandbox` and a short `zathura` wrapper in `~/.local/bin`.
3. Makes zathura the default for PDFs (`~/.config/mimeapps.list`).
4. Prints key hints.

Running `zathura paper.pdf` then goes through `media-sandbox`, which shows the program `/usr`, `/etc` and `/sys` read-only, a blank home and `/tmp`, the restricted window socket, and `paper.pdf` read-only. Your `~/.config/zathura` is shown read-only if it exists. It has no network and no sound.

## What it changes on your computer

- Packages: `zathura`, `zathura-pdf-poppler`, `bubblewrap`, `python3`.
- `~/.local/bin/zathura`, `media-sandbox` and `wayland-restrict`.
- The default PDF application in `~/.config/mimeapps.list`.

## Using it

`zathura paper.pdf`; j/k scroll, Space / b page down / up, J / K next / previous page, `5G` page 5, `+` / `-` zoom, `a` fit page, `s` fit width, `/` search, Tab table of contents, q quit. `DEBSWAY_NO_SANDBOX=1 zathura file.pdf` runs without the sandbox.

## Removing it

`bash extras/pdf-viewer.sh --remove`. The sandbox files stay while the media extra (imv, mpv) is installed.
