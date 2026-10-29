# Operations security (opsec): a practical guide

Operations security, "opsec", is the habit of thinking about what you want to
keep private, who might want it, and how it could leak, and then closing the
gaps that matter. Software helps, and debsway does what it can, but most
leaks come from habits: a reused password, a photo with a location in it, a
laptop left open in a café, a name typed in the wrong window.

This guide is general. It applies whatever computer you use, and it points to
the debsway pieces that help where there are some. It doesn't make anyone
safe on its own, and nothing here is legal advice. `THREAT-MODEL.md` says
plainly what debsway itself does and doesn't protect against.

**Contents**

1. [Start with a threat model](#1-start-with-a-threat-model)
2. [Principles that apply everywhere](#2-principles-that-apply-everywhere)
3. [Your laptop](#3-your-laptop)
4. [USB drives and other storage](#4-usb-drives-and-other-storage)
5. [Networks: home, public Wi-Fi, VPNs and Tor](#5-networks-home-public-wi-fi-vpns-and-tor)
6. [Passwords and accounts](#6-passwords-and-accounts)
7. [Encryption, in plain words](#7-encryption-in-plain-words)
8. [Private communication](#8-private-communication)
9. [Web browsing](#9-web-browsing)
10. [Files, photos and metadata](#10-files-photos-and-metadata)
11. [Identity and compartments](#11-identity-and-compartments)
12. [Money](#12-money)
13. [Your phone](#13-your-phone)
14. [Physical security](#14-physical-security)
15. [People and social engineering](#15-people-and-social-engineering)
16. [Software you install](#16-software-you-install)
17. [Backups](#17-backups)
18. [Travel and borders](#18-travel-and-borders)
19. [When something goes wrong](#19-when-something-goes-wrong)
20. [Checklists](#20-checklists)

---

## 1. Start with a threat model

You can't protect everything from everyone, and trying makes life miserable
and usually makes you careless somewhere. Instead, answer five questions,
honestly, and write the answers down:

1. **What do I want to protect?** Your money, your accounts, your messages,
   your location, who you talk to, a project, your identity behind a
   pseudonym, other people who trust you.
2. **Who might want it?** A thief who takes laptops from cafés, a scammer, an
   abusive ex, an employer, a company that sells data, a stalker, a hacker
   group, a government. Each has very different abilities.
3. **How likely is it, and how bad would it be?** A stolen laptop is likely
   and annoying; a leaked source could be dangerous to someone. Spend effort
   where likelihood times harm is highest.
4. **What can they actually do?** A thief can take the hardware. A scammer
   can send convincing emails. A company can track you across websites. A
   government can demand records from your provider, or seize your devices.
5. **What am I willing to do about it?** The best plan is one you will follow
   every day. A simpler plan you keep beats a perfect one you drop.

Review the answers when your life changes: a new job, a move, a relationship
ending, travel, or something you start publishing.

Three rough levels, to place yourself:

- **Everyday privacy.** You want to avoid fraud, keep accounts safe, and not be
  tracked for advertising. Most of sections 3, 6, 9 and 17 cover you.
- **A specific adversary.** Someone particular wants your location, messages
  or accounts (a stalker, a former partner, a hostile employer). Add sections
  10, 11, 13 and 15, and think hard about who knows your routines.
- **High risk.** Journalists, activists, people with sources to protect, people
  facing a capable state. Everything here applies, and you should also get
  advice from people who work on this professionally. A well-set-up laptop is
  only one part.

## 2. Principles that apply everywhere

- **Minimise.** Data you don't have can't leak. Don't keep what you don't
  need, don't install what you don't use, don't share what nobody asked for.
- **Compartmentalise.** Keep separate things separate: separate accounts,
  browser profiles, email addresses, devices, even separate habits. When one
  compartment is broken into, the others stay closed.
- **Least privilege.** Give each program, person and account only what it
  needs. debsway runs risky programs as separate users for this reason.
- **Defence in depth.** Assume each protection will fail sometimes, and layer
  them: disk encryption, a screen lock, a firewall, a sandbox, a backup.
- **Assume compromise, plan recovery.** Ask "what if this is already
  broken?" and keep a way back: backups, recovery codes, a second contact
  channel.
- **Consistency beats intensity.** One slip can undo years of care. Build
  habits that make the safe way the easy way.
- **Don't stand out without reason.** Unusual tools and behaviour can draw
  attention. Sometimes blending in (common software, ordinary patterns) is the
  stronger protection.
- **Need to know.** The fewer people who know a secret, the fewer ways it can
  get out. That includes friends who mean well.
- **Verify, don't trust.** Check fingerprints, signatures and identities
  through a second channel, especially when something is urgent.

## 3. Your laptop

### Encryption and power

- **Encrypt the whole disk.** Without it, anyone holding the laptop can read
  everything on it by plugging the disk into another computer. On Debian this
  is "guided, use entire disk and set up encrypted LVM" in the installer (see
  the README). `bash status.sh` warns when the disk isn't encrypted. It can't
  be added later without reinstalling.
- **Use a long passphrase for it,** such as five or six random words. It's
  typed before the keyboard layout is set up, so stick to plain letters.
- **Shut down when you leave it.** Disk encryption only protects a laptop
  that is **off**. While it is on, asleep or just locked, the key is in memory,
  and a skilled attacker with the machine can sometimes get it out. Shut down
  before you leave it in a hotel room, a car, a checked bag or at a border.
  debsway's power menu is Super+Shift+Escape.
- **Lock the screen whenever you step away,** even briefly (Super+Escape).
  debsway also locks by itself after 30 minutes idle; `timer lock 5` makes
  that shorter.

### Firmware and boot

- **Set a firmware (BIOS/UEFI) password** so nobody can change the boot order
  or turn security settings off without it. Write it down somewhere safe; on
  some laptops forgetting it is expensive.
- **Boot only from the internal disk** by default, so a stranger's USB stick
  can't start another system on your machine.
- **Secure Boot** checks that the boot loader is signed. It's worth leaving
  on, but debsway doesn't measure or verify the boot chain beyond that, so it
  doesn't detect tampering with the unencrypted boot partition. If someone
  might tamper with your laptop while you're away, see "physical tampering"
  below.
- **Ports that read memory.** Old FireWire ports could read memory directly;
  debsway blocks those modules. Thunderbolt docks can carry similar risks;
  don't plug unknown docks into a laptop that matters.

### What runs on it

- **Keep it updated.** Most real attacks use known bugs that already have a
  fix. debsway installs Debian's security fixes every day; restart programs
  (and the computer, after a kernel update) when you're told to.
- **Install less.** Every program is more code that can have a hole. Remove
  what you don't use (`bash extras/NAME.sh --remove`).
- **Run risky things apart from you.** Open untrusted websites in `incognito`
  or the sandboxed `firefox`, images and videos with debsway's sandboxed `imv`
  and `mpv`, and AI coding agents in `claude-vm`. Anything running *as you* can
  read all your files.
- **Never run commands you don't understand,** especially ones copied from a
  chat or web page that start with `curl ... | bash` or ask for `sudo`.

### Radios, camera and microphone

- **Switch off what you aren't using.** Wi-Fi and Bluetooth can be turned off
  at the radio from the debsway menu; Bluetooth starts off with debsway's
  Bluetooth extra. Radios you leave on can be used to track or attack you.
- **Cover the camera** with a sliding cover or a small sticker. The light is
  not a guarantee on every model.
- **The microphone** is muted at every login with debsway's sound extra, but
  that is a software mute: a program running as you can unmute it. Headsets
  can be unplugged; built-in microphones can't, so keep sensitive talks away
  from devices you don't trust.

### Around you

- **Shoulder surfing.** People and cameras can read your screen and your
  typing. Sit with your back to a wall in public places; a privacy filter on
  the screen helps; shield passphrases as you type them.
- **Notifications** can show message contents on the screen to whoever is
  near. Turn previews off for sensitive apps.
- **Screen sharing and screenshots.** Close unrelated windows before you
  share your screen. Check screenshots for names, tabs and notifications.

### Physical tampering

If someone could have the laptop alone for a while (a hotel room, a seized bag):

- Prefer that it's **off** (encryption on) rather than asleep.
- **Tamper evidence:** photograph the screws on the bottom, or paint them with
  glittery nail polish and photograph the pattern; compare when you return.
  This doesn't stop tampering, it tells you it may have happened.
- If you suspect tampering, **don't type your passphrases into it.** Treat it
  as compromised (section 19).

### Getting rid of a laptop or disk

- With full disk encryption, destroying the encryption header makes the data
  unreadable: `cryptsetup erase` on the encrypted partition, then reinstall or
  wipe. On SSDs, "deleting" or overwriting files doesn't reliably remove them,
  which is one more reason to encrypt from day one.
- When in doubt, keep or physically destroy the disk and sell the laptop
  without it.

## 4. USB drives and other storage

- **Treat unknown USB devices as hostile.** A stick found in a car park, a
  "free" promotional stick or a cable from a stranger can attack a computer:
  some pretend to be a keyboard and type commands (BadUSB), some carry files
  meant to exploit the code that reads them. debsway mounts drives so nothing
  on them can run (`noexec`), but the kernel still reads whatever a stick
  contains. Don't plug in sticks you don't trust.
- **Encrypt sticks and external disks** that hold anything private (LUKS on
  Linux; debsway's USB automount asks for the passphrase). A lost stick is then
  just a lost stick.
- **"Deleted" isn't gone** on USB sticks and SSDs: wear levelling keeps old
  copies the computer can't reach but a lab can. Encrypt first instead of
  relying on deleting.
- **Charging:** public USB charging points can carry data. Use your own
  charger, or a "data blocker" adapter that passes only power.
- **Label and keep track** of your drives; know which ones hold what. Don't
  carry backups and the computer they back up in the same bag.
- **Phones are USB devices too.** Plugging your phone into an unknown computer,
  or an unknown phone into yours, shares more than charge.

## 5. Networks: home, public Wi-Fi, VPNs and Tor

### What a network can see

Whoever runs the network you use (your home router, a café, your mobile
provider, your internet provider) sees **who you talk to, when and how much**,
even when the content is encrypted. Without extra steps they see:

- the **names** of the sites you visit (through DNS lookups, and in the first
  message of most HTTPS connections);
- your **IP address**, which can be linked to your account with the provider;
- **unencrypted traffic** in full (rare now: HTTPS-Only Mode in debsway's
  Firefox refuses it unless you agree).

### Your home network

- Change the router's admin password, keep its firmware updated, use WPA3 (or
  WPA2 with a long password), turn off WPS and UPnP.
- Put visitors and "smart" devices (TVs, speakers, cameras) on a guest network.
- Know which devices are on it; unknown ones are worth looking into.

### Public Wi-Fi

- Assume the operator and other users can watch and tamper. HTTPS protects the
  content of web pages; debsway's firewall blocks all incoming connections.
- debsway gives your laptop a new made-up hardware (MAC) address on every Wi-Fi
  connection and doesn't send its name, so networks can't easily recognise it
  from place to place.
- Wi-Fi sign-in pages are on the network itself; they don't work while
  `extras/secure-dns.sh` is on.
- A phone's hotspot or USB tethering is often safer than unknown Wi-Fi.

### DNS

Every name you look up (example.org) is a small message, normally sent
unencrypted to the network's own DNS server. `extras/secure-dns.sh` sends them
encrypted to a resolver you choose and checks the answers. The resolver you
choose then sees them instead, so choose one you trust.

### VPNs: what they do and don't

A VPN sends all your traffic through an encrypted tunnel to the VPN company's
server, which forwards it. Your local network and your internet provider see
only "this person talks to a VPN"; websites see the VPN's address instead of
yours.

- **It moves trust, it doesn't remove it.** The VPN company can now see what
  your provider used to see. Choose one with a strong record (some, like
  Mullvad, accept anonymous payment and keep no account details).
- **It doesn't make you anonymous** to sites you log into, and it doesn't stop
  tracking by cookies or browser fingerprints.
- Use its "kill switch" (Mullvad: lockdown mode) if you never want traffic to
  leave outside the tunnel.

### Tor: what it does and doesn't

Tor sends your traffic through three volunteer relays, each knowing only the
one before and after it. No single relay knows both who you are and where you
go. Tor Browser (debsway's `extras/tor-browser.sh`) is built so that all its
users look alike.

- It is **slower** than a VPN, and some sites block it.
- The **exit relay** can see unencrypted traffic: stick to HTTPS.
- Your network can see that you use Tor, unless you use a **bridge**; debsway's
  Tor tools ask about bridges before the first connection.
- **Don't log into your personal accounts** in Tor Browser if the point is
  that the activity isn't linked to you, and don't install extra add-ons
  (they make you stand out).
- **Don't open downloaded documents while online** (PDFs and office files can
  fetch things from the internet and reveal your address). Open them offline,
  or in Whonix or Tails.
- For a browser that can't reveal your address even if it is hacked, use
  Whonix (`extras/whonix.sh`).

### Mobile networks

Your phone's mobile connection tells the provider where you are, all the time,
with the phone's identity attached. See section 13.

## 6. Passwords and accounts

- **Use a password manager** (debsway's `extras/keepassxc.sh`). It remembers a
  different, random password for every site, and you remember one.
- **Never reuse passwords.** Sites get breached all the time, and a password
  that leaks from one is tried everywhere else within days.
- **Passphrases you have to remember** (the disk, the password manager, your
  computer login) should be long and random: six or more random words picked
  with dice ("diceware") beat any clever substitution you invent.
- **Turn on two-factor login (2FA)** everywhere it's offered, and prefer, in
  this order:
  1. a **hardware security key** (FIDO2/WebAuthn): it can't be phished,
     because it checks the site's real address itself;
  2. an **authenticator app** (TOTP codes; KeePassXC can make them, but then
     the password and the second factor sit in the same file, which weakens
     the "two");
  3. **SMS codes** only as a last resort: phone numbers can be stolen by
     talking a mobile provider into moving them to another SIM ("SIM
     swapping"). Ask your provider for a port-out PIN.
- **Store recovery codes** offline (printed, in a safe place). They are how you
  get back in when a phone or key is lost.
- **Your email account is the master key:** whoever controls it can reset most
  of your other passwords. Give it your strongest protection.
- **Security questions** ("your mother's maiden name") are public facts. Answer
  them with random words stored in your password manager.
- **Phishing:** never log in from a link in an email or message. Open the site
  yourself, from a bookmark or by typing the address. Be most suspicious when a
  message is urgent, frightening or flattering.
- **Log out and review sessions** now and then: most big services list the
  devices signed in to your account; remove the ones you don't recognise.
- **Use separate email addresses** (aliases) for shopping, newsletters and
  accounts that matter, so a breach or spam in one doesn't expose the others.
- **Close accounts you don't use.** Old accounts with old passwords are easy
  ways in.

## 7. Encryption, in plain words

Encryption scrambles information so that only someone with the right key can
read it. It comes in three main forms:

- **At rest:** data stored on a disk or stick, protected while the device is
  off or locked (disk encryption, encrypted backups, an encrypted password
  file).
- **In transit:** data protected on its way between you and a server (HTTPS,
  DNS over TLS). The server itself can still read it.
- **End-to-end (E2EE):** only the people talking can read it; the service in
  the middle can't (Signal, SimpleX). This is what you want for private
  conversations.

What encryption **doesn't** hide:

- **Metadata:** who talked to whom, when, how often, how much, and from where.
  Metadata alone often tells the story. Choose tools that collect less of it.
- **The endpoints:** if your device, or the other person's, is compromised, the
  message is read before encryption or after decryption.
- **What you, or they, do with the decrypted copy:** screenshots, forwards,
  backups to a cloud.

Keys and passphrases:

- **Lose the key, lose the data.** There is no "forgot my password" for real
  encryption. Keep passphrases for backups and disks written down somewhere
  safe outside the computer.
- **Verify keys.** Messengers show "safety numbers" or fingerprints; compare
  them with the other person in person or by a second channel, once, for each
  contact that matters. debsway does the same for its downloads: every outside
  program is checked against a signing key pinned by fingerprint in `pins.sh`.
- **A signature proves who made something, not that it's harmless.** It tells
  you the download is what its publisher released.

## 8. Private communication

- **Use end-to-end encrypted messengers** for anything private. Signal is
  widely used and well reviewed (it needs a phone number to register, though
  others can find you by username). SimpleX (`extras/simplex-chat.sh`) uses
  no phone number, email or user ID at all.
- **Email isn't private.** Normal email is readable by the providers on both
  ends and is stored indefinitely. Encrypted email (PGP) protects the text but
  not the subject line or who wrote to whom, and is easy to get wrong.
- **Verify contacts** the first time (safety numbers), and again if the
  messenger says the key changed. A changed key can be an innocent new phone,
  or someone in the middle.
- **Disappearing messages** limit what a lost or seized phone reveals. They
  don't stop the other side from screenshotting.
- **The weakest phone in the conversation decides.** A group chat is as private
  as its least careful member. Keep sensitive groups small and know who's in
  them.
- **Files:** send them with end-to-end encrypted tools, or OnionShare
  (`extras/onionshare.sh`) for a one-time transfer that doesn't go through any
  company. Clean metadata first (section 10).
- **Calls:** encrypted voice and video in Signal and similar apps protect the
  content; your phone's location still travels with you.
- **In person** is still the most private channel. Leave phones in another
  room for conversations that matter (a phone can be made to listen).
- **Say less in writing.** Anything written can be copied, forwarded or kept
  for years. Ask: would this be all right if it were read out loud in public?

## 9. Web browsing

- **Separate your browsing** by trust: logged-in accounts that matter (bank,
  email) in their own profile (`extras/firefox-profiles/`), everyday browsing
  in the sandboxed `firefox`, unknown sites in `incognito`, anonymous browsing
  in Tor Browser. Profiles don't share cookies or logins.
- **Block third-party scripts:** most malicious ads and much tracking come from
  other sites' scripts. debsway's Firefox blocks them with uBlock Origin;
  `ublock-allow site.com` lets a site that breaks have them.
- **Fewer add-ons.** Each add-on can read every page. Install only what you
  need, from sources you trust.
- **Fingerprinting:** sites can recognise a browser by its screen size, fonts,
  settings and more, without cookies. Tor Browser and Mullvad Browser make
  everyone look alike; other browsers can only reduce it.
- **Downloads are untrusted** until you know otherwise. Open them in a sandbox
  (debsway's sandboxed browser keeps them in `~/Downloads`).
- **Links carry tracking.** Strip the part after `?` when you share a link, if
  you don't need it. Shortened links hide where they go.
- **Check the address bar** before typing anything sensitive. Lookalike domains
  are the heart of phishing.
- **Search engines** record what you search; debsway's Firefox uses DuckDuckGo
  by default.

## 10. Files, photos and metadata

Files carry information you didn't type:

- **Photos** often hold the GPS position where they were taken, the camera or
  phone model, and the exact time.
- **Documents** (PDF, Word, LibreOffice) hold author names, the software used,
  edit history and sometimes deleted text, comments and tracked changes.
- **Screenshots** show more than you meant: tabs, notifications, names in the
  corner, the time.
- **Printouts** from many colour laser printers carry tiny yellow tracking dots
  that identify the printer.
- **File names and folder paths** can contain names and dates.

What to do:

- **Clean files before sharing** with Metadata Cleaner or `mat2`
  (`extras/metadata-cleaner.sh`). Even then, look at the content itself.
- **Turn location off** in your phone's camera if you don't need it.
- **Crop and blur** with care: some tools leave the original underneath, and
  pixelating text can sometimes be undone. Paint over with solid black, then
  take a fresh screenshot of the result.
- **Your writing style** (words, spelling, punctuation, the hours you write)
  can identify you across pseudonyms. Keep separate identities from sounding
  the same.

## 11. Identity and compartments

If you keep a pseudonym, a separate work identity, or an anonymous project
apart from your name, most failures come from links between the two:

- **Never mix them** on the same account, browser profile, device, phone number,
  email address, payment method or shipping address.
- **Usernames** reused across sites link accounts in seconds.
- **Time and place:** being online at the same times, from the same networks,
  in the same time zone, links identities. Tor and VPNs hide your address, not
  your schedule.
- **Language** (a local expression, a spelling habit, a mention of the weather)
  narrows down who and where you are.
- **People:** telling someone links the two for them, and possibly anyone they
  tell.
- **Photos and files** (section 10).
- Keep separate identities in separate compartments that can't touch: a
  separate browser profile or user, better a VM (Whonix), best a separate
  device.

## 12. Money

- **Cards and bank transfers** link purchases to your name. Prepaid cards often
  do too.
- **Bitcoin is not anonymous:** every transaction is public forever, and once
  one of your addresses is linked to you (an exchange, a delivery), others can
  be traced. Sparrow (`extras/sparrow-wallet.sh`) has tools to control which
  coins you spend, and it can connect through Tor.
- **Monero** hides amounts and parties by design (`extras/feather-wallet.sh`),
  but buying it on an exchange that knows your name still links that purchase
  to you.
- **Wallet seeds** (the 12 or 24 words) *are* the money. Write them on paper or
  metal, never in a photo, a cloud note or a chat. Anyone who sees them can
  take everything.
- **Cash** is still the most private payment for physical goods.

## 13. Your phone

For many people the phone is the biggest risk: it is always on, always with
you, full of apps that collect data, and it reports its location to the mobile
network constantly.

- **Keep it updated,** and replace it when it stops getting security updates.
- **Use a strong PIN or passphrase** (six digits at least). Fingerprint and
  face unlock are convenient, but in some places you can be compelled to unlock
  with a finger or face more easily than to reveal a code; most phones can
  switch to "PIN only" quickly (a lockdown button, or restarting).
- **Fewer apps, fewer permissions.** Check which apps can see your location,
  contacts, microphone, camera and photos. Remove apps you don't use.
- **Location history** is recorded by the system and by many apps. Turn it off,
  and delete what's stored, where you can.
- **Turn it off, or leave it behind,** when where you go must not be known. A
  phone in flight mode can still record; off, or at home, is better.
- **SIM and number:** ask your provider for a PIN against your number being
  moved to another SIM. Consider a separate number for accounts that require
  one.
- **Backups** of phones often go to a cloud, sometimes unencrypted, including
  messages. Know where yours go.
- **Don't charge** at public USB points without a data blocker.

## 14. Physical security

- **Your home:** a good lock matters more than any software. Keep sensitive
  paper in a locked drawer or safe. Shred paper with names, accounts or
  addresses before throwing it away.
- **Mail and deliveries** reveal where you live and what you buy. A P.O. box or
  a pickup point helps if your address must stay private.
- **Whiteboards, sticky notes, screens visible from the window:** check what a
  visitor or a camera sees.
- **Visitors and repairs:** don't leave devices unlocked or alone with
  strangers; be present when a technician works on them.
- **Unattended devices:** in a café, a library or an office, take the laptop
  with you or shut it down. Thieves take laptops in seconds.
- **Cameras** are everywhere now: shops, doorbells, phones. Assume being seen.
- **Under pressure:** someone with power over you (a violent partner, a
  criminal, an official) may simply demand your passwords. Keep the amount of
  sensitive data on you small, and decide ahead of time what you would do.
- **Keep a spare** of what you can't afford to lose (keys, documents, backups)
  somewhere else: a trusted person's home, a bank box.

## 15. People and social engineering

Most break-ins start with a person being talked into something:

- **Urgency, fear, authority, flattery and secrecy** are the tools: "your
  account will be closed in an hour", "this is the IT department", "don't tell
  anyone yet". Slow down when you feel rushed.
- **Verify through a second channel:** if "your bank" or "your boss" asks for
  something unusual, contact them yourself, at a number or address you already
  have, not the one in the message.
- **Nobody legitimate needs your password** or a code sent to your phone. Not
  support, not the bank, not a friend.
- **Oversharing:** posts and photos reveal routines, places, friends, pets'
  names (common security answers), travel dates (an empty home).
- **Your friends' devices and posts** can reveal you too. Ask people not to
  tag or post you where that matters.
- **Insiders:** people close to you know the most. Share sensitive things only
  with those who need to know.

## 16. Software you install

- **Install from trusted sources.** Debian's own packages are signed and
  reviewed; debsway checks every outside download against a pinned key
  (`pins.sh`) and refuses anything that doesn't match.
- **Read before running,** or at least know what a script does. debsway's
  scripts are written to be read.
- **Be wary of "just paste this":** commands from forums, chats or videos can do
  anything your user (or `sudo`) can.
- **Browser add-ons, phone apps and AI tools** get deep access. Fewer is safer.
- **AI coding agents** run commands and write files. Run them where they can't
  reach your keys and documents: `claude-vm` (a separate VM) or `claude` (a
  separate user), and read what they leave before you run it.
- **Updates:** turn on automatic security updates (debsway does) and restart
  updated programs; "later" is when attacks happen.

## 17. Backups

- **Keep three copies** of what matters, on **two kinds** of storage, with
  **one** somewhere else (the "3-2-1" rule).
- **Encrypt backups** (`extras/backup.sh` uses restic, which always encrypts),
  and keep the backup passphrase outside the computer: on paper, in a safe
  place. Without it the backup is unreadable, to thieves and to you.
- **Keep one copy offline** (a disk you unplug), so a mistake, a ransomware
  attack or a bad update can't reach it.
- **Test restoring** now and then. A backup you have never restored is a hope,
  not a backup.
- **Include what you'd forget:** password manager file, wallet files, 2FA
  recovery codes, ssh keys, the onion site's key if you run one.

## 18. Travel and borders

- **Before you go:** back up, then carry less. Consider leaving sensitive data
  at home, or travelling with a clean laptop and phone.
- **At borders** officials in many countries can demand that you unlock
  devices, and the rules vary widely. Know them for where you go. Shut devices
  **down** before you reach the checkpoint, so they are encrypted at rest.
- **Hotel rooms aren't private:** take devices with you or shut them down;
  tamper evidence (section 3) shows if someone opened them.
- **Foreign networks and chargers:** use your own charger, prefer your phone's
  hotspot or a VPN, and expect some sites and tools (including Tor) to be
  blocked in some countries; bridges help.
- **After you return,** if a device was out of your sight in a risky place,
  consider it possibly compromised (section 19).

## 19. When something goes wrong

Decide some of this in advance; it's hard to think clearly in the moment.

**A lost or stolen laptop or phone:**

1. If it was off and encrypted, the data is safe; if it was on or asleep,
   assume it may not be.
2. Change the passwords of the accounts that were logged in on it, starting
   with email and the password manager.
3. Sign it out remotely: most services list devices and sessions.
4. Revoke keys that lived on it (ssh keys, a deploy key on GitHub, API tokens).
5. Restore your data from backups onto a clean device.

**An account broken into:**

1. Use recovery codes or the provider's recovery to get back in.
2. Change the password, turn on (or reset) 2FA, sign out every session.
3. Check the account's settings for things an attacker leaves behind:
   forwarding rules in email, added recovery addresses or phones, app
   passwords, connected apps.
4. Warn your contacts if messages may have been sent in your name.
5. Change the password anywhere else you used the same one (and stop doing that).

**A device that may be compromised** (it behaves strangely, it was out of your
hands, you ran something suspicious):

1. Stop typing passphrases into it.
2. From a different, clean device, change the passwords that matter.
3. Back up only your **data** (documents, not programs or settings), then
   reinstall the system from scratch. debsway is built for that: reinstall
   Debian, run `start.sh` from your stick.

**If you think you are being targeted** by someone capable, get help from
people who do this work. Organisations that support journalists and activists
often run help lines.

## 20. Checklists

**Set up once:**

- [ ] Full disk encryption, long passphrase written down safely
- [ ] Firmware password, boot from internal disk only
- [ ] Password manager, unique passwords everywhere
- [ ] 2FA on email, password manager, bank, and anything important; recovery
      codes printed and stored
- [ ] A PIN on your mobile number against SIM swapping
- [ ] Encrypted backups with an offline copy; restore tested
- [ ] Camera cover; radios off by default
- [ ] Separate browser profiles for accounts that matter
- [ ] An end-to-end encrypted messenger, contacts verified

**Every day:**

- [ ] Lock the screen when you step away; shut down when you leave the laptop
- [ ] Install updates; restart when told
- [ ] Don't open unexpected attachments or links; type addresses yourself
- [ ] Clean metadata before sharing files and photos

**Now and then:**

- [ ] Review signed-in devices and sessions on important accounts
- [ ] Review app permissions on your phone
- [ ] Test a backup restore
- [ ] Re-read your threat model: has anything changed?

---

debsway pieces mentioned here, and what each does in detail: [extras.md](extras.md),
the articles in [extras/](extras/README.md), [install-base.md](install-base.md)
and `THREAT-MODEL.md`.
