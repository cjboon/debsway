# Colour emoji (`extras/emoji-font.sh`)

You get a font with colour emoji, so the small pictures in messages and web pages show up instead of empty boxes.

## The problem it solves

Emoji are characters, like letters. If no installed font has a picture for one, the computer shows an empty box. A minimal install has no such font.

## The ideas behind it

**A font** is a set of shapes for characters. **Emoji** are characters sent as codes, and each font draws them its own way. The font here is `fonts-noto-color-emoji`, Google's Noto Color Emoji set, from Debian.

## How it works, step by step

1. `apt_install fonts-noto-color-emoji` installs it under the marker package `debsway-emoji-font`.
2. It tells you to restart Firefox and `foot` (the terminal) so they notice the new font.

The script sets nothing else.

## What it changes on your computer

- Package `fonts-noto-color-emoji`. Nothing else.

## Using it

Nothing to run. After a restart of Firefox and `foot`, emoji appear in colour wherever you read them.

## What it protects against

Nothing. It is a convenience.

## What it doesn't protect against

Nothing here is a protection, so there is nothing to fall short. The package comes through apt, which checks Debian's signature, and a font can be a vehicle for bugs like any file a program parses.

## Removing it

`bash extras/emoji-font.sh --remove` removes the font package. Emoji go back to empty boxes. Nothing else changes.
