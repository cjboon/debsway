# Seahorse and the keyring (`extras/seahorse.sh`)

## SYNOPSIS

```
wrenctl install seahorse                     install it (edits /etc/pam.d/login)
wrenctl remove seahorse                      take the login lines out and remove it
wrenctl manual seahorse                      print the manual steps below

seahorse            "Passwords and Keys": look at what is stored (or Super+d)
```

Programs that need to remember a secret for you, such as a login token for
`gh`, store it in a keyring: an encrypted
store that is unlocked with a password. This installs the GNOME keyring and
Seahorse ("Passwords and Keys"), from Debian, and adds two lines to
`/etc/pam.d/login`, so the keyring is unlocked with your login password when
you log in on the console, and programs don't ask again. A copy of the file
from before is kept as `/etc/pam.d/login.wren.bak`.

## LIMITS

- Once unlocked, any program running as you can ask the keyring for its secrets.
- The keyring is only as strong as your login password.
- A mistake in `/etc/pam.d/login` can lock you out of console logins: check a login on another console before logging out.

## MANUAL INSTALL

```
# The keyring, its PAM module, and Seahorse
sudo apt install --no-install-recommends seahorse gnome-keyring libpam-gnome-keyring

# A copy of the login settings, to put back if something goes wrong
sudo cp -a /etc/pam.d/login /etc/pam.d/login.wren.bak
# Unlock the keyring with your password at login: one line after the
# "@include common-auth" line, one after "@include common-session"
sudo sed -i '/^@include common-auth/a auth       optional   pam_gnome_keyring.so' /etc/pam.d/login
sudo sed -i '/^@include common-session/a session    optional   pam_gnome_keyring.so auto_start' /etc/pam.d/login
# Both lines must be there
sudo grep -n gnome_keyring /etc/pam.d/login

# Before you log out: press Ctrl+Alt+F2 and check you can still log in there.
# If you can't, put the old file back:
#   sudo cp /etc/pam.d/login.wren.bak /etc/pam.d/login
```

To undo:

```
# Take the two keyring lines out of the login settings
sudo sed -i '/pam_gnome_keyring\.so/d' /etc/pam.d/login
# Remove the keyring and Seahorse
sudo apt purge seahorse gnome-keyring libpam-gnome-keyring
sudo apt autoremove --purge
```
