#!/bin/bash
# Electrum (Bitcoin wallet) from Debian's own packages, which Debian
# keeps patched. It uses Qt5, which runs on Wayland via qtwayland5 (base).
# Usage: bash electrum.sh [--remove | --manual]
# summary: Electrum Bitcoin wallet
# security: some
# status: apt:electrum
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
. "$WREN_DIR/lib/wallet-tor.sh"
if [ "${1:-}" = --manual ]; then print_manual; exit; fi
need_user

if [ "${1:-}" = --remove ]; then
    apt_purge electrum python3-electrum
    note "Your wallets are kept in ~/.electrum. Back them up before deleting anything."
    exit
fi

say "Installing electrum"
apt_install electrum qtwayland5
note "Run it with: electrum   (or Super+d). Wallets live in ~/.electrum."
# Electrum has no Tor of its own: its proxy setting ("proxy" in ~/.electrum/config;
# config_version 3, Electrum 4.5's, so it doesn't rework the file) is this computer's
ELECTRUM_TOR_HOW="Electrum's Tools > Network > Proxy: SOCKS5, ${WALLET_TOR_SOCKS%:*}, port ${WALLET_TOR_SOCKS#*:}."
if system_tor_runs; then
    wallet_offer_tor Electrum electrum "$HOME/.electrum/config" \
        "{\"config_version\": 3, \"proxy\": \"socks5:$WALLET_TOR_SOCKS\"}" \
        "Tor runs on this computer: Electrum can reach its servers through it, so none sees your address." \
        "$ELECTRUM_TOR_HOW"
else
    note "Tor for Electrum: Tor doesn't run on this computer. Set up apt over Tor (wrenctl part apt-tor),"
    note "then: $ELECTRUM_TOR_HOW"
fi
