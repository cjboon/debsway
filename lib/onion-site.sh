# shellcheck shell=bash
# lib/onion-site.sh: the fixed parts of extras/onion-site.sh, and the lines it
# puts in Tor's config. Sourced after lib.sh, by the extra and its test. The
# ports must match bin/onion-site-session and data/onion-site-firewall.nft.

ONION_SITE_USER=onion-site
ONION_SITE_SSH_PORT=2243
ONION_SITE_WEB_PORT=18080
ONION_SITE_SVC_DIR=/var/lib/tor/debsway-onion-site
ONION_SITE_MARK=/etc/tor/.debsway-onion-site
ONION_SITE_BEGIN='# >>> debsway onion-site >>>'
ONION_SITE_END='# <<< debsway onion-site <<<'

# onion_site_torrc POW(yes|no): the block for /etc/tor/torrc. Port 80 of the
# onion address leads to the VM's nginx, through the host-loopback port QEMU
# forwards. POW=yes turns on Tor's proof-of-work defence against floods of
# visits (only where this tor was built with it; the extra checks first).
# A private site has client keys in $ONION_SITE_SVC_DIR/authorized_clients:
# Tor then needs no setting of its own for that.
onion_site_torrc() {
    echo "$ONION_SITE_BEGIN"
    echo "HiddenServiceDir $ONION_SITE_SVC_DIR/"
    echo "HiddenServiceVersion 3"
    echo "HiddenServicePort 80 127.0.0.1:$ONION_SITE_WEB_PORT"
    # Tor's own limits on how fast introductions may arrive (against floods)
    echo "HiddenServiceEnableIntroDoSDefense 1"
    if [ "${1:-no}" = yes ]; then echo "HiddenServicePoWDefensesEnabled 1"; fi
    echo "$ONION_SITE_END"
}
