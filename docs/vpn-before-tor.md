# A VPN before Tor: keeping your records away from your ISP

Your internet provider knows your name and address, and it carries everything you send. In the
United States it can be made to hand over what it knows, and in some cases forbidden to tell you.
This page gives that history, then explains one way to reduce what your provider has to hand over:
Mullvad VPN, with a Tor bridge and Whonix inside it.

The Tor Project and Whonix don't generally recommend adding a VPN to Tor, and this page says why.
For this one concern, your provider's records, it can still make sense. It isn't legal advice. If
you're in real legal danger, talk to a lawyer: the [EFF](https://www.eff.org/) is one place to ask.

## What has happened in the US

**A small ISP and an 11-year gag.** In 2004 the FBI sent Nicholas Merrill, who ran a small New York
provider called Calyx, a National Security Letter: a demand that needs no judge's signature. It
asked about one customer, including addresses, phone numbers, screen names, billing records,
email addresses, and location data from cell towers for their calls. Merrill fought it in court,
and the FBI later dropped its demand, but the gag stayed. He could say he had received the letter
only in 2010, and a court lifted the gag in full only in 2015.

**A secret room at AT&T.** In 2006 Mark Klein, a former AT&T technician, came forward with
documents showing AT&T copying internet traffic into a room in San Francisco that was controlled
by the NSA. The EFF sued AT&T for its customers. In 2008 Congress passed the FISA Amendments Act,
which gave the phone companies retroactive immunity, and the case was dismissed in 2009 because of
it. The Supreme Court declined to hear it in 2012. So a judge never ruled on what AT&T had done.

**Every call record at Verizon.** In 2013 a leak published a secret court order dated April 25 of
that year. It told Verizon Business Network Services to give the NSA its records of calls within
the US and between the US and abroad, "on an ongoing daily basis". These were phone records, not
internet ones, and the order left out what was said and the customer's name. It also said that "no
person shall disclose to any other person that the FBI or NSA has sought or obtained tangible
things under this Order", apart from a few exceptions such as a lawyer. Only the leak made it
public. In 2015 a federal appeals court found that the law cited didn't authorize that bulk
collection, and the USA Freedom Act replaced it with requests tied to a specific target.

## What the law allows today

These are the main US tools, in brief, and each has more conditions than fit here:

