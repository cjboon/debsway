# Good passwords, and how to keep them

Encryption is only as strong as the password that opens it. A disk, a backup or a password
manager can use the best encryption there is, and a weak password still hands it all over.

The good news is that this is one of the cheapest protections you will ever get. You need to
remember only a few passwords, and a computer can make those few very strong.

**In short:**

- Remember a few long passphrases, made of random words: `diceware -n 7`.
- Let a password manager remember everything else: `wrenctl install keepassxc`.
- Never use one password in two places.
- Don't change passwords on a schedule. Change one when you have a reason to.

## Why it matters

**Most break-ins don't crack anything.** Someone takes a password that leaked from one site and
tries it on your email. Websites are breached all the time, and those lists get tried everywhere,
by machines. If every password you have is different, a leak costs you one account.

**Your email is the master key.** Whoever controls it can reset most of your other passwords, so
it deserves one of your best.

**A stolen laptop gives the attacker all the time in the world.** A website can lock someone out
after a few wrong tries. An encrypted disk or a copied password file can't: the attacker can
guess on their own machines, as fast as they can afford, for years.

That is the case the rest of this page is about, and if you are at risk from someone powerful, it
is the one to plan for.

## Why random words

A good passphrase isn't clever. It is **random**. People are bad at this: we pick names, dates,
song lyrics, and swap an `a` for `@`. Attackers know all those tricks, and their tools try them
first. `Tr0ub4dor&3` looks strong to you, and looks familiar to them.

`diceware` picks words at random from a list of 7776, using your computer's secure random source.
The base install of Wren Linux has it already.

```
$ diceware -n 7 --no-caps -d ' '
```

That prints seven random words with spaces between them. Plain `diceware -n 7` joins them with
capital letters instead, like `CedarOutlookUnpackedRiverbed...`. Both are equally strong, so use
whichever you find easier to type. Spaces are usually easier.

**The word list is public, and that's fine.** The secret is which words were picked. Each word adds
the same amount of strength, about 12.9 "bits", and each bit doubles the attacker's work.

## How strong is it?

The attacker knows you used `diceware` and has its list, so this is the honest number. These are
average times to find it, trying half of all the possibilities:

| Words | Possibilities | Strength | A slow, protected password (10,000 guesses a second) | A fast, poorly stored one (1 trillion a second) | The same, with a thousand times that (1,000 trillion a second) |
|---|---|---|---|---|---|
| `diceware -n 6` | 2.2 × 10²³ | 77.5 bits | 350 billion years | 3,500 years | 3.5 years |
| `diceware -n 7` | 1.7 × 10²⁷ | 90.5 bits | 2.7 million billion years | 27 million years | 27,000 years |
| `diceware -n 8` | 1.3 × 10³¹ | 103.4 bits | 21 billion billion years | 210 billion years | 210 million years |

**The guessing speeds are rough figures, chosen to show the scale.** Nobody publishes what the
best-funded attackers own, and hardware gets faster. What you can rely on is the pattern: each
extra word makes the job 7776 times harder.

**Why the columns differ so much.** Good software makes every guess slow on purpose, using a lot of
time and memory for each one. Disk encryption (LUKS2) and KeePassXC can both do that. A website
that stored its passwords carelessly doesn't, and you can't tell which kind a site is.

For comparison, against that trillion guesses a second:

| Password | Strength | Average time |
|---|---|---|
| 8 random characters, all kinds of symbol | 53 bits | about an hour |
| 12 random characters, all kinds of symbol | 79 bits | about 8,600 years (a little more than 6 words) |
| A word with some numbers and symbols you chose | Far less than its length suggests | Often moments: these patterns are tried first |

Twelve random symbols are about as strong as six words, but far harder to remember and type.

## How many words for what

| What it protects | Words | Why |
|---|---|---|
| Your login and sudo password | 6 | You type it often, and the disk encryption is around it |
| Your KeePassXC master passphrase | 7 | It opens everything else |
| Encrypted backups and sticks, the vault | 7 | Copies can be taken away and attacked for years |
| Disk encryption | 7, or 8 if seizure is a real risk | A seized laptop can be kept and worked on for a long time |
| Wallets, and anything that must stay safe for decades | 8 | Nobody can say what guessing will cost in 20 years |
| Website passwords | None to remember | KeePassXC makes a long random one for each |

