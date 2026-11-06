# Wallpapers to pick from (`extras/wallpapers.sh`)

## SYNOPSIS

```
wrenctl install wallpapers                     download Budgie's, or nothing ("I'll find my own"); pictures go in ~/Pictures/Wallpapers
wrenctl remove wallpapers                      take out what it downloaded (your own pictures stay)
wrenctl manual wallpapers                      print the manual steps below

Super+] / Super+[                              step through them as your wallpaper
wallpaper pick                                 choose one by name
```

Pictures to choose your wallpaper from (the base's `~/Pictures/wren/desktop`, `parts/wallpaper.sh`),
in `~/Pictures/Wallpapers`: `budgie_`, Budgie's photos from Debian. The package is only downloaded with
`apt-get download` (checked against Debian's signed package lists, through Tor when apt goes through
Tor) and its pictures unpacked as you, so nothing is installed, no package script runs and no sudo is
needed.

An earlier version also fetched pictures from NASA and ESA (`nasa_`, `webb_`, `earth_`, with
`CREDITS.txt`). If you have them they stay yours: neither an update nor `wrenctl remove wallpapers`
touches them.

Ticking "No wallpapers downloaded, I'll find my own" downloads nothing and only sets up the folder
and its README. Pictures of your own (an image search, saved through Firefox into `~/Downloads`) can
go in the same folder: Wren Linux never changes or removes them.

Pexels has more for your own screen: <https://www.pexels.com/search/desktop%20wallpaper/>. They're free to
use there with no credit needed, but its terms don't allow passing them on as they are, so Wren Linux
doesn't ship any. Its licence, which can change: <https://www.pexels.com/license/>. Wren Linux only names
the site: nothing here opens or fetches it.

Super+] and Super+[ step through the folder as your wallpaper, and `wallpaper pick` lists it by name
(`parts/wallpaper.sh`). `README.txt` there says the same.

## LIMITS

- Pictures from an image search are usually someone's copyright: fine on your own screen, not to
  share on.

## MANUAL INSTALL

```
# Budgie's: downloaded (apt checks it against Debian's signed lists), its
# pictures and licence unpacked, nothing installed
mkdir -p ~/Pictures/Wallpapers /tmp/wp && cd /tmp/wp
apt-get download budgie-backgrounds
dpkg-deb -x budgie-backgrounds_*.deb x
find x -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \) -size +100k |
    while read -r f; do cp "$f" ~/Pictures/Wallpapers/budgie_"${f##*/}"; done
cp x/usr/share/doc/budgie-backgrounds/copyright ~/Pictures/Wallpapers/budgie_LICENCE.txt
cd && rm -rf /tmp/wp
```

To undo:

```
cd ~/Pictures/Wallpapers && rm -f budgie_*
```
