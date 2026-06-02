#!/usr/bin/env bash
#
# Post-deploy verification for the Olympus sandbox. Read-only probes that
# confirm the stack actually came up. Run after ./inf/deploy.sh.
#
#   ./inf/verify.sh
#
# Reads the target hostname from inf/env.sh (TF_VAR_dns_hostname). Exits
# non-zero if a hard check fails (health / DNS); cert + MCP are advisory.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_SH="${HERE}/env.sh"
[[ -f "$ENV_SH" ]] && { . "$ENV_SH"; }

green() { printf '\033[32m✓\033[0m %s\n' "$*"; }
warn()  { printf '\033[33m⚠\033[0m %s\n' "$*"; }
err()   { printf '\033[31m✗\033[0m %s\n' "$*" >&2; }

host="${1:-${TF_VAR_dns_hostname:-}}"
[[ -n "$host" && "$host" != *example.com ]] || { err "no real hostname (set TF_VAR_dns_hostname or pass one as \$1)"; exit 1; }

echo "── verifying https://$host ──"
fails=0

# 1. DNS resolves
if ip=$(getent hosts "$host" 2>/dev/null | awk '{print $1; exit}'); [[ -n "${ip:-}" ]]; then
  green "DNS: $host → $ip"
else
  err "DNS: $host does not resolve yet (propagation can take a minute)"; fails=$((fails+1))
fi

# 2. TLS cert issued for the host (advisory — staging/early runs may lag)
if cn=$(echo | openssl s_client -servername "$host" -connect "$host:443" 2>/dev/null \
        | openssl x509 -noout -subject 2>/dev/null); then
  green "TLS: cert present (${cn#subject=})"
else
  warn "TLS: no cert yet — Let's Encrypt issuance can take a few minutes on first boot"
fi

# 3. /healthz returns ok
code=$(curl -s --max-time 15 -o /tmp/olympus-healthz.$$ -w '%{http_code}' "https://$host/healthz" 2>/dev/null || echo 000)
if [[ "$code" == "200" ]] && grep -q '"ok"' /tmp/olympus-healthz.$$ 2>/dev/null; then
  green "health: https://$host/healthz → 200 ok"
else
  err "health: https://$host/healthz → $code (not ready)"; fails=$((fails+1))
fi
rm -f /tmp/olympus-healthz.$$

# 4. dashboard SPA serves (advisory)
if curl -s --max-time 15 "https://$host/" 2>/dev/null | grep -qiE "olympus|<div id=\"root\""; then
  green "dashboard: SPA served at https://$host/"
else
  warn "dashboard: root page didn't look like the SPA yet"
fi

# 5. NetDB MCP wired? (advisory — only if netdb_mcp_host was set)
nd="$(grep -E '^netdb_mcp_host:' "$HERE/ansible/group_vars/all.yml" 2>/dev/null | sed -E 's/.*: *"?([^"]*)"?.*/\1/')"
if [[ -n "$nd" ]]; then
  if curl -s --max-time 10 "http://$nd:8080/healthz" >/dev/null 2>&1; then
    green "netdb: server at $nd reachable (MCP grafted onto sysadmin)"
  else
    warn "netdb: $nd:8080 not reachable from here (it's locked to the cluster — normal)"
  fi
fi

echo "──"
if [[ "$fails" -gt 0 ]]; then
  err "$fails hard check(s) failed — the deploy isn't fully up. Re-run after a minute, or check /tmp/olympus-deploy-*.log."
  exit 1
fi
green "verify passed — Olympus is live at https://$host/"
