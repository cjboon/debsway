# Electrum, a Bitcoin wallet (`extras/electrum.sh`)

You get Electrum, a graphical wallet for holding and sending Bitcoin. It comes from Debian's own package archive, so Debian keeps it patched and updates it with everything else. Your wallet files live in `~/.electrum`.

## The problem it solves

Bitcoin is money that exists only as entries in a shared public record. To use it you need a program that can create your keys, show your balance and sign payments. Without one, you cannot hold Bitcoin yourself. This extra gives you such a program, installed the same way as the rest of the system.

## The ideas behind it

**A Bitcoin wallet** does not hold coins like a leather wallet holds cash. Your coins are entries in a public record called the blockchain. What you hold is a set of secret keys that prove those entries are yours. The wallet program looks after the keys and builds payments.

**A seed** is a list of words (usually 12) from which all your keys can be rebuilt. It works like the master key to a building full of lockers. Anyone who has the words can take the money. If you lose both the wallet file and the words, the money is gone. No company can reset it for you. Write the words on paper and keep them somewhere safe.

**Why it comes from Debian.** Debian's packages are signed by Debian, and apt checks that signature on every download. Debian also installs security fixes by itself every day (`parts/unattended-upgrades.sh`). The cost is that Debian's version may be older than the newest one on the Electrum website.

**Qt and Wayland.** Electrum is built with a toolkit called Qt (version 5). The package `qtwayland5` lets Qt programs draw natively on sway's window system, Wayland, so Electrum needs no compatibility layer.

## How it works, step by step

1. `need_user` checks that you run the script as yourself, not as root.
2. `apt_install electrum qtwayland5` installs both packages. debsway does not install them directly. It builds a tiny empty package called `debsway-electrum` that depends on them, and installs that. This lets `--remove` take out exactly what this script added, without touching things other extras need.
3. It prints a note: run `electrum`, or press Super+d and type its name. Wallets live in `~/.electrum`.

That is all. The script makes no settings changes and adds no key bindings. It does not choose a server for you.

## What it changes on your computer

- Packages: `electrum` and `qtwayland5`, plus whatever they depend on, recorded under the marker package `debsway-electrum`.
- When you first run Electrum, it creates `~/.electrum` for your wallets.
- Nothing is added to `~/.local/bin`, `~/.config/sway` or `~/.config/mimeapps.list`.

## Using it

- `electrum` starts the wallet (or Super+d, then `electrum`).
- On first start it walks you through creating a new wallet or restoring one from a seed. Write the seed down before you go on.
- Re-run `bash extras/electrum.sh` any time. It installs nothing twice. Updates themselves arrive through Debian's normal daily upgrade.

## What it protects against

- **A tampered download.** The package comes through apt, which checks Debian's signature. debsway adds no extra check, because it does not need one here.
- **Known bugs going unfixed.** Debian's daily security updates cover this package (`THREAT-MODEL.md`, "Known bugs being used against you").

## What it doesn't protect against

- **Anything running as you.** debsway does not sandbox your own user. A malicious program, or an attack that escapes your browser, can read `~/.electrum` like any other file (`THREAT-MODEL.md`: "Anything running as you ... your wallets"). Only install software you trust.
- **A lost seed.** debsway does not back it up, and cannot.
- **Privacy about which addresses are yours.** Like most wallets, Electrum has to ask some server about your addresses to learn your balance. The script does not set up Tor or your own server, so it makes no promise about this. Decide that yourself inside Electrum.
- **Debian's version being a bit behind** the newest release.
- **Someone with your unlocked, running laptop.** A computer that is on and unlocked is open. Lock it (Super+Escape) or shut it down.

## Removing it

`bash extras/electrum.sh --remove` removes the `electrum` and `python3-electrum` packages (through the marker package) and anything that only they needed. It keeps `~/.electrum`, with your wallets. It tells you so and says to back them up before deleting anything.
