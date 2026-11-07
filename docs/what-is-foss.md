# What is free and open source software?

Most of the software that runs the modern world can be read, changed and shared by anyone, and
much of it was written by people who gave it away. That sounds as if it shouldn't work. It has
worked for over forty years, and you are probably using it right now.

**FOSS** stands for **free and open source software**. Wren Linux is FOSS, and so is nearly
everything under it.

## What it means

"Free" here means freedom, not price. The usual saying is "free as in free speech, not as in free
beer." The Free Software Foundation's definition is four freedoms:

0. **To run the program,** for any purpose.
1. **To study how it works, and change it.** That needs the source code, the form people write it in.
2. **To share copies** with others.
3. **To share your changed versions,** so that others gain from them too.

(They are numbered from zero. Programmers do that.)

Software that doesn't give you these is called **proprietary**. You may use it on the owner's terms,
you can't see inside it, and it may stop working when the owner decides.

### "Free software" or "open source"?

They describe nearly the same programs, from two points of view:

- **Free software** speaks of users' rights. It says you should control the programs you use, as a
  matter of right and wrong.
- **Open source** speaks of results. It says that working in the open makes better software.

Some people hold firmly to one word or the other, for good reasons. "FOSS" is a way to mean both.

### Two kinds of license

A license is what turns these ideas into law. Nearly all of them fall into two families:

| Kind | What it says | Examples |
|---|---|---|
| **Copyleft** | You may change and share it, but what you share must stay just as free | GPL (Linux, GCC, Bash) |
| **Permissive** | Do nearly anything, even put it in a closed product. Keep the notice | MIT (Wren Linux), BSD, Apache |

Copyleft keeps improvements in the open. Permissive licenses get a program used as widely as
possible. Both are FOSS.

**Not everything you can read is FOSS.** "Source available" licenses show you the code but limit what
you can do with it, often forbidding competition. Check the license, not the word on the website.

## A short history

**Before it had a name.** Early programmers shared code as a matter of course, as scientists share
results. In the 1970s, Unix spread through universities with its source, and Berkeley's changes to
it became BSD. As software turned into a business, in the late 1970s and 1980s, the sharing shrank.

**1983: GNU.** Richard Stallman, a programmer at MIT, announced the GNU project on September 27, 1983:
a complete operating system, like Unix, that everyone would be free to use and change. The name
stands for "GNU's Not Unix".

**1985: the Free Software Foundation,** to support that work.

**1989: the GPL.** The GNU General Public License used copyright against itself. It says: you may share
and change this, as long as you give others the same rights. This idea is called copyleft.

**1991: Linux.** By then GNU had nearly everything except the kernel, the core that runs the hardware.
Linus Torvalds, a student in Helsinki, announced his as a hobby: "just a hobby, won't be big and
professional". Under the GPL, GNU's tools and his kernel made a whole free system.

**1993: Debian.** Ian Murdock started a system put together by volunteers, and it is still going
([its history](history-of-debian.md)). Its Free Software Guidelines later became the basis of the
Open Source Definition.

**1995 onward: the web.** The Apache web server, MySQL, PHP and Linux became the cheap, common way to
build a website, which is a large part of why small players could build on the web at all.

**1998: "open source".** Netscape announced it would release its browser's source, the code that later
became Firefox. A group meeting that February looked for a name that wouldn't confuse people about
price or put off businesses. "Open source" is usually credited to Christine Peterson, though accounts
differ on the details. Eric Raymond and Bruce Perens founded the Open Source Initiative.

**2005: Git.** A dispute over the tool Linux's developers used led Linus Torvalds to write his own in a
few weeks. Git now holds most of the world's code, Wren Linux's included.

**2008: Android.** The most used phone system in the world came out, built on the Linux kernel.

