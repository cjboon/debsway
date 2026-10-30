# shellcheck shell=bash
# pins.sh: every signing key debsway trusts, and the outside things its
# scripts were written against. Sourced by lib.sh, so every script and
# test.sh use these.
#
# Each entry says when it was last checked by hand. A fingerprint counts
# as checked once it matched on the project's own website and on a second,
# independent source. "bash test.sh" re-checks what it can automatically
# and warns about entries not checked by hand for over a year
# (lines starting "# checked: ").

# Claude Code apt repo (extras/claude-code.sh). Anthropic's key.
# checked: 2026-10-27  code.claude.com/docs/en/setup; downloads.claude.ai key
ANTHROPIC_FPR=31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE
ANTHROPIC_KEY_URL=https://downloads.claude.ai/keys/claude-code.asc

# Tor Browser (extras/tor-browser.sh, prep/fetch-tor-browser.sh). Tor Browser
# Developers; the same fingerprint torbrowser-launcher pins.
# checked: 2026-10-26  torbrowser-launcher source; keys.openpgp.org; torproject.org WKD
TB_FPR=EF6E286DDA85EA2A4BA7DE684E2C6E8793298290
TB_KEY_URL=https://keys.openpgp.org/vks/v1/by-fingerprint/EF6E286DDA85EA2A4BA7DE684E2C6E8793298290
# data/tor-browser-safest.js copies the Safest prefs of this Tor
# Browser version (SecurityLevel.sys.mjs). Re-check them when the first
# number changes.
# checked: 2026-10-26  Tor Browser 15.0.26 (Whonix's 15.0.25 identical)
TB_SAFEST_VERSION=15

# Whonix (extras/whonix.sh). Patrick Schleizer, signs all Whonix releases.
# checked: 2026-10-26  whonix.org signing key page; keys.openpgp.org
WHONIX_FPR=916B8D99C38EAF5E8ADC7A2A8D66066A2EEACCDA
WHONIX_KEY_URL=https://keys.openpgp.org/vks/v1/by-fingerprint/916B8D99C38EAF5E8ADC7A2A8D66066A2EEACCDA
# whonix.sh edits the disk images (root partition named "primary",
# /usr/local/etc/torrc.d, /usr/local/etc/torbrowser.d); written against
# this release. Re-check them when the first number changes.
# checked: 2026-10-26  Whonix 18.2.4.2 LXQt
WHONIX_TESTED_VERSION=18

# Debian's installer images (prep/make-install-iso.sh): the Debian CD signing
# key, which signs the SHA512SUMS of every release image (Debian 13's included).
# checked: 2026-10-30  debian.org/CD/verify; keyring.debian.org; a good signature on 13.7.0's SHA512SUMS
DEBIAN_CD_FPR=DF9B9C49EAA9298432589D76DA87E80D6294BE9B
DEBIAN_CD_KEY_URL='https://keyring.debian.org/pks/lookup?op=get&search=0xDF9B9C49EAA9298432589D76DA87E80D6294BE9B'

# Tails (extras/tails-usb.sh). The Tails signing key, which signs every Tails
# image (expires 2028-10-22; Tails says it extends it as needed).
# checked: 2026-10-29  tails.net/doc/about/openpgp_keys; tails.net/install/expert; keys.openpgp.org
TAILS_FPR=A490D0F4D311A4153E2BB7CADBB802B258ACD84F
TAILS_KEY_URL=https://tails.net/tails-signing.key

# Feather Wallet (extras/feather-wallet.sh). FeatherWallet <dev@featherwallet.org>.
# checked: 2026-10-26  featherwallet.org/download; docs.featherwallet.org
FEATHER_FPR=8185E158A33330C7FD61BC0D1F76E155CEFBA71C
FEATHER_KEY_URL=https://raw.githubusercontent.com/feather-wallet/feather/master/utils/pubkeys/featherwallet.asc

# SimpleX Chat (extras/simplex-chat.sh). build@simplex.chat.
# checked: 2026-10-26  simplex.chat/reproduce; keys.openpgp.org
SIMPLEX_FPR=BBDF7BDAD1548B16836AF5B9D53BDFD153C366BA
SIMPLEX_KEY_URL=https://keys.openpgp.org/vks/v1/by-fingerprint/BBDF7BDAD1548B16836AF5B9D53BDFD153C366BA

# Sparrow Wallet (extras/sparrow-wallet.sh). Craig Raw. keybase's copy,
# because keys.openpgp.org serves this key without its user IDs and gpg
# won't import it then.
# checked: 2026-10-26  sparrowwallet.com/download; keys.openpgp.org; keybase
SPARROW_FPR=D4D0D3202FC06849A257B38DE94618334C674B40
SPARROW_KEY_URL=https://keybase.io/craigraw/pgp_keys.asc

# Mullvad apt repo (extras/mullvad-vpn.sh, extras/mullvad-browser.sh).
# Mullvad (code signing) <admin@mullvad.net>.
# checked: 2026-10-26  mullvad.net/en/help/verifying-signatures; the repo's keyring
MULLVAD_FPR=A1198702FC3E0A09A9AE5B75D5A1D4F266DE8DDF
MULLVAD_KEY_URL=https://repository.mullvad.net/deb/mullvad-keyring.asc

# Snowflake bridge lines (data/snowflake-bridges.txt): Tor Browser's own, from
# Browser/chrome/toolkit/content/global/pt_config.json inside its omni.ja,
# with fronts= changed to front= for Debian's snowflake-client.
# checked: 2026-10-27  Tor Browser 15.0.26
SNOWFLAKE_BRIDGES_SOURCE="Tor Browser 15.0.26 pt_config.json"

# DNS-over-TLS resolvers that extras/secure-dns.sh offers (lib/secure-dns.sh
# says what each one is): the name its certificate must carry, then its
# addresses. Checked against the provider's own page, and with openssl on port
# 853 that the certificate matches the name (IPv4 addresses; IPv6 wasn't
# reachable from where it was checked). Mullvad's public DNS isn't here: it
# shuts down on 2026-11-02 (mullvad.net/en/blog/2026/9/3/...).
# checked: 2026-10-29  quad9.net/service/service-addresses-and-features; openssl
DOT_QUAD9="dns.quad9.net 9.9.9.9 149.112.112.112 2620:fe::fe 2620:fe::9"
# checked: 2026-10-29  digitale-gesellschaft.ch/dns; openssl
DOT_DIGIGES="dns.digitale-gesellschaft.ch 185.95.218.42 185.95.218.43 2a05:fc84::42 2a05:fc84::43"
# checked: 2026-10-29  applied-privacy.net/services/dns; openssl
DOT_APPLIEDPRIVACY="dot1.applied-privacy.net 146.255.56.98 2a02:1b8:10:234::2"

# The Debian release everything was written and tested on.
# checked: 2026-10-27
DEBIAN_RELEASE=trixie
