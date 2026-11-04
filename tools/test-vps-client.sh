#!/bin/bash
# Checks tools/vps-client.sh in a temp home: the onion client key is a real
# X25519 pair (its public half is what openssl derives from the private one),
# kept for you alone, in the form setup-vps.sh takes; Tor's client file and the
# ssh entry say what they should; nothing runs sudo. Changes nothing outside a
# temp folder. Run by test.sh, or:  bash tools/test-vps-client.sh
# shellcheck disable=SC2016  # the inner shells expand their own variables
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
V=$HERE/tools/vps-client.sh
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
fails=0
check() { # DESCRIPTION CONDITION-COMMAND...
    local what=$1
    shift
    if "$@" >/dev/null 2>&1; then printf '  ok    %s\n' "$what"; else printf '  FAIL  %s\n' "$what"; fails=$((fails + 1)); fi
}
not() { ! "$@"; }
command -v openssl >/dev/null || { echo "  ok    skipped: openssl isn't installed"; exit 0; }
export HOME=$T/home XDG_CONFIG_HOME=
mkdir -p "$HOME" "$T/bin"
printf '#!/bin/sh\necho "sudo $*" >>"%s/sudo-calls"\n' "$T" >"$T/bin/sudo"
chmod +x "$T/bin/sudo"
vc() { PATH="$T/bin:$PATH" bash "$V" "$@"; }
K=$HOME/.config/wren/vps

pub=$(vc keygen | tail -n1)
check "keygen: a public half setup-vps.sh takes (52 of A-Z and 2-7)" bash -c '[[ $1 =~ ^[A-Z2-7]{52}$ ]]' _ "$pub"
check "...the private half kept for you alone" bash -c '[ "$(stat -c %a "$1")" = 700 ] && [ "$(stat -c %a "$1/wren-vps.key")" = 600 ] && [[ $(cat "$1/wren-vps.key") =~ ^[A-Z2-7]{52}$ ]]' _ "$K"
derived=$(python3 -I -c 'import base64,sys; k=sys.argv[1]; sys.stdout.buffer.write(bytes.fromhex("302e020100300506032b656e04220420")+base64.b32decode(k+"===="))' "$(cat "$K/wren-vps.key")" |
    openssl pkey -inform DER -pubout -outform DER 2>/dev/null | python3 -I -c 'import base64,sys; print(base64.b32encode(sys.stdin.buffer.read()[-32:]).decode().rstrip("="))')
check "...and the two belong together (openssl derives that public half from the private one)" test "$derived" = "$pub"
check "...a second keygen with the same name is refused (the key isn't replaced)" not vc keygen
check "keygen-show prints the public half again" test "$(vc keygen-show)" = "$pub"
grep -q '\[\[ \$VPS_ONION_SSH_CLIENT =~ \^\[A-Z2-7\]{52}\$ \]\]' "$HERE/tools/setup-vps.sh"
check "...the same form setup-vps.sh checks for" test $? -eq 0
ON=$(printf 'k%.0s' {1..56})
out=$(vc tor-auth "$ON.onion")
check "tor-auth: Tor's client file, for that address, yours alone" bash -c '
    [ "$(cat "$1/wren-vps.auth_private")" = "$2:descriptor:x25519:$(cat "$1/wren-vps.key")" ] && [ "$(stat -c %a "$1/wren-vps.auth_private")" = 600 ]' _ "$K" "$ON"
check "...and the root commands that give it to this computer's Tor, printed, not run" bash -c '
    grep -q "ClientOnionAuthDir /var/lib/tor/onion_auth" <<<"$1" && grep -q "sudo install -m 0600 -o debian-tor" <<<"$1" && [ ! -e "$2/sudo-calls" ]' _ "$out" "$T"
check "...an address that isn't one is refused" not vc tor-auth example.com
out=$(vc ssh-config wren "$ON")
check "ssh-config: through this computer's Tor, with the server's key file and your user" bash -c '
    grep -q "^Host wren-vps$" <<<"$1" && grep -q "HostName $2.onion" <<<"$1" && grep -q "User wren" <<<"$1" &&
    grep -q "ProxyCommand nc -X 5 -x 127.0.0.1:9050 %h %p" <<<"$1" && grep -q "IdentitiesOnly yes" <<<"$1"' _ "$out" "$ON"
check "...a user name that isn't one is refused" not vc ssh-config 'x;y' "$ON"
check "a name for the key files that isn't one is refused" not vc keygen '../x'

[ "$fails" -eq 0 ]
