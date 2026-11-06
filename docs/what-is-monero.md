# What is Monero?

Monero (XMR) is a cryptocurrency built to keep payments private. On most cryptocurrencies, every
payment sits on a public record that anyone can read forever. Monero's record hides who paid, who
was paid, and how much.

This page explains how, and where that privacy ends. It isn't advice to buy anything. Monero's
value can swing a lot, and money you send can't be recovered if you make a mistake.

## Why privacy in money matters

Bitcoin isn't anonymous. Its record is public, so once one of your addresses is linked to you, by an
exchange or a delivery address for instance, your other payments can often be traced. Anyone you
pay may be able to see what you hold.

That also makes coins unequal: a coin with a history someone dislikes can be refused. Monero's aim is
that every coin looks like any other, as cash does. That's called *fungibility*.

## How it hides things

Three ideas do most of the work:

- **Stealth addresses hide who was paid.** You can publish one address, but each payment goes to a new
  one-time address made for that payment. Nobody else can link those to you or to each other.
- **Ring signatures hide who paid.** A payment is signed with your coins mixed among others from the
  record, used as decoys. It proves one of them is being spent, without showing which.
- **RingCT hides how much.** It conceals the amount, while still letting everyone check that no
  money was made from nothing. It went live in January 2017, and has been required since later that year.

Privacy is on for everyone, always. In a system where it's optional, using it can stand out.

Monero launched in April 2014, with no coins set aside for its founders beforehand. Its supply doesn't
stop: since May 2022, each new block pays miners a small fixed reward of about 0.6 XMR, so they keep
being paid to secure the network. Mining uses RandomX, designed to run well on ordinary computers.

## Where the privacy ends

- **Buying it can link it to you.** An exchange that knows your name knows you bought Monero, and
  where you withdrew it to. Coins can stay private after that, but that purchase isn't.
- **Your network can see you use it.** Your wallet talks to the network. Without Tor, your network, and
  any server your wallet uses, can see your address.
- **Decoys can be weaker than they look.** Researchers have shown real coins could be picked out,
  sometimes by their age, and through past bugs in how wallets chose decoys. Some of this has been
  fixed, and some was mainly about older transactions. Treat Monero's privacy as strong and improving,
  not as perfect. The project has been planning to replace ring signatures altogether, so check
  the current state on its site.
- **The person you pay knows what you paid them,** and may know who you are.
- **Your device is the weak spot.** Malware on your computer sees your wallet, whatever the math says.
- **Your wallet's words are the money.** The seed words open your wallet. Anyone who sees them can take
  everything, and nobody can undo it. Write them on paper or metal, never in a photo or a chat.
- **It may be hard to get, or restricted.** Some exchanges don't list it, and rules differ by country.
  Know yours.

## In Wren Linux

- **Whonix's Workstation is the safest place Wren Linux has:** it comes with Feather, so a hacked wallet
  can't learn your real address or reach your files (`wrenctl install whonix`). Its limits are on
  [its page](extras/whonix.md). Note that a program running as you could read the VM's disk.
- **Feather on your own desktop,** which can use Tor: `wrenctl install feather-wallet`. It runs as you, so
  it isn't walled off from your files.

Whichever you use, check the receiving address before you send. A hacked wallet could show a false one.
Start with a small amount, and restore your seed words once while it's small, so you know they work.

## Sources

- Monero Project: [What is Monero?](https://www.getmonero.org/get-started/what-is-monero/),
  [about](https://www.getmonero.org/resources/about/),
  [stealth addresses](https://www.getmonero.org/resources/moneropedia/stealthaddress.html),
  [RingCT](https://www.getmonero.org/resources/moneropedia/ringCT.html),
  [tail emission](https://www.getmonero.org/resources/moneropedia/tail-emission.html),
  [technical specs](https://docs.getmonero.org/technical-specs/). These are the project's own pages.
- On its limits: Möser and others, [An Empirical Analysis of Traceability in the Monero
  Blockchain](https://alphaxiv.org/abs/1704.04299), the project's
  [response](https://getmonero.org/2018/03/29/response-to-an-empirical-analysis-of-traceability.html), and
  [Monero Traceability Heuristics](https://arxiv.org/html/2408.05332v1).