When in doubt, add a word. It costs you a second of typing.

**A passphrase typed at boot:** the disk passphrase is typed before your keyboard layout is set up,
so on a keyboard that isn't a US one, some symbols land elsewhere. Plain letters and spaces from
the default word list are the safest choice.

## Doing it right

- **Take the words as they come.** Throwing away lists until you like one, or swapping in a word
  of your own, makes it weaker. If you can't stand a list, make one new list and keep it.
- **Don't add anything from your life:** no names, dates or places.
- **Make it on your own computer.** Not on a website, and not on a computer you don't trust. A
  generator on a web page could keep what it shows you.
- **Use it in one place only.**
- **Don't send it,** by mail, chat or anything else, and don't keep it in a note on your computer.

**Learning one by heart** is easier than it sounds:

1. Write it on paper, and keep that with you, away from the computer.
2. Picture a small silly scene that links the words, in order.
3. Type it every day. After a week or two your fingers know it.
4. Then decide what happens to the paper.

**Forgetting is final.** Real encryption has no "forgot my password". So for what you can't afford to
lose, keep a written copy somewhere safe and away from the computer, such as a sealed envelope with
someone you trust. If people may search your home, weigh that risk: being locked out may be better
than being found out, and only you can judge which.

## How often to change them

**Don't change them on a schedule.** It's an old rule that turned out to make things worse: people
forced to change passwords make small, predictable changes, like `Summer2026!` to `Autumn2026!`. The
US standard on this, NIST SP 800-63B, says not to require it. A strong password that nobody else has
seen doesn't wear out.

**Change a password when:**

- a site tells you it was breached, or you read that it was
- you typed it on a computer you don't trust, or someone may have watched you
- someone else knew it and shouldn't any more: an ex, a former colleague, anyone you've fallen out with
- your computer or phone may have been hacked, or was out of your hands (do it from a clean computer)
- it is weak, or used in two places. That is the one to fix today

**Two catches.** Changing a passphrase doesn't reach copies made before the change:

- **KeePassXC, and backups:** an old copy of a database still opens with the old master passphrase. If
  that passphrase may have leaked and a copy may have too, change the passwords inside it as well.
- **Disk encryption:** changing the passphrase (`cryptsetup luksChangeKey`) doesn't change the key the
  disk is really encrypted with. Someone who copied the disk or its header earlier can still open
  that copy with the old passphrase.

