#!/usr/bin/env bash
#
# Preflight checks for the Olympus sandbox deploy. Read-only — makes NO changes
# to AWS or DNS. Run it before ./inf/deploy.sh to catch missing tools, creds,
# or config up front instead of failing 10 minutes into a terraform apply.
#
#   ./inf/preflight.sh
#
# Exits non-zero if any hard requirement is missing. Warnings (⚠) don't fail.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_SH="${HERE}/env.sh"

green() { printf '\033[32m✓\033[0m %s\n' "$*"; }
warn()  { printf '\033[33m⚠\033[0m %s\n' "$*"; }
err()   { printf '\033[31m✗\033[0m %s\n' "$*" >&2; }

fails=0
fail() { err "$*"; fails=$((fails+1)); }

echo "── Olympus sandbox preflight ──"

# 1. env.sh present + sourced
if [[ -f "$ENV_SH" ]]; then
  # shellcheck source=/dev/null
  source "$ENV_SH"
  green "env.sh found + sourced"
else
  fail "inf/env.sh missing — cp inf/env.sh.template inf/env.sh and fill it in"
  echo; err "$fails hard failure(s). Fix env.sh first."; exit 1
fi

# 2. required CLI tools (terraform authenticates to AWS via ~/.aws or AWS_* env;
#    the `aws` CLI is convenient but not required, so it's advisory)
for tool in terraform ansible-playbook curl ssh; do
  if command -v "$tool" >/dev/null 2>&1; then
    green "$tool present"
  else
    fail "$tool not found on PATH"
  fi
done

# 3. AWS credentials + region
if command -v aws >/dev/null 2>&1; then
  if ident=$(aws sts get-caller-identity --query Arn --output text 2>/dev/null); then
    green "AWS credentials valid ($ident)"
  else
    fail "AWS credentials not usable — aws sts get-caller-identity failed (configure ~/.aws or AWS_* env)"
  fi
elif [[ -n "${AWS_ACCESS_KEY_ID:-}" || -f "$HOME/.aws/credentials" ]]; then
  green "AWS creds present (AWS_* env or ~/.aws); install the aws CLI to verify them"
else
  warn "no aws CLI and no obvious AWS creds (AWS_* env / ~/.aws) — terraform apply will fail without credentials"
fi
[[ -n "${AWS_REGION:-${TF_VAR_aws_region:-}}" ]] && green "AWS region = ${AWS_REGION:-$TF_VAR_aws_region}" \
  || warn "AWS region unset — terraform var default will be used"

# 4. deploy target (domain)
host="${TF_VAR_dns_hostname:-}"
if [[ -z "$host" || "$host" == *example.com ]]; then
  fail "TF_VAR_dns_hostname is unset or still a placeholder ('$host') — set it to a domain you control"
else
  green "deploy hostname = $host"
fi
[[ -n "${DEPLOY_CERTBOT_EMAIL:-}" && "${DEPLOY_CERTBOT_EMAIL}" != *example.com ]] \
  && green "certbot email set" || warn "DEPLOY_CERTBOT_EMAIL unset/placeholder — Let's Encrypt wants a real address"

# 5. Cloudflare token + zone (read-only API probe)
token="${TF_VAR_cloudflare_api_token:-}"
zone="${TF_VAR_cloudflare_zone_id:-}"
if [[ -z "$token" ]]; then
  warn "TF_VAR_cloudflare_api_token empty — DNS won't be managed; you'll point $host by hand"
else
  vr=$(curl -s --max-time 10 -H "Authorization: Bearer $token" \
        https://api.cloudflare.com/client/v4/user/tokens/verify 2>/dev/null)
  if grep -q '"status":"active"' <<<"$vr"; then
    green "Cloudflare token verified (active)"
  else
    fail "Cloudflare token did not verify — check Zone:DNS:Edit scope"
  fi
  if [[ -z "$zone" ]]; then
    fail "TF_VAR_cloudflare_zone_id empty but a token is set — set the zone id for $host"
  else
    zr=$(curl -s --max-time 10 -H "Authorization: Bearer $token" \
          "https://api.cloudflare.com/client/v4/zones/$zone" 2>/dev/null)
    if grep -q '"success":true' <<<"$zr"; then
      # Pick the domain-shaped "name" (the zone's), not nested ones like the
      # plan name ("Free Website"). Greedy .* used to grab the last match.
      zname=$(grep -oE '"name":"[a-zA-Z0-9.-]+"' <<<"$zr" | sed -E 's/"name":"//; s/"//' \
                | grep -E '\.[a-z]{2,}$' | head -1)
      green "Cloudflare zone reachable${zname:+ ($zname)}"
      [[ -n "$zname" && "$host" != *"$zname" ]] && warn "  $host is not under zone $zname — double-check the zone id"
    else
      fail "Cloudflare zone id '$zone' not reachable with this token"
    fi
  fi
fi

# 6. router vs provider key
router="${OLYMPUS_ROUTER:-manual}"
if [[ "$router" == "llm" ]]; then
  if [[ -n "${OPENAI_API_KEY:-}" || -n "${ANTHROPIC_API_KEY:-}" ]]; then
    green "router=llm and a provider key is set"
  else
    fail "OLYMPUS_ROUTER=llm but no OPENAI_API_KEY / ANTHROPIC_API_KEY set"
  fi
else
  green "router=manual (no LLM key required)"
fi

# 7. auth allowlist sanity (warning only)
[[ -z "${DEPLOY_AUTH_ALLOWED_DOMAINS:-}" ]] \
  && warn "DEPLOY_AUTH_ALLOWED_DOMAINS empty — no one will pass login until you set it (or '*')" \
  || green "auth allowlist = ${DEPLOY_AUTH_ALLOWED_DOMAINS}"

echo "──"
if [[ "$fails" -gt 0 ]]; then
  err "$fails hard failure(s) — fix before deploying."; exit 1
fi
green "preflight passed — ./inf/deploy.sh is good to go"
