# A password manager (`extras/keepassxc.sh`)

You get KeePassXC, a program that keeps all your passwords in one encrypted file, which you unlock with one strong password. It is the minimal build, with no web-browser connection, so no web page can talk to it. You copy a password and paste it, or use auto-type.

## The problem it solves

People reuse passwords or pick ones they can remember. When one site leaks them, attackers try the same password everywhere. Remembering a different long random password for every account is not possible.

## The ideas behind it

**A password manager.** A program that stores your passwords, creates strong random ones, and fills them in when you need them. You remember only one password: the one that opens the manager.

**Encryption.** Scrambling data so it can only be read with the right key. KeePassXC keeps everything in one file ending in `.kdbx`. Without the master password (and the key file, if you add one), the file is unreadable noise. You choose where it lives, and you can copy it like any file.

**Browser integration, and why it is left out.** The full KeePassXC can connect to Firefox through an add-on, so it fills in passwords for you. That connection is a door between the browser and the password manager. Debian's `keepassxc-minimal` package leaves it out, so a web page, or the sandboxed Firefox, has no way to reach the manager.

**Copy and paste, and auto-type.** You copy a password with Ctrl+C in KeePassXC and paste it into a page. Auto-type is a KeePassXC feature that types an entry's details into the window you chose.

**TOTP.** The six-digit codes that change every 30 seconds in two-factor login. KeePassXC can generate them.

**Wayland.** The window system sway uses. `qtwayland5` lets KeePassXC draw its windows on Wayland directly.

## How it works, step by step

When you run `bash extras/keepassxc.sh`:

1. It removes the full build (`keepassxc-full`), the plain `keepassxc` package and the `webext-keepassxc-browser` Firefox add-on if they are installed. It tells you if it replaces the full build.
2. It installs `keepassxc-minimal` and `qtwayland5`.
3. It tells you how to start it and how to use a password on a web page.

It makes no configuration of its own and no database. You create a database from within KeePassXC.

## What it changes on your computer

- Packages: `keepassxc-minimal`, `qtwayland5`. If present, `keepassxc-full`, `keepassxc` and `webext-keepassxc-browser` are removed.
- Nothing else: no users, services, firewall rules or settings files.

## Using it

- `keepassxc` (or Super+d): start it. The first time, create a database, choose a strong master password and save it somewhere you control.
- Ctrl+C on an entry copies its password. Paste it into the page.
- Auto-type types an entry's details into the window you pick.
- TOTP codes: add a TOTP secret to an entry and copy the code from KeePassXC.
- Keep a copy of the `.kdbx` file in your backup (see `docs/extras/backup.md`), and write the master password down somewhere safe outside the laptop.

## What it protects against

- **Reused and weak passwords.** You can use a long random one for each account.
- **A web page talking to the password manager.** There is no browser integration.
- **Someone reading the file.** The database is encrypted.

## What it doesn't protect against

- **Anything running as you.** If you run a malicious program, it can read the database file, watch the clipboard and log your master password as you type it.
- **The clipboard.** A copied password sits there until replaced. In the sandboxed Firefox, the clipboard is shared while its window has focus.
- **A weak master password**, or one you lose: the database cannot be opened without it.
- **A stolen unlocked computer.** While the database is open, its contents are in memory.
- **Phishing that you do not notice**, and sites that are already hacked.
- **Losing the file.** Back it up.

## Removing it

`bash extras/keepassxc.sh --remove` removes `keepassxc-full`, `keepassxc-minimal`, `keepassxc` and `webext-keepassxc-browser`. Your password databases (`.kdbx` files) are left where they are.
