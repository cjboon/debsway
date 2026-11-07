# The extras, explained

One page per extra. The short list of all of them is in
[../extras.md](../extras.md); general advice is in [../opsec.md](../opsec.md).

Every page has the same shape:

- **SYNOPSIS**: the commands to install, remove and use it.
- One paragraph on what it is.
- **LIMITS**: what it does not protect against.
- **MANUAL INSTALL**: every step to do by hand what the script does, each with
  what it is for. `wrenctl manual NAME` prints this section
  and changes nothing. In the page, `@NAME@` stands for a value from `pins.sh`
  or the script (a key's fingerprint, an address, a package list) and
  `@WREN_DIR@` for your Wren Linux folder; `--manual` fills them in.

Installed by hand, an extra has no Wren Linux marker package, so its `--remove`
doesn't know what to take out: undo it with the steps at the end of its page.
`apt purge` also removes every package that depends on what you purge, so the
undo steps purge only the extra's own programs and mark shared ones
"automatic" (`apt-mark auto`), for `apt autoremove` to take out only if
nothing needs them. Either way, read the list apt shows before you say yes.


## Browsing

- [Firefox's hardening, and a throwaway window](firefox.md)
- [Firefox as its own locked-down user](firefox-sandbox.md)
- [One Firefox profile per site](firefox-profiles.md)
- [PDF viewer in a sandbox](pdf-viewer.md): `docs/extras/pdf-viewer.md`
- [GIMP image editor, in a sandbox](gimp.md)
- [Archive tools](archive-tools.md): `docs/extras/archive-tools.md`
- [Console-only, tmux instead of sway](console-only.md): `docs/extras/console-only.md`
- [w3m, a web browser for the terminal](w3m.md): `docs/extras/w3m.md`
- [vim, with colors for each programming language](vim.md)
- [Tor Browser, as its own user](tor-browser.md)
- [Mullvad Browser, as its own user](mullvad-browser-sandbox.md)
- [Mullvad Browser, as you](mullvad-browser-regular.md)

## Anonymity and network privacy

- [Mullvad VPN](mullvad-vpn.md)
- [Whonix, Tor in a virtual machine](whonix.md)
- [Share files over Tor with OnionShare](onionshare.md)
- [Your own onion site](onion-site.md)
- [Remote access over Tor](remote-access.md)
- [Other systems' install images, checked, onto a USB stick](get-iso.md)
- [Tails on a USB stick](tails-usb.md)

## Sandboxes and test machines

- [Claude Code as you, with its own sandbox on](claude-regular.md) (retired)
- [Claude Code in its own user](claude-code.md)
- [Claude Code inside a disposable virtual machine](claude-vm.md)
- [opencode inside a disposable virtual machine](opencode-vm.md) (retired)
- [A disposable practice server](mockvps-kvm.md)
- [Kali, Tails and Arch in VMs kept off your network](distro-vm.md) (retired)
- [Images and video in a sandbox](media.md)
- [yt-dlp as its own locked-down user](yt-dlp.md)

## Passwords, keys and backups

- [A password manager](keepassxc.md)
- [A keyring that unlocks when you log in](seahorse.md)
- [Hardware security keys: SSH, website logins and sudo](security-key.md)
- [A watch on what starts at your login](startup-watch.md)
- [Encrypted backups of your home folder](backup.md)
- [An encrypted ~/Vault that locks itself](vault.md)

## Money

- [Electrum, a Bitcoin wallet](electrum.md)
- [Sparrow, a Bitcoin wallet with extra privacy tools](sparrow-wallet.md)
- [Feather, a Monero wallet](feather-wallet.md)
- [Hardware wallets over USB](hardware-wallet.md)
- [Sandboxed wallets, for a computer that can't run VMs](wallet-sandbox.md) (retired)

## Messaging and sharing

- [Signal Desktop](signal.md)
- [SimpleX Chat, a private messenger](simplex-chat.md)
- [Metadata Cleaner, to strip hidden data from files](metadata-cleaner.md)
- [Wallpapers to pick from: NASA, Webb, Earth Observatory, Budgie, or your own](wallpapers.md)

## Devices and hardware

- [Sound and the microphone switch](pipewire-audio.md)
- [Bluetooth, off until you want it](bluetooth.md)
- [Phone tethering over USB](phone-tethering.md)
- [USB drives that mount by themselves, safely](udiskie.md)
- [Closing the lid locks but doesn't suspend](lid-awake.md)
- [Compressed memory](zram.md)
- [One workspace: no workspace keys or buttons](one-workspace.md)
- [Logging in on tty1 without the password](autologin.md)
- [A webcam switch, off at every boot](webcam.md)

## Everyday tools

- [git, to track changes to files](git.md)
- [Tools for working on Wren Linux: lintian and shellcheck](wren-dev.md)
- [Wren Linux's signing key, kept by a user of its own](signing-key.md)
- [Thunar, a file manager](file-manager.md)
- [Mousepad, a plain text editor](mousepad.md)
- [Screenshots](grim-slurp.md)
- [Colour emoji](emoji-font.md)
