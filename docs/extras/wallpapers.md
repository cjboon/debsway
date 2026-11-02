# Debian's wallpapers (`extras/wallpapers.sh`)

## SYNOPSIS

```
bash ~/debsway/extras/wallpapers.sh            pick collections; their pictures go in ~/Pictures/Wallpapers
bash ~/debsway/extras/wallpapers.sh --remove   take out what it put there (your own pictures stay)
bash ~/debsway/extras/wallpapers.sh --manual   print the manual steps below

cp ~/Pictures/Wallpapers/gnome-backgrounds/PICTURE ~/Pictures/debsway/desktop/
                                               make one your wallpaper, then Super+Shift+c
```

Debian's wallpaper collections, sway's, Debian's own release artwork, GNOME's,
Budgie's, MATE's, KDE's and Xfce's, as pictures in `~/Pictures/Wallpapers`, a
folder per collection, to pick your wallpaper from (the base's
`~/Pictures/debsway/desktop`, `parts/wallpaper.sh`). A list asks which; the
big ones start unticked. The packages are only downloaded, with
`apt-get download`, which checks each against Debian's signed package lists
(and goes through Tor when apt does), and the JPEG and PNG pictures and the
package's licence file are unpacked from it as you: nothing is installed, no
package script runs, and it needs no sudo. Installed, `desktop-base` would also
change your boot and login screens; unpacked, it changes nothing.

## LIMITS

- The pictures are freely licensed, not public domain: to share or publish one, credit its artist as the folder's `LICENCE.txt` says.
- They come from apt's package lists on this computer: with old lists a download fails (`sudo apt update`, then run it again).
- KDE's set is 124 MB; all of them together are about 230 MB.
- SVG pictures are left out (a much bigger program would have to read them), and so are pictures under 100 kB (icons, boot-screen pieces).

## MANUAL INSTALL

```
# One collection, gnome-backgrounds here: downloaded (apt checks it against
# Debian's signed lists), its pictures and licence unpacked, nothing installed
mkdir -p ~/Pictures/Wallpapers/gnome-backgrounds /tmp/wp && cd /tmp/wp
apt-get download gnome-backgrounds
dpkg-deb -x gnome-backgrounds_*.deb x
find x -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \) -size +100k \
    -exec cp -t ~/Pictures/Wallpapers/gnome-backgrounds/ {} +
cp x/usr/share/doc/gnome-backgrounds/copyright ~/Pictures/Wallpapers/gnome-backgrounds/LICENCE.txt
cd && rm -rf /tmp/wp
```

To undo:

```
rm -r ~/Pictures/Wallpapers/gnome-backgrounds
```