**Since then,** the companies that once fought FOSS have become among its biggest contributors. Linux
has run all of the 500 fastest supercomputers on the [TOP500](https://top500.org/) list since November
2017.

## What it has built

You rely on these whether you know their names or not.

**The web and the internet**

- Linux runs most of the servers behind the websites you visit.
- nginx and Apache serve a huge share of the world's pages.
- OpenSSL and its relatives encrypt much of what travels across the internet.
- Let's Encrypt, a nonprofit using open software, made free HTTPS certificates ordinary.
- curl, a small tool for fetching things, is built into a vast number of devices and programs.

**Phones and devices**

- Android is built on the Linux kernel, and billions of phones run it. (Parts of the Android most people
  have are closed: Google's apps and services, and much of the drivers.)
- Linux is inside televisions, routers, cars and countless other machines.
- SQLite, a small database in the public domain, is on nearly every phone and in most browsers.

**The cloud and big science**

- Most of the rented computers that make up "the cloud" run Linux.
- Kubernetes, which started at Google, is how many companies run their programs across many machines.
- PostgreSQL holds the data of banks, governments and startups.
- Python, with its open libraries, is the common language of science and data work.
- Every computer on the TOP500 supercomputer list runs Linux: weather, medicine, physics.

**Everyday tools**

- Firefox, and Chromium, the open project under Chrome and Edge.
- LibreOffice, GIMP, Inkscape, Krita and Blender, the last of which has been used on professional films.
- VLC, which plays almost anything.
- Git, GCC and LLVM: most software, closed or open, is made with free tools.

**Privacy and safety**

- Tor, OpenSSH, GnuPG, WireGuard, KeePassXC and Signal's apps.
- Tails, Whonix and Qubes OS.
- Bitcoin and Monero, where anyone can check the rules.

## Why it matters for your safety

If you can't read a program, you have to trust its maker. That means trusting their honesty, their
security, and anyone who can lean on them, including a government.

FOSS changes that in ways that matter most to people who can't afford misplaced trust:

- **It can be checked.** Anyone can read the code, and hire someone to if they can't themselves. A hidden
  backdoor can be found, and a false promise exposed.
- **It can be forked.** If a project goes bad, is bought or is pressured, anyone may copy it and carry
  on. This has really happened: LibreOffice from OpenOffice, and Valkey from Redis.
- **It can't easily be taken away.** No company can switch it off, or forbid you from using it in your
  country. Copies live all over the world.
- **It can be adapted and translated** by the people who need it, in their own language and for their own
  situation, without asking for permission.
- **It can be rebuilt.** With reproducible builds, anyone can check that a program was really made from
  the published source.

## What it asks of public policy

The same ideas apply to governments and institutions, and a movement argues for them.

**"Public money, public code."** This is the campaign of the Free Software Foundation Europe, begun in
2017: software paid for by the public should be available to the public. It's reasonable to ask that
what taxes pay for is open to inspection, reusable by other towns and countries, and not tied
to one company for ever.

**Digital sovereignty.** A country whose schools and offices depend on a foreign company's closed software
depends on that company, and on that company's government.

**Some of what has happened:**

- **The United States** set a Federal Source Code Policy in 2016, asking agencies to share custom code
  between them and to release some of it to the public.
- **Schleswig-Holstein,** a German state, decided to move its government's 30,000 computers from Windows
  and Microsoft Office to Linux and LibreOffice, and its coalition agreement names "public money, public
  code".
- **Munich** shows it isn't simple. The city moved to Linux, then voted to go back to Windows in 2017, and
  later said it wanted open source again. Moving a whole organisation depends on politics and
  support as much as on software.
- **The European Union's Cyber Resilience Act** (2024) sets security rules for software sold in Europe, and
  was written, after protests from FOSS projects, to treat non-commercial work and the foundations that
  look after it differently from companies selling products.

**Science and education** gain too. Research whose code can be read can be checked, and a student can see
how real systems work, for free, in any country.

## Where it falls short

FOSS isn't magic, and a page in a security project shouldn't pretend it is.

**Open doesn't mean someone has looked.** "Many eyes" only help if the eyes are really there. In 2014,
**Heartbleed**, a bug in OpenSSL, exposed private data across the internet. The library that much of the
web depended on had very few people working on it and little money.

**Small projects hold up big ones.** In 2021, **Log4Shell**, a flaw in one free logging library, put a large
share of the world's Java systems at risk. Enormous companies had built on the work of a few volunteers.

**Trust can be attacked, slowly.** In March 2024, Andres Freund noticed that logins on his computer were
a fraction of a second slow, and found a **backdoor in xz**, a compression library used across Linux. Someone
calling themselves "Jia Tan" had spent years earning a tired volunteer's trust, and become a maintainer.
The backdoor had reached only test versions of some systems, and Debian's stable release never got it.

Read that one both ways. It was very nearly a disaster, and it shows that the people who write this software
are a target. It was also caught, by someone outside the project, reading public code. Inside a closed
product, nobody but its maker could have looked.

**Maintainers burn out.** Much of this is kept going by a few unpaid people, who get more demands than thanks.

**Companies can change the deal.** A company that owns a project can relicense its future versions, as
HashiCorp did with Terraform in 2023 and Redis did in 2024. The old code stays free, and people have forked it
(OpenTofu, Valkey), but it's disruptive.

**Hardware still isn't open.** Firmware, the small programs inside Wi-Fi cards, processors and phones, is
usually closed, even on a fully free system. And a free program can still have a design you don't like.

**It can be harder to use,** and it depends on people's spare time. That is one reason projects like this one exist.

## Wren Linux and FOSS

- **Wren Linux is under the [MIT license](../LICENSE).** You may read it, change it and share it, even in
  ways we'd never choose. The pictures in `data/wallpapers/` each keep their own license.
- **It stands on Debian, Linux and GNU,** and on the many programs named above. Very little here is new:
  mostly careful settings for other people's excellent work.
- **It's written to be read.** Its scripts are plain enough for you to check what they do before you run
  them. [THREAT-MODEL.md](../THREAT-MODEL.md) says what it doesn't protect against.
- **Not everything it offers is FOSS,** and you should know that. Some Wi-Fi firmware is closed, and the
  `claude-code` and `claude-vm` extras install Claude Code, which isn't open source. Those are optional.
- **Being open doesn't excuse you from checking.** The signature on each update tells you who published it.
  Your own reading, or someone's you trust, is what tells you whether it's any good.

## How to help

You don't have to be a programmer:

- **Report bugs** clearly, with how to make them happen.
- **Improve the documents,** or translate them. If something took you a while to understand, you are the
  right person to explain it.
- **Give money** to a project or a maintainer you depend on, if you can. It is often less than you'd think
  and matters more.
- **Be kind.** Remember that the person on the other end may be doing this at night, for nothing.
- **Ask for it:** ask your school, library or local government what they run, and why.

[CONTRIBUTING.md](../CONTRIBUTING.md) says how to help with Wren Linux.

## To read more

- [What is free software?](https://www.gnu.org/philosophy/free-sw.html), the Free Software Foundation
- [The initial GNU announcement](https://www.gnu.org/gnu/initial-announcement.html), from 1983
- [The Open Source Definition](https://opensource.org/osd), the Open Source Initiative
- [Public Money, Public Code](https://publiccode.eu/), the Free Software Foundation Europe
- [What Debian is](what-is-debian.md), and [a short history of Tor](history-of-tor.md)
