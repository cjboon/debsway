# Metadata Cleaner, to strip hidden data from files (`extras/metadata-cleaner.sh`)

You get Metadata Cleaner, a small window program, and the `mat2` command it is built on. Both remove hidden details from photos, PDFs, office documents, audio and video before you share them. Both come from Debian.

## The problem it solves

A file often carries more than you can see. A photo may record where you stood and which camera took it. A document may record your name and its edit history. When you share the file, that goes along. This extra lets you remove it first.

## The ideas behind it

**Metadata** is data about a file, kept inside it, such as GPS position, camera model, author names, software used or edit history. It is like the postmark and return address on an envelope, as opposed to the letter itself.

**mat2** is a metadata anonymisation toolkit. For each file type it knows, it writes a copy with the metadata removed. Metadata Cleaner is the graphical front end, the same program Tails (a privacy-focused operating system) ships.

**Cleaning may change the file.** To be sure nothing hides in a PDF, a normal clean turns its pages into images. The result looks the same, but the text can no longer be selected.

## How it works, step by step

1. `apt_install metadata-cleaner mat2` installs both, through the marker package `debsway-metadata-cleaner`.
2. It prints examples. Nothing else is configured.

When you use it:

- In the window, you add files, look at what they carry, and clean them.
- In a terminal, `mat2` does the same job.

## What it changes on your computer

- Packages `metadata-cleaner` and `mat2` and their dependencies.
- The commands `metadata-cleaner` and `mat2` (from the packages, not `~/.local/bin`).
- No settings, key bindings or default applications.

## Using it

- `metadata-cleaner`, or Super+d: open the window.
- `mat2 --show photo.jpg`: list the metadata found. Removes nothing.
- `mat2 photo.jpg`: write `photo.cleaned.jpg` without metadata. The original stays.
- `mat2 *.jpg report.pdf`: clean several files at once.
- `mat2 --inplace photo.jpg`: clean the file itself, with no copy kept.
- `mat2 --lightweight report.pdf`: gentler. A PDF keeps its selectable text, but some metadata may stay.
- `mat2 --list`: the file types it handles.

## What it protects against

- **Hidden data in files you share** (`THREAT-MODEL.md`): GPS position, camera model, author names and edit history, in the file types mat2 handles.

## What it doesn't protect against

- **Anything it cannot see.** `--show` finding nothing does not prove a file is clean. Clean it anyway.
- **File types mat2 does not handle.** Check with `mat2 --list`.
- **What is in the visible content.** A face, a street sign, a name written in the text, or your writing style is yours to watch.
- **A gentle clean leaving some metadata**, if you use `--lightweight`.
- **Mistakes with `--inplace`.** No copy of the original is kept.
- **Which files you choose to send.** Nothing here sanitises files automatically. You must run it.

## Removing it

`bash extras/metadata-cleaner.sh --remove` removes `metadata-cleaner` and `mat2` and whatever only they needed. It touches none of your files, including cleaned copies you made.
