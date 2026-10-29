#!/bin/bash
# Checks new-profile.sh's helpers (lib/firefox-profiles.sh, lib/firefox-sandbox.sh):
# a Firefox profile gets a locked-down user of its own, a settings file, a sudo
# rule for the session script and a launcher; removing it takes them away. sudo
# and visudo are pretended and only write down what they were asked to do.
# Changes nothing outside a temp folder. Run by test.sh, or:
#   bash tools/test-profile-users.sh
# shellcheck disable=SC2016  # the inner bash expands its own variables
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
fails=0
check() { # DESCRIPTION CONDITION-COMMAND...
    local what=$1
    shift
    if "$@" >/dev/null 2>&1; then printf '  ok    %s\n' "$what"; else printf '  FAIL  %s\n' "$what"; fails=$((fails + 1)); fi
}
not() { ! "$@"; }

mkdir -p "$T/fake" "$T/home" "$T/files" "$T/sandbox"
printf '#!/bin/sh\n' >"$T/sandbox/firefox"; printf '#!/bin/sh\n' >"$T/sandbox/firefox-session"
chmod +x "$T/sandbox/"*
# sudo: write down the command; "tee FILE" keeps what it was given; "install SRC DEST" keeps the source
# shellcheck disable=SC2016  # written into the pretend programs, expanded when they run
cat >"$T/fake/sudo" <<FAKE
#!/bin/bash
echo "sudo \$*" >>"$T/calls"
case \$1 in
    tee) cat >"$T/files/\$(basename "\$2")" ;;
    install) src=\${@: -2:1}; dest=\${@: -1}; [ -f "\$src" ] && cp "\$src" "$T/files/\$(basename "\$dest")" ;;
    visudo) exit 0 ;;
esac
exit 0
FAKE
# id: a user fx-* does not exist until "useradd" has been asked for it (the file $T/made)
cat >"$T/fake/id" <<FAKE
#!/bin/bash
if [[ "\${1:-}" == fx-* || "\${2:-}" == fx-* ]]; then
    grep -qx "\${2:-\$1}" "$T/made" 2>/dev/null && { [ "\$1" = -u ] && echo 900 || true; exit 0; }
    exit 1
fi
exec /usr/bin/id "\$@"
FAKE
printf '#!/bin/sh\nexit 1\n' >"$T/fake/getent"   # no group debsway-fx, no render group yet
chmod +x "$T/fake/"*
export HOME="$T/home" DEBSWAY_FX_CLIENT="$T/sandbox/firefox" DEBSWAY_FX_SESSION="$T/sandbox/firefox-session"
export DEBSWAY_TEST_ANSWERS="$T/answers"

run() { # script body, run with the helpers loaded and the pretend commands first
    env PATH="$T/fake:$PATH" bash -c '. "$1/lib.sh"; PATH="$2:$PATH"; . "$1/lib/firefox-sandbox.sh"; . "$1/lib/firefox-profiles.sh"; '"$3" _ "$HERE" "$T/fake"
}

: >"$T/calls"; : >"$T/answers"
: >"$T/made"
run x x 'fx_create_user fx-bank /var/lib/debsway-fx/bank "debsway Firefox profile bank"' >/dev/null 2>&1
check "a new profile's user is made through useradd" grep -q 'sudo useradd --system --gid debsway-fx --create-home --home-dir /var/lib/debsway-fx/bank --shell /usr/sbin/nologin' "$T/calls"
check "...in the shared group, which is made first if it is missing" grep -q 'sudo groupadd --system debsway-fx' "$T/calls"
check "...locked, with no login shell" grep -q 'sudo usermod --lock --shell /usr/sbin/nologin fx-bank' "$T/calls"
check "...and a home only that user can enter" grep -q 'sudo chmod 0700 /var/lib/debsway-fx/bank' "$T/calls"

: >"$T/calls"
run x x 'fx_allow_session fx-bank' >/dev/null 2>&1
check "the sudo rule is checked with visudo" grep -q 'sudo visudo -cf' "$T/calls"
check "...and installed read-only for root, named for the user" grep -q 'sudo install -o root -g root -m 0440 .* /etc/sudoers.d/debsway-fx-bank' "$T/calls"
rule=$(grep -h 'NOPASSWD' "$T/files/debsway-fx-bank")
check "it lets your user run the session script as fx-bank" grep -qF "ALL=(fx-bank) NOPASSWD: $T/sandbox/firefox-session" <<<"$rule"
check "...and nothing else (one rule line)" test "$(grep -c NOPASSWD "$T/files/debsway-fx-bank")" -eq 1

