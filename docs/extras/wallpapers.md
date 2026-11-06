# Wallpapers to pick from (`extras/wallpapers.sh`)

## SYNOPSIS

```
wrenctl install wallpapers                     choose basic and/or strong; pictures go in ~/Pictures/Wallpapers
wrenctl remove wallpapers                      take out what it put there (your own pictures stay)
wrenctl manual wallpapers                      print the manual steps below

Super+] / Super+[                              step through them as your wallpaper
wallpaper pick                                 choose one by name
```

Pictures to choose your wallpaper from (the base's `~/Pictures/wren/desktop`, `parts/wallpaper.sh`),
copied into `~/Pictures/Wallpapers` from `data/wallpapers/`. They come with Wren Linux, so nothing is
downloaded and Wren Linux's signature covers them. `CREDITS.txt` names each one's author, page, licence and
what was changed.

- **basic**, ticked at first: wrens, art, Earth and space.
- **strong**, never on unless you tick it: real violence and death, and nudity. Without a terminal to ask
  on, it isn't copied. Unticking it later takes those pictures out again.

An earlier version fetched pictures from NASA, ESA and Debian. NASA's and ESA's (`nasa_`, `webb_`, `earth_`)
stay yours: neither an update nor `wrenctl remove wallpapers` touches them, and a picture you already have
isn't replaced by a smaller one.

Pictures of your own (an image search, saved through Firefox into `~/Downloads`) can
go in the same folder: Wren Linux never changes or removes them.

Pexels has more for your own screen: <https://www.pexels.com/search/desktop%20wallpaper/>. They're free to
use there with no credit needed, but its terms don't allow passing them on as they are, so Wren Linux
doesn't ship any. Its licence, which can change: <https://www.pexels.com/license/>. Wren Linux only names
the site: nothing here opens or fetches it.

Super+] and Super+[ step through the folder as your wallpaper, and `wallpaper pick` lists it by name
(`parts/wallpaper.sh`). `README.txt` there says the same.

## LIMITS

- Most need a credit if you share them on, and some must be shared under the same licence:
  `CREDITS.txt` says which.
- Commons lists some pictures as public domain, and Wren Linux hasn't confirmed that further.
- Pictures from an image search are usually someone's copyright: fine on your own screen, not to
  share on.

## MANUAL INSTALL

```
mkdir -p ~/Pictures/Wallpapers
cp -n @WREN_DIR@/data/wallpapers/*.jpg @WREN_DIR@/data/wallpapers/*.png \
    @WREN_DIR@/data/wallpapers/CREDITS.txt ~/Pictures/Wallpapers/
# Only if you want the strong ones: real violence and death, and nudity
# cp -n @WREN_DIR@/data/wallpapers/shock/*.jpg ~/Pictures/Wallpapers/
```

To undo: delete the pictures you copied, from `~/Pictures/Wallpapers`.
