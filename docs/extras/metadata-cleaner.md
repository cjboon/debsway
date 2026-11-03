# Metadata Cleaner (`extras/metadata-cleaner.sh`)

## SYNOPSIS

```
wrenctl install metadata-cleaner                     install it
wrenctl remove metadata-cleaner                      remove it
wrenctl manual metadata-cleaner                      print the manual steps below

metadata-cleaner               the window (or Super+d): add files, look, clean
mat2 --show photo.jpg          list the metadata it finds (removes nothing)
mat2 photo.jpg                 write photo.cleaned.jpg without metadata
mat2 --inplace photo.jpg       clean the file itself, no copy kept
mat2 --lightweight report.pdf  gentler: a PDF keeps selectable text, some metadata may stay
mat2 --list                    the file types it handles
```

Photos, PDFs, office documents, audio and video carry hidden metadata: GPS
position, camera model, author names, edit history. Metadata Cleaner, the
graphical program Tails ships, removes it before you share a file. It is built
on mat2, which comes with it and gives the `mat2` command. Both are from
Debian. A normal clean turns PDF pages into images, so the text can't be
selected any more; that's how it makes sure nothing hides in them.

## LIMITS

- `--show` finding nothing doesn't prove a file is clean: clean it anyway.
- The visible content is yours to watch: a face, a street sign, a name in the text.
- `--lightweight` can leave some metadata; `--inplace` keeps no copy of the original.
- Nothing is cleaned unless you run it.

## MANUAL INSTALL

```
# Metadata Cleaner and mat2, from Debian
sudo apt install --no-install-recommends metadata-cleaner mat2
```

To undo:

```
# Remove both
sudo apt purge metadata-cleaner mat2
sudo apt autoremove --purge
```
