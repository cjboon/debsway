# A keyring that unlocks when you log in (`extras/seahorse.sh`)

You get Seahorse ("Passwords and Keys"), a program for looking at stored secrets, and the GNOME keyring behind it. The keyring is unlocked with your login password when you log in on the console, so programs that store a secret there, such as GitHub's `gh`, do not ask again.

## The problem it solves

Some programs need to remember a secret for you, such as a login token. Storing it in a plain file is unsafe, and asking you every time is tiresome. A keyring is a place where the system keeps such secrets encrypted, and hands them to programs when it is unlocked.

## The ideas behind it

**A keyring.** An encrypted store for small secrets (passwords, tokens, keys). It is locked until you give it the right password.

**GNOME keyring and Seahorse.** `gnome-keyring` is the program that holds the keyring. Seahorse is its window, for browsing and managing what is stored.

**Unlocking with your login password.** If the keyring's password is the same as your login password, the system can unlock it for you at the moment you log in, because it has just seen your password.

**PAM.** The system that checks your password when you log in. It is configured by files in `/etc/pam.d/`, and `login` is the one used for a console login (debsway starts sway from a console login on tty1). A PAM module is a small plug-in that runs at that step. `pam_gnome_keyring.so` is the plug-in that passes your password to the keyring.

**A keyring is not a password manager.** KeePassXC (`extras/keepassxc.sh`) keeps your own passwords in a file you control. This keyring is mainly for programs that save their own secrets.

## How it works, step by step

When you run `bash extras/seahorse.sh`:

1. It installs `seahorse`, `gnome-keyring` and `libpam-gnome-keyring`.
2. It copies `/etc/pam.d/login` to `/etc/pam.d/login.debsway.bak`, unless that backup already exists.
3. It adds two lines to `/etc/pam.d/login`: `auth optional pam_gnome_keyring.so`, right after the `@include common-auth` line, and `session optional pam_gnome_keyring.so auto_start`, right after the `@include common-session` line. They are marked `optional`, so a failure in the module does not stop you logging in.
4. It checks both lines landed. If not, it puts the original file back and stops. A broken login PAM file could lock you out of console logins.
5. It shows the lines and warns you: before you log out, check that logging in still works by pressing Ctrl+Alt+F2 and logging in there. To undo by hand: `sudo cp /etc/pam.d/login.debsway.bak /etc/pam.d/login`.

It takes effect at your next console login. Running it again does not add the lines twice.

## What it changes on your computer

- Packages: `seahorse`, `gnome-keyring`, `libpam-gnome-keyring`.
- `/etc/pam.d/login` (two lines added) and the backup `/etc/pam.d/login.debsway.bak`.
- Later, your keyrings in `~/.local/share/keyrings` (made by the keyring, not by the script).

## Using it

- `seahorse`: see and manage stored passwords and keys.
- Log in on the console as usual. Nothing else to do.
- After installing, test with Ctrl+Alt+F2 before logging out of your only session.

## What it protects against

- **Secrets left in plain text files.** Programs that use the keyring store them encrypted.
- **Stored secrets being read while you are logged out or the computer is off.** They are encrypted at rest, with a key derived from your password.

## What it doesn't protect against

- **Anything running as you after you log in.** Once the keyring is unlocked, a program running as you can ask for its secrets. This is a convenience, not a wall.
- **A weak login password.** The keyring is only as strong as it.
- **Logins that do not go through `/etc/pam.d/login`.** The keyring is unlocked at a console login. This script does not change other logins (a graphical login manager or ssh).
- **A password manager's job.** It does not generate or organise your passwords like KeePassXC.
- **Mistakes in `/etc/pam.d/login`.** The script checks its edit, but if you cannot log in afterwards, use the backup.

## Removing it

`bash extras/seahorse.sh --remove` takes the two keyring lines out of `/etc/pam.d/login` and purges `seahorse`, `gnome-keyring` and `libpam-gnome-keyring`, unless another extra needs them. The backup file `login.debsway.bak` is not deleted. Your keyrings stay in `~/.local/share/keyrings`; programs that saved secrets there, such as `gh`, will ask you to log in again.