# a whole profile
: >"$T/calls"; rm -rf "$T/files"/*; rm -f "$T/home/.local/bin/firefox-bank"
echo fx-bank >"$T/made"
out=$(run x x 'make_profile bank https://bank.example/ no' 2>&1)
check "make_profile writes the profile's settings where only root can" test -f "$T/files/bank.conf" && grep -q 'sudo tee /etc/debsway/firefox-profiles/bank.conf' "$T/calls"
check "...the address" grep -qx 'url=https://bank.example/' "$T/files/bank.conf"
check "...and the JavaScript choice" grep -qx 'fast_js=no' "$T/files/bank.conf"
check "it allows the session for that user only" test -f "$T/files/debsway-fx-bank"
check "the firefox-bank command runs the sandbox with the profile name" grep -q "firefox --profile bank" "$T/home/.local/bin/firefox-bank"
check "...and is executable" test -x "$T/home/.local/bin/firefox-bank"
check "...and is one remove_profile will recognise as ours" grep -q 'Written by debsway extras/firefox-profiles/new-profile.sh' "$T/home/.local/bin/firefox-bank"
check "it tells where the downloads go" grep -q 'Downloads/bank' <<<"$out"
: >"$T/calls"
run x x 'make_profile shop https://shop.example/ yes' >/dev/null 2>&1
check "fast JavaScript is written to the settings file" grep -qx 'fast_js=yes' "$T/files/shop.conf"

# names that cannot be a user are refused before anything happens
: >"$T/calls"
for bad in Bank 1bank 'bank_x' abcdefghijklmnopqrstuvwxyzabcdefghij '' esr restart-check session; do
    check "the profile name \"$bad\" is refused" not run x x "make_profile '$bad' https://x.example/ no"
done
check "...and nothing was run for them" test ! -s "$T/calls"
# a firefox-NAME command that someone else wrote is refused before a user is made
mkdir -p "$T/home/.local/bin"
printf '#!/bin/sh\necho mine\n' >"$T/home/.local/bin/firefox-work"
: >"$T/calls"
check "a name whose firefox-NAME command isn't debsway's is refused" not run x x 'make_profile work https://work.example/ no'
check "...before any user, rule or settings file is made" test ! -s "$T/calls"
check "...and that command is left as it was" grep -qx 'echo mine' "$T/home/.local/bin/firefox-work"

# the sandboxed Firefox can't be removed while profiles still run through it
# (the guard is tested on its own: the extra itself would run the real sudo)
mkdir -p "$T/profiles"
echo 'url=https://bank.example/' >"$T/profiles/bank.conf"
out=$(DEBSWAY_FX_PROFILE_DIR="$T/profiles" run x x 'fx_sandbox_unused' 2>&1)
rc=$?
check "removing the sandbox with a profile left is refused" test "$rc" -ne 0
check "...naming the profile and how to remove it" bash -c 'grep -q "bank" <<<"$1" && grep -q "new-profile.sh --remove" <<<"$1"' _ "$out"
rm -f "$T/profiles/bank.conf"
DEBSWAY_FX_PROFILE_DIR="$T/profiles" run x x 'fx_sandbox_unused' >/dev/null 2>&1
check "with no profile left it goes ahead" test $? -eq 0
check "the extra asks it first thing when removing, before any change" \
    bash -c 'sed -n "/--remove ]; then/,/^fi/p" "$1" | sed -n 2p | grep -qx "    fx_sandbox_unused"' _ "$HERE/extras/firefox-sandbox.sh"

# removing: the launcher, the rule and the settings go; the data stays unless you say so
: >"$T/calls"; : >"$T/answers"; echo n >"$T/answers"
echo fx-bank >"$T/made"
run x x 'remove_profile bank' >/dev/null 2>&1
check "removing takes away the command" test ! -e "$T/home/.local/bin/firefox-bank"
check "...the permission to run the session" grep -q 'sudo rm -f /etc/sudoers.d/debsway-fx-bank' "$T/calls"
check "...and the settings file" grep -q 'sudo rm -f /etc/debsway/firefox-profiles/bank.conf' "$T/calls"
check "saying no keeps the user and the logins" not grep -q 'userdel' "$T/calls"
: >"$T/calls"
run x x 'make_profile bank https://bank.example/ no' >/dev/null 2>&1
: >"$T/calls"; echo y >"$T/answers"
run x x 'remove_profile bank' >/dev/null 2>&1
check "saying yes deletes the user" grep -q 'sudo userdel fx-bank' "$T/calls"
check "...and its home folder" grep -q 'sudo rm -rf /var/lib/debsway-fx/bank' "$T/calls"

# an older profile (in your own Firefox) is removed the old way: no sudo at all
mkdir -p "$T/home/.local/bin"
printf '#!/bin/sh\n# Written by debsway extras/firefox-profiles/new-profile.sh\nexec firefox-esr --name firefox-old -P old "$@"\n' >"$T/home/.local/bin/firefox-old"
: >"$T/calls"
run x x 'remove_profile old' >/dev/null 2>&1
check "an older profile's command is removed" test ! -e "$T/home/.local/bin/firefox-old"
check "...without touching sudo or users" test ! -s "$T/calls"

# the script itself
n=$HERE/extras/firefox-profiles/new-profile.sh
check "new-profile.sh uses the sandbox helpers" grep -q 'lib/firefox-sandbox.sh' "$n"
check "its header says each profile gets a user of its own" grep -q 'locked-down Linux user of its own' "$n"

[ "$fails" -eq 0 ]