If your computer was hacked, [the opsec guide's section on what to do when something goes
wrong](opsec.md#19-when-something-goes-wrong) says where to start: your email and password manager first.

## KeePassXC: one passphrase to remember, the rest done for you

A password manager is what makes all this possible. Nobody can remember a hundred different
strong passwords. KeePassXC remembers them in one encrypted file that you keep. Nothing goes to any
company's server.

```
wrenctl install keepassxc
keepassxc                       (or Super+d, then keepassxc)
```

**Setting it up takes a few minutes:**

1. Make a new database, and give it a master passphrase from `diceware -n 7`.
2. In its settings, look at the database's encryption: the key derivation should say **Argon2**,
   which makes each guess slow and memory-hungry. Check this if the database was made with
   `keepassxc-cli`: version 2.7.10 gives the older AES setting there, as below.
3. Add an entry for each site as you next log in to it. Its generator makes the password: 32 random
   characters is plenty. You never need to see or know it.

**Then, day to day:**

| Key | What it does |
|---|---|
| Ctrl+F | Find an entry: type a few letters of the site's name |
| Ctrl+B | Copy the user name |
| Ctrl+C | Copy the password, then paste it into the page |

It locks by itself whenever the screen locks. To change a password you click one button, and you
never have to think up another one. Its database reports can list the old, weak or reused passwords
still in there, so you can fix them a few at a time.

**In a terminal,** `keepassxc-cli` does the same with the same file, so it works on a text console or
over ssh too:

```
keepassxc-cli db-create -p -t 1000 mine.kdbx      a new database, about a second to open
keepassxc-cli open mine.kdbx                      asks once, then takes the commands below (without
                                                  the file name), until you type quit
keepassxc-cli mkdir mine.kdbx Email               a group, to keep entries in
keepassxc-cli add -u me@example.org --url https://example.org -g -L 32 mine.kdbx Email/example
                                                  an entry, with a new 32-character password
keepassxc-cli ls -R mine.kdbx                     everything in it
keepassxc-cli search mine.kdbx example            find an entry
keepassxc-cli show mine.kdbx Email/example        its details, with the password hidden
keepassxc-cli clip mine.kdbx Email/example 20     copy its password, and clear it after 20 seconds
keepassxc-cli edit -g -L 32 mine.kdbx Email/example   give it a new password
keepassxc-cli diceware -W 7                       seven random words, from KeePassXC itself
```

Each command asks for the master passphrase, and `man keepassxc-cli` has the rest. Don't use `show -s`
where anyone can see your screen: that prints the password, and it may stay in your terminal's history.

A database made this way uses the older AES key setting, however long you tell `-t` to take. Its
guesses are slow but need little memory, so special hardware is better at them than at Argon2. To
change that, open the file once in the KeePassXC window and choose Argon2 in its database settings.

**It's handy for the things around passwords, too:**

- **Security questions:** "your mother's maiden name" is a public fact. Answer with random words, and
  keep them in the entry.
- **Recovery codes** for your accounts, though a printed copy is better: you need them when
  everything else is lost.
- **Notes:** which email address an account uses, and what you answered where.

**What to know about Wren Linux's KeePassXC:**

- **It is the minimal build, `keepassxc-minimal`, with no browser add-on,** on purpose, so that no web page
  can talk to it. This also means it won't
  notice a fake site. Before you paste, look at the address yourself, and open sites you log in to
  from a bookmark, never from a link in a message.
- **The clipboard is shared** with the sandboxed Firefox while that window has focus. `incognito` doesn't
  share it. A copied password stays there until something replaces it, unless KeePassXC's settings
  clear it, so look at that setting.
- **Back up the file.** Lose it and every password in it is gone. Copy the `.kdbx` file to an encrypted
  stick (`bash encrypt-usb.sh`) and keep that somewhere else. Do it again whenever you've added something
  important. [The backup extra](extras/backup.md) can do it too, encrypted.
- **Don't keep its passphrase inside it.** That needs to be in your head, or on paper.

## A second lock

A password can be stolen however strong it is, by a fake login page or a program that watches you
type. A second factor means a stolen password isn't enough:

1. **A hardware security key** is the best. It checks the site's real address itself, so it can't be
   phished. `wrenctl install security-key` sets one up, for sudo as well if you like.
2. **An authenticator app** (TOTP codes) is good. KeePassXC can make these codes, but then the password
   and the second factor sit in one file, which weakens the "two".
3. **SMS codes** are the last resort, as phone numbers can be stolen by talking a provider into moving
   them. They're still better than nothing.

## What a strong password can't do

Be clear about what this doesn't protect against:

- **A hacked computer.** A program running as you can log what you type and read what you paste, however
  long the passphrase is. See [THREAT-MODEL.md](../THREAT-MODEL.md).
- **A computer that is on.** While it runs, or sleeps, the disk's key is in memory. Shut down before you
  leave it somewhere or cross a border.
- **Being watched.** A camera or a person behind you can see it being typed.
- **Force or the law.** Someone can threaten you, or a court can order you, to give a passphrase. No
  number of words helps with that. In some places refusing is itself a crime. The real protection is having less
  on the computer to begin with: [the opsec guide](opsec.md) has more.
- **Being fooled.** Nobody legitimate needs your password, or a code sent to your phone. Not the bank, not
  support, not your employer's IT.

## Start today, in this order

1. Install KeePassXC, and make its master passphrase with `diceware -n 7`.
2. Give your email a new password from it, and turn on a second factor.
3. Do the same for the accounts that could hurt most: bank, phone provider, work.
4. Change any password you've used in more than one place, starting with the most important.
5. Back up the database.
6. Add the rest as you next log in to them. There's no need to do it all in one day.
