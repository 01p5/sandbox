#!/usr/bin/env bash
#
# Turn-key sandbox deploy for Olympus.
#
# Usage:
#   ./inf/deploy.sh                # apply infra (if missing) + ansible
#   ./inf/deploy.sh --fresh        # destroy + apply + ansible (clean redeploy)
#   ./inf/deploy.sh --ansible-only # ansible only (assumes infra is up)
#   ./inf/deploy.sh --destroy      # destroy only (no rebuild)
#
# Reads creds from ./inf/env.sh (gitignored). Logs each phase to
# /tmp/olympus-deploy-<phase>.log.
#
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_SH="${HERE}/env.sh"
TF_DIR="${HERE}/terraform"
ANSIBLE_DIR="${HERE}/ansible"

# ---------- helpers ----------
cyan()  { printf '\033[36m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
red()   { printf '\033[31m%s\033[0m\n' "$*" >&2; }
step()  { cyan "▶ $*"; }

fail() { red "✗ $*"; exit 1; }

require_env_sh() {
  [[ -f "$ENV_SH" ]] || fail "$ENV_SH missing — copy env.sh.template + fill in creds"
  # shellcheck source=/dev/null
  source "$ENV_SH"
}

tf_destroy() {
  step "terraform destroy (AWS + Cloudflare)"
  ( cd "$TF_DIR" && terraform destroy -auto-approve ) \
    2>&1 | tee /tmp/olympus-deploy-destroy.log
  green "✓ destroy complete"
}

tf_apply() {
  step "terraform apply (VPC, EC2 ×2, EIP, Cloudflare DNS, inventory.ini)"
  ( cd "$TF_DIR" && terraform init -input=false && terraform apply -auto-approve ) \
    2>&1 | tee /tmp/olympus-deploy-apply.log
  green "✓ apply complete"
}

ansible_deploy() {
  step "ansible-playbook (kubeadm + Olympus + TLS + inventory bootstrap + HPC demo)"
  # The ansible.cfg points at ../deployment/inventory.ini which terraform
  # writes; if that file is missing the apply step never ran (or didn't
  # write it). Bail clearly so the user can fix.
  [[ -f "${HERE}/deployment/inventory.ini" ]] \
    || fail "${HERE}/deployment/inventory.ini missing — run ./inf/deploy.sh apply first"
  ( cd "$ANSIBLE_DIR" && ansible-playbook site.yml \
      -e session_secret="${OLYMPUS_SESSION_SECRET:-}" \
      -e google_client_id="${OLYMPUS_GOOGLE_CLIENT_ID:-}" \
      -e google_client_secret="${OLYMPUS_GOOGLE_CLIENT_SECRET:-}" \
      -e smtp_host="${OLYMPUS_SMTP_HOST:-}" \
      -e smtp_username="${OLYMPUS_SMTP_USERNAME:-}" \
      -e smtp_password="${OLYMPUS_SMTP_PASSWORD:-}" \
      -e smtp_from="${OLYMPUS_SMTP_FROM:-}" \
      -e openai_api_key="${OPENAI_API_KEY:-}" \
      -e anthropic_api_key="${ANTHROPIC_API_KEY:-}" \
      -e olympus_router=llm \
  ) 2>&1 | tee /tmp/olympus-deploy-ansible.log
  green "✓ ansible complete"
}

verify_live() {
  step "verify live"
  local host="${TF_VAR_dns_hostname:-0lympu5.com}"
  if curl --max-time 10 -sf "https://${host}/healthz" >/dev/null; then
    green "✓ https://${host}/healthz returns 200"
  else
    red "  warning: https://${host}/healthz didn't respond cleanly — may still be issuing certs (DNS propagation can take a minute)"
  fi
}

# ---------- args ----------
case "${1:-}" in
  --fresh)
    require_env_sh
    tf_destroy
    tf_apply
    ansible_deploy
    verify_live
    ;;
  --destroy)
    require_env_sh
    tf_destroy
    ;;
  --ansible-only)
    require_env_sh
    ansible_deploy
    verify_live
    ;;
  ""|--default|--up)
    require_env_sh
    # If terraform state is empty (no instances), apply first.
    if ! (cd "$TF_DIR" && terraform state list 2>/dev/null | grep -q aws_instance); then
      tf_apply
    else
      step "terraform state has instances — skipping apply (use --fresh to redeploy)"
    fi
    ansible_deploy
    verify_live
    ;;
  -h|--help)
    sed -n '3,12p' "${BASH_SOURCE[0]}"
    ;;
  *)
    fail "unknown flag: $1 (try --help)"
    ;;
esac
