# Tor Browser (`extras/tor-browser.sh`)

## SYNOPSIS

```
wrenctl install tor-browser                     install it, or change its bridge (asks if you need one)
wrenctl remove tor-browser                      remove it (asks before deleting the downloaded browser)
wrenctl manual tor-browser                      print the manual steps below

torbrowser-launcher       start Tor Browser (or Super+d); the first start downloads it
```

Tor Browser sends what you browse through three Tor relays, so the sites
can't see your address and your network can't see where you go. It comes
through Debian's torbrowser-launcher, which downloads Tor Browser from
torproject.org, checks its signature and keeps it updated; the launcher is in
Debian's contrib section, so contrib is turned on. Tor Browser runs on X11 on
purpose (it's less fingerprintable), so XWayland is installed. Before its
first start, Wren Linux writes a `user.js` into its profile: the Safest security
level with JavaScript off (`data/tor-browser-safest.js`), and a bridge if you
need one (obfs4, webtunnel, Snowflake or meek), so its very first connection
already goes through it; Firefox applies `user.js` at every start. Tor's
AppArmor profile is fixed so bridges given as host names can be looked up.
If `prep/fetch-tor-browser.sh` saved a checked copy in `offline/torbrowser`,
that is unpacked instead, and torproject.org is never contacted.

## LIMITS

- The first start downloads Tor Browser without Tor: your network sees that you fetched it (not what you do with it).
- Logging in to a site tells it who you are, Tor or not.
- Safest breaks many sites; lowering it gives attackers more to work with.
- It runs as you, with no sandbox from Wren Linux; for a stronger wall, use Whonix or Tails.

## MANUAL INSTALL

```
# Debian's contrib section, where torbrowser-launcher is: add "contrib" after
# "main" on Debian's lines (in /etc/apt/sources.list, or the Components: lines
# of /etc/apt/sources.list.d/debian.sources), then check
sudo sed -i -E '/^deb(-src)?[[:space:]].*debian/ { /[[:space:]]contrib([[:space:]]|$)/! s/[[:space:]]main([[:space:]]|$)/ main contrib\1/ }' /etc/apt/sources.list
grep -n contrib /etc/apt/sources.list /etc/apt/sources.list.d/*.sources

# XWayland (Tor Browser uses X11) and the launcher
sudo apt update
sudo apt install --no-install-recommends xwayland torbrowser-launcher xz-utils
# If XWayland was new: log out and back in once, so sway starts it

# Let Tor's AppArmor profile read resolv.conf through its symlink, for
# bridges given as host names (webtunnel), then reload the profile
printf '%s\n' '# >>> Wren Linux: DNS through the resolv.conf symlink >>>' \
    '@{run}/resolvconf/resolv.conf r,' '@{run}/NetworkManager/{,no-stub-}resolv.conf r,' \
    '@{run}/systemd/resolve/{,stub-}resolv.conf r,' '# <<< Wren Linux <<<' | sudo tee -a /etc/apparmor.d/local/torbrowser.Tor.tor
sudo apparmor_parser -r /etc/apparmor.d/torbrowser.Tor.tor

# Safest, JavaScript off, before its first start: a user.js in the profile
# torbrowser-launcher will unpack Tor Browser into
P=~/.local/share/torbrowser/tbb/$(uname -m)/tor-browser/Browser/TorBrowser/Data/Browser/profile.default
mkdir -p "$P" && chmod 700 "$P"
cp @WREN_DIR@/data/tor-browser-safest.js "$P/user.js"
# A bridge, if you need one: add ONE of these blocks to that user.js
#  Tor Browser's built-in bridges (TYPE is obfs4, snowflake or meek):
#    user_pref("torbrowser.settings.bridges.enabled", true);
#    user_pref("torbrowser.settings.bridges.source", 0);
#    user_pref("torbrowser.settings.bridges.builtin_type", "TYPE");
#  your own obfs4 or webtunnel lines from bridges.torproject.org, numbered from 0:
#    user_pref("torbrowser.settings.bridges.enabled", true);
#    user_pref("torbrowser.settings.bridges.source", 2);
#    user_pref("torbrowser.settings.bridges.bridge_strings.0", "obfs4 1.2.3.4:443 ...");
chmod 600 "$P/user.js"

# Start it: the first start downloads Tor Browser and checks its signature
torbrowser-launcher
```

To undo:

```
# The launcher
sudo apt purge torbrowser-launcher
# The AppArmor lines added above (between the Wren Linux marker lines)
sudo sed -i '/^# >>> Wren Linux: DNS through the resolv.conf symlink >>>$/,/^# <<< Wren Linux <<<$/d' /etc/apparmor.d/local/torbrowser.Tor.tor
# contrib off again, if nothing else needs it
sudo sed -i -E 's/ main contrib([[:space:]]|$)/ main\1/' /etc/apt/sources.list
sudo apt update
# The downloaded browser, its bookmarks and settings
rm -rf ~/.local/share/torbrowser ~/.cache/torbrowser ~/.config/torbrowser
```
