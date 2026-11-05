# shellcheck shell=bash
# pins.sh: every signing key Wren Linux trusts, and the outside things its
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
# checked: 2026-11-05  Tor Browser 16.0 (signed by TB_FPR): its SecurityLevel.sys.mjs's
#   Safest column and slider pref names are the same as 15's
TB_SAFEST_VERSION=16

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

# Kali Linux (extras/distro-vm.sh). Kali's archive key, which also signs the
# SHA256SUMS of every image in cdimage.kali.org/current (rsa4096, 2025).
# checked: 2026-11-04  kali.org/docs/introduction/download-official-kali-linux-images;
#   archive.kali.org/archive-key.asc; keyserver.ubuntu.com; a good signature on 2026.3's SHA256SUMS
KALI_FPR=827C8569F2518CC677FECA1AED65462EC8D5E4C5
KALI_KEY_URL=https://archive.kali.org/archive-key.asc

# Arch Linux's install image (extras/distro-vm.sh). Pierre Schmitz, who signs
# every monthly ISO; archlinux.org's release list names him as its signer.
# checked: 2026-11-04  archlinux.org/download; archlinux.org/releng/releases/json; WKD pierre@archlinux.org
ARCH_ISO_FPR=3E80CA1A8B89F69CBA57D98A76A5EF9054449A5C
ARCH_ISO_KEY_URL=https://keys.openpgp.org/vks/v1/by-fingerprint/3E80CA1A8B89F69CBA57D98A76A5EF9054449A5C

# yt-dlp (extras/yt-dlp.sh). Simon Sawicki (yt-dlp signing key), which signs the
# SHA2-256SUMS of every release (rsa4096, 2023-02-26). Fetched from
# keys.openpgp.org, not from the GitHub repository whose releases it signs.
# checked: 2026-10-30  github.com/yt-dlp/yt-dlp public.key and README; keys.openpgp.org;
#   a good signature on 2026.10.26's SHA2-256SUMS
YTDLP_FPR=AC0CBBE6848D6A873464AF4E57CF65933B5A7581
YTDLP_KEY_URL=https://keys.openpgp.org/vks/v1/by-fingerprint/AC0CBBE6848D6A873464AF4E57CF65933B5A7581

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

# Signal Desktop's apt repo (extras/signal.sh). Open Whisper Systems'
# repository key (2017, no expiry date).
# checked: 2026-11-02  updates.signal.org's keys.asc; keyserver.ubuntu.com; keys.openpgp.org
SIGNAL_FPR=DBA36B5181D0C816F630E889D980A17457F6FB06
SIGNAL_KEY_URL=https://updates.signal.org/desktop/apt/keys.asc

# opencode (extras/opencode-vm.sh), installed inside the VM from this GitHub
# repository's newest release (sst/opencode moved here). Its releases carry no
# signatures: the guest takes only an immutable release, checked against the
# SHA-256s GitHub's API gives (data/opencode-vm-provision.sh).
# checked: 2026-11-02  opencode.ai/docs; api.github.com/repos/sst/opencode redirects here; v1.19.5 immutable
OPENCODE_REPO=anomalyco/opencode

# The Tor Project's apt repo, for lyrebird only (webtunnel bridges for the
# system tor: lib/tor.sh). "deb.torproject.org archive signing key"; it signs
# with a subkey that expires 2027-11-01, renewed in the file at the URL.
# checked: 2026-11-02  deb.torproject.org's key file; keys.openpgp.org; keyserver.ubuntu.com; it signs trixie's InRelease
TORPROJECT_FPR=A3C4F0F979CAA22CDBA8F512EE8CBC9E886DDD89
TORPROJECT_KEY_URL=https://deb.torproject.org/torproject.org/A3C4F0F979CAA22CDBA8F512EE8CBC9E886DDD89.asc

# Mullvad apt repo (extras/mullvad-vpn.sh, extras/mullvad-browser-regular.sh).
# Mullvad (code signing) <admin@mullvad.net>.
# checked: 2026-10-26  mullvad.net/en/help/verifying-signatures; the repo's keyring
MULLVAD_FPR=A1198702FC3E0A09A9AE5B75D5A1D4F266DE8DDF
MULLVAD_KEY_URL=https://repository.mullvad.net/deb/mullvad-keyring.asc

# Snowflake bridge lines (data/snowflake-bridges.txt): Tor Browser's own, from
# Browser/chrome/toolkit/content/global/pt_config.json inside its omni.ja,
# with fronts= changed to front= for Debian's snowflake-client.
# checked: 2026-10-27  Tor Browser 15.0.26
SNOWFLAKE_BRIDGES_SOURCE="Tor Browser 15.0.26 pt_config.json"

# DNS-over-TLS resolvers that parts/secure-dns.sh offers (lib/secure-dns.sh
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

# Wren Linux's own key (update.sh): the OpenPGP key that signs Wren Linux's commits.
# Its public half is data/wren-signing-key.asc. Once this is set, update.sh
# brings in a change only when the newest commit carries a good signature from
# exactly this key, checked with the key file and this line of the copy you
# already have, never with what comes in. Empty: changes come in unchecked, as
# GitHub serves them, and update.sh says so. docs/maintaining.md says how to
# make the key and turn this on.
WREN_SIGNING_FPR=DE09E9B9E9565B2BDA9D5FF5F0F19D6CEF465DC5

# Wren Linux's own apt repository (parts/wren-repo.sh): where it is served
# from, https:// or an .onion address. Its packages are signed with the key
# above (tools/make-apt-repo.sh), so the server needn't be trusted. Empty:
# not set up yet, and the part changes nothing.
WREN_REPO_URL=

# Where Wren Linux is published (git-init.sh connects a copy from a stick to it).
# checked: 2026-11-03  the repository was renamed from cjboon/debsway
WREN_GIT_URL=https://github.com/cjboon/wren-linux.git

# The Debian release everything was written and tested on.
# checked: 2026-10-27
DEBIAN_RELEASE=trixie