| Tool | Who decides | What the provider gives | Can it be kept secret? |
|---|---|---|---|
| Subpoena ([18 USC 2703](https://www.law.cornell.edu/uscode/text/18/2703)) | No judge needed for an administrative or grand jury subpoena | Your name and address, times and lengths of sessions, your temporary network addresses, how you pay | Sometimes, by a separate court order |
| Preservation request (2703(f)) | The government asks | Nothing yet: it must keep what it has for 90 days, and that can be renewed | Often not told to you |
| Pen register order ([18 USC 3123](https://www.law.cornell.edu/uscode/text/18/3123)) | A judge, on a lawyer's statement that it is relevant to an investigation | From then on, who your connections go to, not their content, for up to 60 days at a time, renewable | Yes: the order is sealed and the provider may not reveal it |
| National Security Letter ([18 USC 2709](https://www.law.cornell.edu/uscode/text/18/2709)) | A senior FBI official, with no judge | Subscriber information, toll billing records, and transaction records | Yes, if the FBI certifies a listed harm. A court can review it |

Most providers aren't villains in this. They must obey, and you may never learn that they did.
That is why it helps to reduce what they have in the first place.

## What each party sees

| Who | Without a VPN | With a VPN |
|---|---|---|
| **Your ISP** | Your name, when you're online, how much data moves, the address of your bridge, and where the rest of this computer connects | Your name, when you're online, how much data moves, and the address of one Mullvad server |
| **Mullvad** | Nothing | Your home address while connected, your bridge's address, how much data moves, and where the rest of this computer connects |
| **Your bridge** | Your home address, and that you use Tor | The Mullvad server's address, and that a Tor user connected |
| **Sites you visit in Whonix** | A Tor exit, not you | A Tor exit, not you |

The VPN wraps all of this computer's traffic: updates, ordinary browsing and Whonix alike. That
wider cover is probably its biggest benefit if your provider is your concern. Webtunnel alone
already makes your Tor connection look like ordinary web traffic, and secure DNS hides your name
lookups, but neither covers the rest. Site names often still show at the start of ordinary
connections, for example.

## What it doesn't do

- **It doesn't make Tor more anonymous.** Tor's protection comes from its circuits, and a VPN in
  front doesn't change them.
- **Your provider still sees some things.** It can see that you use a VPN, when you're online, and
  how much data you move. A VPN can also draw attention, and in some countries it is a risk itself.
- **It doesn't stop timing analysis.** Someone able to watch both your connection and the far end
  may be able to match them up by timing and volume.
- **It moves trust, it doesn't remove it.** Mullvad takes your provider's place as the one who knows
  your address. The record moves to a company that says it doesn't keep it.
- **It doesn't protect your identity elsewhere.** It doesn't change what you log in to or reveal,
  and it covers only this computer, not your phone. Those habits matter more: see the
  [opsec guide](opsec.md).

## Why Mullvad, and what you'd be trusting

Other VPNs may suit you too. Mullvad is what Wren Linux installs (`wrenctl install mullvad-vpn`).

- **Logs:** [its policy](https://mullvad.net/en/help/no-logging-data-policy) says it logs no traffic,
  DNS requests, connection times, IP addresses or per-user bandwidth. It keeps your account number
  and expiry date, and payment records. You can't check that from outside.
- **A real test of that:** [on April 18, 2023](https://mullvad.net/en/blog/2023/4/20/mullvad-vpn-was-subject-to-a-search-warrant-customer-data-not-compromised/)
  Swedish police came to its office with a search warrant, intending to seize computers with
  customer data. By Mullvad's account they left with nothing, because "such customer data did not
  exist". That is one good sign, reported by Mullvad itself. It isn't proof.
- **Its limits:** a no-logs policy says what a company keeps, not what it could be ordered to start
  watching. Mullvad answers to Swedish law, and [many of its servers](https://mullvad.net/en/servers)
  are rented from other companies.
- **Paying:** it [accepts Monero](https://mullvad.net/en/blog/we-now-accept-monero), which weakens the
  link between your name and your account, as long as the Monero wasn't bought in your name and
  sent straight there. See [What Monero is](what-is-monero.md). It doesn't hide your address from
  Mullvad while you're connected.

## What the Tor Project and Whonix say

[The Tor Project](https://support.torproject.org/faq/faq-5/) warns that a VPN can "reduce anonymity
or break Tor's protections if not configured correctly", and doesn't generally recommend one unless
you can configure both without compromising your privacy. They also offer bridges for hiding Tor
from your network, which is what webtunnel does.

[Whonix](https://www.whonix.org/wiki/Tunnels/Connecting_to_a_VPN_before_Tor) treats a VPN before Tor
as optional and community-supported. It warns you to understand the risks, and that a VPN on the
host can drop and may not fail closed: when it drops, traffic goes out directly unless something
stops it. That is the reason for lockdown mode below.

So this page doesn't disagree with them about anonymity. It answers a narrower question.

## Do you need it?

| What worries you | What helps |
|---|---|
| Your ISP knowing you use Tor | Webtunnel already covers much of this |
| A bridge operator learning your address | A VPN really helps |
| Your ISP's records of everything this computer does | A VPN really helps |
| Being found by a powerful adversary | A VPN changes little. Your habits matter most |

## How to set it up on Wren Linux

```
wrenctl install mullvad-vpn
mullvad account login 1234123412341234    your own account number
mullvad relay set location se             one country and stay there (se = Sweden)
mullvad lockdown-mode set on              no internet at all while the VPN is off
mullvad auto-connect set on               connect whenever the laptop starts
mullvad connect
mullvad status                            it should say Connected
whonix
```

- **Pick one server outside the US, and stay on it.** A server in the US leaves its data centre under
  the same US law this page is about.
- **Don't hop between countries.** Privacy laws limit what a company can be forced to do. They don't
  stop someone with access to the network from watching it. Each hop adds another data centre that
  can see you and another dropped connection, and drops are when mistakes happen.
- **Keep lockdown mode on, and leave the VPN on all the time.** Switching it on only for Whonix leaves
  a pattern in your provider's records.
- **Keep your bridge.** With webtunnel, Mullvad sees an ordinary-looking web connection rather than Tor.
- **If the bridge won't connect,** try another Mullvad server or another bridge.

### Why it should work

On Wren Linux the Gateway's network runs through `passt`, an ordinary program on this computer, and
its connections leave the way any other program's do. So they go through the VPN, and lockdown mode
should block them when the VPN is down. A bridge that has to look up names does that through this
computer's resolver.

**Not tested by Wren Linux:** that reasoning comes from how the network is built. The test suite
doesn't try Whonix through Mullvad, and it needs a real account. You can check it yourself. Install
`tcpdump`, start Whonix, and watch your real network card (`ip route` names it after `dev`, and
`mullvad status` names the server's address):

```
sudo tcpdump -ni YOUR-CARD 'ip and not host MULLVAD-SERVER-ADDRESS'
```

A few lines to your own router are normal. Connections to your bridge's address or to anywhere else
on the internet mean something is leaving outside the tunnel, so stop and find out why before you
rely on this.

## Sources

- Merrill and Calyx: [PBS Frontline](https://www.pbs.org/wgbh/frontline/article/gag-order-gone-secrets-of-a-national-security-letter-are-revealed),
  [Engadget](https://www.engadget.com/2015-09-15-judge-orders-fbi-gag-order-lifted.html).
- AT&T: [EFF's page on Hepting v. AT&T](https://www.eff.org/cases/hepting). The EFF brought that case,
  so it is one side's account of it.
- Verizon: [the order itself](https://assets.aclu.org/live/uploads/document/foia/Section_215_-_Secondary_Order_-_Verizon.pdf),
  published by the ACLU, and [its summary](https://www.aclu.org/documents/verizon-fisa-court-ruling).
  What followed: [JD Supra](https://jdsupra.com/legalnews/the-future-of-the-nsa-s-bulk-telephone-36638/).
- US law: [18 USC 2703](https://www.law.cornell.edu/uscode/text/18/2703),
  [2709](https://www.law.cornell.edu/uscode/text/18/2709) and
  [3123](https://www.law.cornell.edu/uscode/text/18/3123). Check them and the rest of the law yourself:
  it changes, and this page is only a summary.
- Mullvad: [no-logging policy](https://mullvad.net/en/help/no-logging-data-policy),
  [the 2023 search](https://mullvad.net/en/blog/2023/4/20/mullvad-vpn-was-subject-to-a-search-warrant-customer-data-not-compromised/),
  [Monero](https://mullvad.net/en/blog/we-now-accept-monero). These are the company's own pages.
- Tor Project: [Using Tor Browser with a VPN](https://support.torproject.org/faq/faq-5/).
- Whonix: [Connecting to a VPN before Tor](https://www.whonix.org/wiki/Tunnels/Connecting_to_a_VPN_before_Tor).
