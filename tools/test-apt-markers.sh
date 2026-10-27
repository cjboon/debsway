#!/bin/bash
# Checks lib/apt.sh (the marker packages behind apt_install and apt_purge)
# without touching the system: apt-get, apt-mark and dpkg-query are replaced
# by small fakes that keep their state in a temporary folder. Real tools are
# used for what is only file work (dpkg-deb), plus apt-get -s to see that
# apt can resolve a marker. Run by test.sh; or: bash tools/test-apt-markers.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
set +e +o pipefail

ST=$(mktemp -d)
trap 'rm -rf "$ST"' EXIT
mkdir -p "$ST/pkg"
LOG=$ST/log
: >"$LOG"
fails=0
check() { # DESCRIPTION CONDITION-COMMAND...
    local what=$1
    shift
    if "$@" >/dev/null 2>&1; then printf '  ok    %s\n' "$what"; else printf '  FAIL  %s\n' "$what"; fails=$((fails + 1)); fi
}
logged() { grep -q -- "$1" "$LOG"; }
count() { grep -c -- "$1" "$LOG"; }
installed() { [ -f "$ST/pkg/$1" ]; }
mark() { cat "$ST/pkg/$1" 2>/dev/null; }

# ---- fakes: a package is a file holding "auto" or "manual", and
# $ST/pkg/NAME.deps holds what it depends on
SUDO=
have_internet() { return 0; }
fake_install() { # PKG MARK [DEPS]
    echo "$2" >"$ST/pkg/$1"
    echo "$3" >"$ST/pkg/$1.deps"
}
apt-get() {
    echo "apt-get $*" >>"$LOG"
    local cmd=$1 a d deps changed
    shift
    case $cmd in
        install)
            for a in "$@"; do
                case $a in
                    -*) ;;
                    *.deb)
                        deps=$(dpkg-deb -f "$a" Depends)
                        fake_install "$(dpkg-deb -f "$a" Package)" manual "$deps"
                        for d in $(tr -d ',' <<<"$deps"); do installed "$d" || fake_install "$d" auto ""; done ;;
                    *) installed "$a" || fake_install "$a" manual "" ;;
                esac
            done ;;
        purge)
            for a in "$@"; do
                case $a in -*) ;; *) rm -f "$ST/pkg/$a" "$ST/pkg/$a.deps" ;; esac
            done ;;
        autoremove)
            changed=true
            while $changed; do
                changed=false
                for a in "$ST"/pkg/*; do
                    case $a in *.deps) continue ;; esac
                    [ -f "$a" ] || continue
                    [ "$(cat "$a")" = auto ] || continue
                    if ! cat "$ST"/pkg/*.deps | tr -d ',' | tr ' ' '\n' | grep -qxF -- "$(basename -- "$a")"; then
                        rm -f "$a" "$a.deps"
                        changed=true
                    fi
                done
            done ;;
    esac
}
apt-mark() {
    echo "apt-mark $*" >>"$LOG"
    local a
    for a in "${@:2}"; do [ -f "$ST/pkg/$a" ] && echo "$1" >"$ST/pkg/$a"; done
    return 0
}
# shellcheck disable=SC2016  # the ${...} are dpkg-query field names
dpkg-query() {
    local fmt pkg a
    for a in "$@"; do
        case $a in -f=*) fmt=${a#-f=} ;; -W) ;; *) pkg=$a ;; esac
    done
    case $fmt in
        *'${Status}'*) installed "$pkg" && echo "install ok installed" ;;
        *'${Depends}'*) installed "$pkg" && sed 's/ *$//' "$ST/pkg/$pkg.deps" ;;
        *Status-Abbrev*)
            for a in "$ST"/pkg/debsway-*; do
                case $a in *.deps) continue ;; esac
                [ -f "$a" ] && echo "ii  $(basename -- "$a")"
            done ;;
    esac
    return 0
}
unset DEBSWAY_APT_UPDATED

echo "Marker package names"
check "named after the script" test "$(bash -c '. "$1/lib.sh"; apt_marker' "parts/Foo_Bar.sh" "$DEBSWAY_DIR")" = debsway-foo-bar
check "DEBSWAY_OWNER wins" test "$(DEBSWAY_OWNER=Whonix bash -c '. "$1/lib.sh"; apt_marker' x "$DEBSWAY_DIR")" = debsway-whonix

echo "Building a marker"
mkdir "$ST/b"
marker_build debsway-demo "$ST/b" mat2 mpv mat2
check "it is a valid package" dpkg-deb -I "$ST/b/debsway-demo.deb"
check "it depends on the sorted, unique packages" test "$(dpkg-deb -f "$ST/b/debsway-demo.deb" Depends)" = "mat2, mpv"
if [ -x /usr/bin/apt-get ]; then
    check "apt can resolve it" /usr/bin/apt-get -s -o Debug::NoLocking=1 install --no-install-recommends "$ST/b/debsway-demo.deb"
fi

echo "apt_install"
export DEBSWAY_OWNER=alpha
apt_install aaa bbb >/dev/null
check "the marker is installed" installed debsway-alpha
check "its packages came in as dependencies" bash -c "[ \"$(mark aaa)\" = auto ] && [ \"$(mark bbb)\" = auto ]"
check "the marker itself is manual" test "$(mark debsway-alpha)" = manual
n=$(count '^apt-get install')
apt_install aaa >/dev/null
check "asking for recorded packages again runs no apt" test "$(count '^apt-get install')" = "$n"
apt_install ccc >/dev/null
check "a second call merges with the first" test "$(tr -d ',\n' <"$ST/pkg/debsway-alpha.deps")" = "aaa bbb ccc"
check "apt-get update ran only once" test "$(count '^apt-get update')" = 1

echo "Shared packages"
export DEBSWAY_OWNER=beta
apt_install bbb ddd >/dev/null
export DEBSWAY_OWNER=alpha
apt_purge aaa bbb ccc >/dev/null
check "purging removes the marker" bash -c "! [ -f '$ST/pkg/debsway-alpha' ]"
check "packages only alpha needed are gone" bash -c "! [ -f '$ST/pkg/aaa' ] && ! [ -f '$ST/pkg/ccc' ]"
check "a package beta still needs stays" installed bbb
check "autoremove ran" logged '^apt-get autoremove --purge'
export DEBSWAY_OWNER=beta
apt_purge >/dev/null
check "beta's purge removes the rest" bash -c "! [ -f '$ST/pkg/bbb' ] && ! [ -f '$ST/pkg/ddd' ]"

echo "Packages from a .deb file"
mkdir "$ST/f"
printf 'Package: fakeapp\nVersion: 1\nArchitecture: all\nMaintainer: x\nDescription: x\n' >/dev/null
mkdir -p "$ST/f/root/DEBIAN"
printf 'Package: fakeapp\nVersion: 1\nArchitecture: all\nMaintainer: x <x@localhost>\nDescription: test\n' >"$ST/f/root/DEBIAN/control"
dpkg-deb --root-owner-group --build "$ST/f/root" "$ST/f/fakeapp.deb" >/dev/null
export DEBSWAY_OWNER=gamma
apt_install "$ST/f/fakeapp.deb" libfoo >/dev/null
check "the marker depends on the package in the file" bash -c "grep -q fakeapp '$ST/pkg/debsway-gamma.deps' && grep -q libfoo '$ST/pkg/debsway-gamma.deps'"
check "the file's package was made automatic" test "$(mark fakeapp)" = auto
apt_purge fakeapp >/dev/null
check "removing takes it away" bash -c "! [ -f '$ST/pkg/fakeapp' ]"

echo "Packages installed before markers existed"
fake_install oldpkg manual ""
fake_install sharedpkg manual ""
fake_install debsway-other manual "sharedpkg"
export DEBSWAY_OWNER=delta
apt_purge oldpkg sharedpkg >/dev/null
check "an old package is purged by name" bash -c "! [ -f '$ST/pkg/oldpkg' ]"
check "unless another script's marker needs it" installed sharedpkg
fake_install untouched manual ""
apt_purge >/dev/null
check "with nothing recorded and no names, nothing is removed" installed untouched

echo "Switching to a package that conflicts with the old one"
export DEBSWAY_OWNER=epsilon
apt_install oldname extra >/dev/null
apt_drop oldname
apt_install newname >/dev/null
check "the dropped package leaves the marker" test "$(tr -d ',\n' <"$ST/pkg/debsway-epsilon.deps")" = "extra newname"
APT_DROP=()
apt_drop extra
n=$(count '^apt-get install')
apt_install newname >/dev/null
check "dropping works even when nothing new is asked for" test "$(tr -d ',\n' <"$ST/pkg/debsway-epsilon.deps")" = newname
check "and the marker was rebuilt for it" test "$(count '^apt-get install')" -gt "$n"

[ "$fails" -eq 0 ]
