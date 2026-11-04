#!/bin/bash
# What install-base.sh is about to do, a disclaimer, and the question
# whether to go on. install-base.sh runs this first (skip it with --yes);
# it exits 0 to go on, 1 if you said no or there is nobody to ask.
#   bash prep/intro.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"

bold=$(printf '\033[1m')
off=$(printf '\033[0m')

text=$(cat <<EOF
${bold}Wren Linux: what the base install does${off}

It turns this Debian 13 (trixie) system into a small sway desktop. It will:

  1. Install programs with apt (it asks for your sudo password): the sway
     window manager, the foot terminal, and the pieces below. Nothing is
     installed that isn't listed here. First it asks whether apt should
     download through Tor over https, with a bridge if you need one (the
     default is no).
  2. Write settings in your home folder: ~/.config/sway (your own sway
     config is kept; one include line is added), ~/.local/bin, and a block
     in ~/.profile that starts sway when you log in on tty1.
  3. Change the system, as root, with one small script per piece:
       - automatic security updates every day
       - a firewall that blocks everything coming in (ufw)
       - NetworkManager takes over your Wi-Fi (the connection can drop for
         a few seconds) and uses a random hardware address on every network
       - kernel hardening: safer sysctl settings, boot parameters that clear
         memory and tighten the allocator (they apply after one reboot), and
         a list of unused kernel modules that are blocked from loading
       - needrestart, which lists programs still running outdated libraries
         after an update (it never restarts anything itself)
       - encrypted DNS: Unbound on this computer asks a resolver over TLS,
         /etc/resolv.conf points at it and a firewall rule stops other DNS
         going around it (a switch in the Wren menu turns it off)
       - your home folder closed to other users (chmod on what is directly
         in it, umask 077 in ~/.profile, and a sudo rule so that what root
         installs stays readable)
       - what Debian's live image adds is removed: avahi, hw-probe, extrepo,
         telnet, printing unless you say you print, and dkms and mdadm if
         nothing needs them
       - the clock kept right over NTP, and a question about your time zone
       - tmux for text consoles, GRUB's menu in Wren Linux's colors
       - launcher, screen lock, a power menu (Super+Shift+Escape),
         brightness, clipboard, notifications, USB drives (mounted so
         nothing on them can run), a readable terminal font and colors,
         power profiles
  4. Before any of that, offer a list of optional programs to pick from, and
     install what you pick at the end. Sound, screenshots and emoji are
     there, and so are browsers: without one you have no web browser. Firefox
     comes as its own locked-down user, with HTTPS-Only Mode, no JavaScript JIT
     and uBlock Origin, and with incognito, a throwaway Firefox as another such
     user. w3m is on the list too, for a text-only web.

It needs an internet connection and takes several minutes. Every piece can
be taken out again with "bash parts/NAME.sh --remove", and the scripts can
be run again to repair it. Read them first if you like: they're in parts/.
bash status.sh shows afterwards what is set up.

${bold}Disclaimer${off}

Wren Linux is free software, provided "as is", without warranty of any kind
(see the LICENSE file). It makes changes to your system with administrator
rights, and a mistake, a bug, or a package that changes upstream could
leave something not working. Back up what you care about first.

It makes common attacks harder; it does not make you anonymous or safe.
THREAT-MODEL.md says what it protects against and what it does not. You are
responsible for what you run on your computer and for how you use it.
EOF
)

# Longer than the screen: page it (space for more, q to get to the question).
# less's own prompt is a lone ":", so it says what to press, and at the end
# that q goes on (in less's prompt language: ?e...:... is "at the end, or not")
INTRO_PROMPT='?eThe end\. Press q to go on to the question:Space for more\, b to go back\, q to go on.'
if [ -t 1 ] && command -v less >/dev/null; then
    printf '%s\n\n' "$text" | less -FRX -Ps"$INTRO_PROMPT"
else
    printf '%s\n\n' "$text"
fi


if [ "${WREN_ASSUME_YES:-}" = 1 ]; then exit 0; fi
if ! { : </dev/tty; } 2>/dev/null; then
    warn "There is no terminal to ask on. Run it from a terminal, or use: bash install-base.sh --yes"
    exit 1
fi
if ask "Do you want to go on with the base install?" y; then
    exit 0
fi
note "Nothing was changed."
exit 1
