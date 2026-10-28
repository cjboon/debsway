#!/bin/bash
# temp-claude-vm.sh -- throwaway check, runs INSIDE the claude-vm guest.
# It confirms Claude Code and its tools are installed, that the guest can
# reach the internet, and that it CANNOT reach your local network. It
# changes nothing. temp-claude-host.sh pipes this in for you; you can also
# run it by hand: `claude-vm shell`, paste it, bash it. Delete it afterwards.
#
# Reaching a private address below should FAIL fast (the host rejects the
# guest's socket). If one SUCCEEDS, the network containment is not working.

pass=0; fail=0
ok()   { printf '  \033[32mPASS\033[0m  %s\n' "$1"; pass=$((pass+1)); }
no()   { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; fail=$((fail+1)); }
yn()   { if "$@" >/dev/null 2>&1; then return 0; else return 1; fi; }

# connects HOST PORT: true if a TCP connection opens within 5s
connects() { timeout 5 bash -c "exec 3<>/dev/tcp/$1/$2" 2>/dev/null; }

echo "== inside the guest: $(hostname) as $(id -un) =="

echo "-- Claude Code and tools --"
yn command -v claude     && ok "claude is installed ($(claude --version 2>/dev/null | head -1))" || no "claude is NOT installed"
for t in git rg jq shellcheck python3; do
    yn command -v "$t" && ok "$t present" || no "$t missing"
done

echo "-- the guest's own identity (never yours) --"
[ "$(git config --global user.email 2>/dev/null)" = noreply@anthropic.com ] \
    && ok "git identity is Claude <noreply@anthropic.com>" || no "git identity is not the guest's"
[ -f "$HOME/.ssh/id_ed25519" ] && ok "guest has its own ssh key" || no "no guest ssh key"
[ -d "$HOME/projects" ] && ok "the projects folder exists" || no "the projects folder is missing"

echo "-- no shared folder with the host --"
if mount 2>/dev/null | grep -Eiq '9p|virtiofs|host'; then
    no "a host folder seems to be mounted (there should be none)"; mount | grep -Ei '9p|virtiofs'
else
    ok "no 9p/virtiofs host mount"
fi

echo "-- the internet IS reachable --"
yn getent hosts deb.debian.org && ok "DNS resolves" || no "DNS does not resolve"
if connects api.github.com 443 || connects deb.debian.org 443; then
    ok "a public host answers on 443"
else
    no "no public host reachable (expected the internet to work)"
fi

echo "-- the local network is NOT reachable (each should be blocked) --"
for hp in 192.168.0.1:80 192.168.1.1:80 10.0.0.1:80 172.16.0.1:80; do
    if connects "${hp%:*}" "${hp#*:}"; then
        no "reached ${hp} -- the firewall is NOT blocking the LAN"
    else
        ok "${hp} blocked"
    fi
done
echo "  (also try your real router's address by hand: connects ROUTER_IP 80)"

echo
echo "== guest: $pass passed, $fail failed =="
[ "$fail" -eq 0 ]
