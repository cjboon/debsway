#!/bin/bash
# Checks tools/release.sh on a copy of Wren Linux with a pretend server, git-push.sh,
# build-deb.sh, sudo and wrenctl: the steps in order, a stop at the first that
# fails, and the one file from a private folder going to apt, whatever else lies
# in /tmp. Nothing is pushed or installed, and nothing outside a temp folder
# changes. Run by test.sh, or:  bash tools/test-release.sh
# shellcheck disable=SC2016  # the inner shells and pretend programs expand their own variables
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

export HOME=$T/home GIT_CONFIG_NOSYSTEM=1
mkdir -p "$HOME"
git config --global user.name t
git config --global user.email t@example.org
git config --global init.defaultBranch main
git config --global commit.gpgsign false

# A copy, committed, with a server to compare with
R=$T/wren
mkdir -p "$R/tools"
cp -r "$HERE/lib" "$HERE/lib.sh" "$HERE/pins.sh" "$R/"
cp "$HERE/tools/release.sh" "$R/tools/"
echo first >"$R/notes"
git init -q --bare "$T/server.git"
git -C "$R" init -q
git -C "$R" add -A
git -C "$R" commit -qm first
git -C "$R" remote add origin "$T/server.git"
git -C "$R" push -q origin main

# Each pretend step writes down that it ran, and fails when asked to
cat >"$R/tools/git-push.sh" <<EOF
#!/bin/bash
echo push >>"$T/ran"
[ -z "\${FAIL_PUSH:-}" ] || exit 1
[ -n "\${DECLINE_PUSH:-}" ] || git -C "$R" push -q origin main
EOF
cat >"$R/tools/build-deb.sh" <<EOF
#!/bin/bash
echo "build \$*" >>"$T/ran"
[ -z "\${FAIL_BUILD:-}" ] || { echo "no room"; exit 1; }
out=\$4
d=\${BAD_NAME:-\$out/wren-linux_1_all.deb}
echo package >"\$out/wren-linux_1_all.deb"
chmod 600 "\$out/wren-linux_1_all.deb"
[ -z "\${LINK_DEB:-}" ] || ln -sf /etc/passwd "\$out/wren-linux_1_all.deb"
echo "\$d"
echo "SHA-256: abc123"
EOF
cat >"$T/sudo" <<EOF
#!/bin/bash
echo "sudo \$*" >>"$T/ran"
f=\${!#}
stat -c '%a' "\$f" >"$T/deb-mode"
stat -c '%a' "\${f%/*}" >"$T/deb-dir-mode"
ls -A "\${f%/*}" | grep -c '\.deb$' >"$T/deb-count"
[ -z "\${FAIL_APT:-}" ]
EOF
printf '#!/bin/bash\necho "wrenctl $*" >>"%s/ran"\n' "$T" >"$T/wrenctl"
chmod +x "$T/sudo" "$T/wrenctl"
release() { : >"$T/ran"; env WREN_SUDO="$T/sudo" WREN_WRENCTL="$T/wrenctl" bash "$R/tools/release.sh" "$@" 2>&1; }
steps() { cut -d' ' -f1 "$T/ran" | paste -sd' '; }

# ---- all the way
out=$(release)
check "the steps, in order: publish, build, install, update" test "$(steps)" = "push build sudo wrenctl"
check "...the package is built from the commit" grep -q 'build --commit HEAD --out ' "$T/ran"
check "...its SHA-256 is shown before it is installed" grep -q 'SHA-256: abc123' <<<"$out"
sudo_line=$(grep '^sudo ' "$T/ran")
check "...apt gets one file, by its whole path, in a private folder" bash -c '
    [[ $1 =~ ^sudo\ apt\ install\ /[^\ *]+/wren-linux_1_all\.deb$ ]]' _ "$sudo_line"
check "...never by a name that could match another file" not grep -q '\*' <<<"$sudo_line"
check "...a folder only you can write in, that apt's own user can read" test "$(cat "$T/deb-dir-mode")" = 755
check "...the file readable by apt's own user" test "$(cat "$T/deb-mode")" = 644
check "...and it is the only package there" test "$(cat "$T/deb-count")" = 1
check "...the folder goes afterwards" bash -c 'f=${1##* }; [ ! -e "${f%/*}" ]' _ "$sudo_line"
check "...wrenctl --update last" test "$(tail -1 "$T/ran")" = "wrenctl --update"

# ---- it stops at the first step that fails
out=$(FAIL_PUSH=1 release)
check "a push that fails: nothing built or installed" test "$(steps)" = push
check "...and it says so" grep -q 'nothing was installed' <<<"$out"
echo x >>"$R/notes"; git -C "$R" add -A; git -C "$R" commit -qm second
out=$(DECLINE_PUSH=1 release)
check "no to the push: nothing installed, though git-push.sh is content" test "$(steps)" = push
check "...and it says how to try it here without publishing" grep -q 'release.sh --local' <<<"$out"
git -C "$R" push -q origin main
out=$(FAIL_BUILD=1 release)
check "a build that fails: nothing installed" test "$(steps)" = "push build"
check "...and you see why" grep -q 'no room' <<<"$out"
out=$(FAIL_APT=1 release)
check "apt refusing: no update" test "$(steps)" = "push build sudo"
out=$(BAD_NAME=/tmp/wren-linux_9_all.deb release)
check "the build naming a file outside the private folder: not installed" test "$(steps)" = "push build"
out=$(LINK_DEB=1 release)
check "a link where the package should be: not installed" test "$(steps)" = "push build"

# ---- --local
out=$(release --local)
check "--local: nothing pushed, the rest all the same" test "$(steps)" = "build sudo wrenctl"
echo y >>"$R/notes"
out=$(release --local)
check "...what isn't committed: it says so" grep -q "aren't committed" <<<"$out"
git -C "$R" checkout -q -- notes
check "anything else on its command line is refused" bash -c '
    out=$(WREN_SUDO=x bash "$1/tools/release.sh" --force 2>&1); [ $? != 0 ] && grep -q Usage <<<"$out"' _ "$R"
check "not as root" grep -qx 'not_root' "$HERE/tools/release.sh"

# ---- the recipe git-push.sh prints
check "git-push.sh no longer tells you to install from a name in /tmp" not grep -q '/tmp/wren-linux' "$HERE/tools/git-push.sh"
check "...it names release.sh" grep -q 'tools/release.sh' "$HERE/tools/git-push.sh"

[ "$fails" -eq 0 ]
