# A short history of Tor

Tor is a privacy tool used around the world, and it began in a United States Navy research lab. It
helps to know both of those things.

The dates here come from the Tor Project's [own history page](https://www.torproject.org/about/history/),
so this is the project's account of itself.

## The idea: 1995

In the mid-1990s, as the internet was becoming part of everyday life, three researchers at the U.S.
Naval Research Lab, David Goldschlag, Michael G. Reed and Paul Syverson, asked a question: could
internet connections be made in a way that didn't show who was talking to whom? Encryption can hide
what you say, but not who you're saying it to.

Their answer was **onion routing**: wrap a message in layers of encryption, and pass it through
several computers. Each one peels off a layer, and knows only the computer before it and the one
after it. No single one sees both ends.

## Tor: the early 2000s

In the early 2000s Roger Dingledine, recently graduated from MIT, began working on an onion routing
project at the lab with Paul Syverson. He called it **Tor**, for "The Onion Routing". Nick Mathewson,
a classmate of his from MIT, joined soon after.

In **October 2002** the Tor network was first deployed, and its code was released under a free
software license. By the end of 2003 it had about a dozen volunteer computers, mostly in the U.S.,
with one in Germany.

## Why it had to be public

Tor's design has a point worth understanding, even though the page above doesn't spell it out.
If only one kind of person uses an anonymity network, then being seen on it says something about
you. It works better the more ordinary people use it, for ordinary reasons. Publishing the code,
and letting volunteers run the network, is part of what makes it work.

That's also why it's reasonable to use Tor despite where it started. You don't have to take the
project's word for how it works, since the code and the design are public.

## A nonprofit, and tools for everyone: 2004 to 2008

- **2004:** the Electronic Frontier Foundation began funding Roger's and Nick's work.
- **2005:** work began on tools beyond the Tor program itself.
- **2006:** The Tor Project, Inc. was founded, as a nonprofit, to maintain Tor.
- **2007:** work began on **bridges**, unlisted ways into Tor, for people whose networks block it.
- **2008:** work began on **Tor Browser**, which made Tor usable without knowing how to set it up.

## Tor in the world: 2010 and after

The Tor Project describes Tor as an instrumental tool during the Arab Spring, starting in late 2010.
In 2013, Edward Snowden's revelations raised mainstream concern about mass surveillance. The project
says Tor was instrumental to his whistleblowing, and that the documents supported its assurances that,
at the time, Tor could not be cracked. That's about those documents, at that time. It's no promise
that Tor is unbreakable today, or for you.

Today Tor is run by thousands of volunteer relays.

## What Tor doesn't do

Tor hides your address. It doesn't hide who you are if you log in to something, and it doesn't protect
what you type into a site from that site. [Wren Linux's threat model](../THREAT-MODEL.md) and
[its opsec guide](opsec.md) say more.

## Tor in Wren Linux

- **Tor Browser**, with bridges if you need them: `wrenctl install tor-browser`
- **Whonix**, which runs your programs in a VM whose only way out is Tor: `wrenctl install whonix`
- **Your own onion site** ([what's that?](what-is-an-onion-site.md)): `wrenctl install onion-site`
- **Package downloads through Tor**, which `install-base.sh` offers before downloading anything

## Sources

- The Tor Project, [History](https://www.torproject.org/about/history/). All the names and dates above.
  The section on why it had to be public is this page's own explanation.
