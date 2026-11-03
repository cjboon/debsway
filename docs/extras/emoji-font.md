# Color emoji (`extras/emoji-font.sh`)

## SYNOPSIS

```
debsway install emoji-font                     install it
debsway remove emoji-font                      remove it
debsway manual emoji-font                      print the manual steps below

(nothing to run: restart Firefox and foot, and emoji show in color)
```

Without a color emoji font, emoji show up as empty boxes in Firefox, foot and
every other program. This installs Google's Noto Color Emoji font from
Debian's archive, so they show as pictures everywhere. It changes no settings.

## LIMITS

- It's only a font: nothing to do with security or privacy.

## MANUAL INSTALL

```
# The font, from Debian
sudo apt install --no-install-recommends fonts-noto-color-emoji
# Programs read fonts when they start: close and reopen Firefox and foot
```

To undo:

```
# Remove the font
sudo apt purge fonts-noto-color-emoji
```
