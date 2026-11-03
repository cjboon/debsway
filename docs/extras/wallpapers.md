# Wallpapers to pick from (`extras/wallpapers.sh`)

## SYNOPSIS

```
wrenctl install wallpapers                     pick sources, or none ("I'll find my own"); pictures go in ~/Pictures/Wallpapers
wrenctl remove wallpapers                      take out what it downloaded (your own pictures stay)
wrenctl manual wallpapers                      print the manual steps below

Super+] / Super+[                              step through them as your wallpaper
wallpaper pick                                 choose one by name
```

Pictures to choose your wallpaper from (the base's `~/Pictures/wren/desktop`,
`parts/wallpaper.sh`), all in `~/Pictures/Wallpapers`, each named after its
source: `nasa_` from NASA's image library (astronauts' photos and Hubble's
archive), `webb_` from ESA's Webb site in ESA's own 1920×1200 wallpaper cut,
`earth_` from NASA Earth Observatory's images of the day, and `budgie_`,
Budgie's photos from
Debian, whose package is only downloaded with `apt-get download` (checked
against Debian's signed package lists, through Tor when apt goes through Tor)
and its pictures unpacked as you, so nothing is installed, no package script
runs and no sudo is needed. The others are fetched by `lib/wallpaper-sources.py`:
https only, to each source's own hosts, also after a redirect; each picture at
least 1920×1080 and landscape (read from the file itself), a real JPEG or PNG
of at most 40 MB, and none whose credit names another copyright holder, with
its title, credit and page in `CREDITS.txt`. Ticking "No wallpapers downloaded, I'll find my own" downloads nothing and only sets up the folder and its README. Pictures of your own (an image
search, saved through Firefox into `~/Downloads`) can go in the same folder:
Wren Linux never changes or removes them. Super+] and Super+[ step through the
folder as your wallpaper, and `wallpaper pick` lists it by name
(`parts/wallpaper.sh`). `README.txt` there says the same.

## LIMITS

- The downloaded pictures come over https from their sites, not signed like Debian's packages: they are as trustworthy as NASA's and ESA's websites, which see your address (Tor isn't used for them).
- NASA's own pictures are public domain, but its library also holds partners'; Webb's are CC BY 4.0: `CREDITS.txt` says how to credit each if you share one.
- Earth Observatory's feed has only its last ten pictures, and some are too big (over 40 MB) or not landscape; the others top up over time as you run it again.
- USGS's Earth as Art and NOAA's photo library aren't included: neither has a feed or an interface for programs, and USGS's site turns them away.
- Pictures from an image search are usually someone's copyright: fine on your own screen, not to share on.

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

# The others, from their sites (or pick by hand: images.nasa.gov,
# esawebb.org/images, earthobservatory.nasa.gov)
for s in nasa webb earth; do
    python3 -I @WREN_DIR@/lib/wallpaper-sources.py ~/Pictures/Wallpapers "$s" 12
done
```

To undo:

```
cd ~/Pictures/Wallpapers && rm -f budgie_* nasa_* webb_* earth_* CREDITS.txt
```
