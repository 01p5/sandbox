#!/usr/bin/env bash
#
# Turn-key sandbox deploy for Olympus.
#
# Usage:
#   ./inf/deploy.sh                # apply infra (if missing) + ansible
#   ./inf/deploy.sh --fresh        # destroy + apply + ansible (clean redeploy)
#   ./inf/deploy.sh --ansible-only # ansible only (assumes infra is up)
#   ./inf/deploy.sh --destroy      # destroy only (no rebuild)
#   ./inf/deploy.sh netdb-up       # one-time: stand up the PERSISTENT NetDB /
#                                  #   DNS server (separate state — survives
#                                  #   cluster redeploys). Prints the EIP to set
#                                  #   as netdb_mcp_host in group_vars.
#
# Reads creds from ./inf/env.sh (gitignored). Logs each phase to
# /tmp/olympus-deploy-<phase>.log.
#
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_SH="${HERE}/env.sh"
TF_DIR="${HERE}/terraform"
ANSIBLE_DIR="${HERE}/ansible"
NETDB_TF_DIR="${HERE}/netdb/terraform"
NETDB_ANSIBLE_DIR="${HERE}/netdb/ansible"

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
  # Deploy params come from env.sh so the committed group_vars stay generic
  # (example.com). Anything unset falls back to the group_vars default.
  #   - router defaults to "manual" (no LLM key needed); set OLYMPUS_ROUTER=llm
  #     once you've set a provider key to exercise the LLM-driven agents.
  #   - host / email / allowlist come from the DEPLOY_* / TF_VAR_dns_hostname env.
  local router="${OLYMPUS_ROUTER:-manual}"
  local extra=(
    -e "olympus_router=${router}"
    -e "session_secret=${OLYMPUS_SESSION_SECRET:-}"
    -e "google_client_id=${OLYMPUS_GOOGLE_CLIENT_ID:-}"
    -e "google_client_secret=${OLYMPUS_GOOGLE_CLIENT_SECRET:-}"
    -e "smtp_host=${OLYMPUS_SMTP_HOST:-}"
    -e "smtp_username=${OLYMPUS_SMTP_USERNAME:-}"
    -e "smtp_password=${OLYMPUS_SMTP_PASSWORD:-}"
    -e "smtp_from=${OLYMPUS_SMTP_FROM:-}"
    -e "openai_api_key=${OPENAI_API_KEY:-${TF_VAR_openai_api_key:-}}"
    -e "anthropic_api_key=${ANTHROPIC_API_KEY:-${TF_VAR_anthropic_api_key:-}}"
  )
  # Only override the generic group_vars defaults when the operator set them.
  [[ -n "${TF_VAR_dns_hostname:-}" ]]        && extra+=(-e "dns_hostname=${TF_VAR_dns_hostname}")
  [[ -n "${DEPLOY_CERTBOT_EMAIL:-}" ]]       && extra+=(-e "certbot_email=${DEPLOY_CERTBOT_EMAIL}")
  [[ -n "${DEPLOY_AUTH_ALLOWED_DOMAINS:-}" ]] && extra+=(-e "auth_allowed_domains=${DEPLOY_AUTH_ALLOWED_DOMAINS}")
  ( cd "$ANSIBLE_DIR" && ansible-playbook site.yml "${extra[@]}" ) \
    2>&1 | tee /tmp/olympus-deploy-ansible.log
  green "✓ ansible complete (router=${router})"
}

verify_live() {
  step "verify live"
  local host="${TF_VAR_dns_hostname:-}"
  [[ -n "$host" ]] || { red "  TF_VAR_dns_hostname unset — skipping live check (set it in env.sh)"; return 0; }
  if curl --max-time 10 -sf "https://${host}/healthz" >/dev/null; then
    green "✓ https://${host}/healthz returns 200"
  else
    red "  warning: https://${host}/healthz didn't respond cleanly — may still be issuing certs (DNS propagation can take a minute)"
  fi
}

netdb_up() {
  # One-time bring-up of the persistent NetDB / Technitium / Kea server.
  # SEPARATE terraform state from the cluster, so cluster --fresh never
  # destroys it. Idempotent: re-running applies + re-provisions in place.
  # Lock netdb's :8080 (no auth, write tools) to the cluster's public egress
  # IPs, derived from the cluster inventory. Without this it'd be internet-open
  # and bypass Olympus's approval queue.
  local inv="${HERE}/deployment/inventory.ini" cidrs
  if [[ -f "$inv" ]]; then
    cidrs=$(awk '{for(i=1;i<=NF;i++) if($i ~ /^ansible_host=/){split($i,a,"="); printf "\"%s/32\",", a[2]}}' "$inv")
    cidrs="[${cidrs%,}]"
    if [[ "$cidrs" != "[]" ]]; then
      export TF_VAR_mcp_ingress_cidrs="$cidrs"
      green "✓ netdb :8080 will be locked to the cluster: $cidrs"
    fi
  fi
  [[ -n "${TF_VAR_mcp_ingress_cidrs:-}" ]] || red "  warning: no cluster inventory found — netdb :8080 falls back to its var default; lock it via terraform.tfvars"

  step "terraform apply — NetDB/DNS server (VPC, EC2 ×1, EIP, Cloudflare NS delegation)"
  # TF_VAR_cloudflare_api_token is already exported by inf/env.sh.
  ( cd "$NETDB_TF_DIR" \
      && terraform init -input=false \
      && terraform apply -auto-approve ) \
    2>&1 | tee /tmp/olympus-deploy-netdb-tf.log
  local eip
  eip="$(cd "$NETDB_TF_DIR" && terraform output -raw netdb_public_ip)"
  [[ -n "$eip" ]] || fail "could not read netdb EIP from terraform output"
  green "✓ NetDB server EIP: $eip"

  step "ansible — provision the NetDB stack (docker compose + zone seed)"
  [[ -n "${DNS_SERVER_ADMIN_PASSWORD:-}" ]] || fail "set DNS_SERVER_ADMIN_PASSWORD in inf/env.sh"
  ( cd "$NETDB_ANSIBLE_DIR" && ansible-playbook netdb.yml \
      -e dns_server_admin_password="${DNS_SERVER_ADMIN_PASSWORD}" \
      -e netdb_cloudflare_token="${NETDB_CLOUDFLARE_TOKEN:-}" \
  ) 2>&1 | tee /tmp/olympus-deploy-netdb-ansible.log
  green "✓ NetDB stack up"
  cyan  "▶ Next: set  netdb_mcp_host: \"$eip\"  in inf/ansible/group_vars/all.yml, then ./inf/deploy.sh --ansible-only"
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
  netdb-up)
    require_env_sh
    netdb_up
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
    sed -n '3,16p' "${BASH_SOURCE[0]}"
    ;;
  *)
    fail "unknown flag: $1 (try --help)"
    ;;
esac
