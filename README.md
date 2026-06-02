# Olympus — sandbox

A **clone-and-deploy demonstration environment** for
[Olympus](https://github.com/01p5/01p5), kept out of the main repo.

Olympus is built for operators who own their own infrastructure
(Proxmox / bare metal) — that path lives in `01p5` under `infra/`. This
sandbox is the reproducible **public AWS** path: a fresh clone stands up a real
2-node kubeadm cluster on EC2, deploys the Olympus dashboard via its Helm chart,
and fronts it with Let's Encrypt TLS — at **a domain you control**.

Nothing in here is specific to our deployment: every project value (domain,
Cloudflare zone, region, allowlist, keys) comes from a gitignored `inf/env.sh`.
Set those and `./inf/deploy.sh` brings the whole thing up.

## Quick start

```bash
git clone <this repo> && cd <this repo>

# 1. configure — copy the template and fill in YOUR values
cp inf/env.sh.template inf/env.sh
$EDITOR inf/env.sh          # at minimum: TF_VAR_dns_hostname, a Cloudflare
                            # token + zone id, AWS creds (~/.aws or AWS_* env)

# 2. preflight — read-only checks (tools, creds, DNS token, config)
./inf/preflight.sh

# 3. deploy — terraform (cluster + DNS) then ansible (kubeadm + Olympus + TLS)
./inf/deploy.sh             # ~15-20 min; image builds on the worker, cert issues

# 4. verify — health, DNS, TLS, dashboard
./inf/verify.sh
# → open https://<your dns_hostname>/
```

By default the dashboard runs in **manual-router** mode (no LLM key needed). Set
`OLYMPUS_ROUTER=llm` + a provider key in `inf/env.sh` to exercise the LLM agents
and the group-chat coordinator. See [`inf/README.md`](inf/README.md) for the
full runbook (prerequisites, auth/OTP wiring, NetDB, tear-down, cost).

## Layout

- [`inf/deploy.sh`](inf/deploy.sh) — the entry point. `deploy.sh` (apply +
  ansible), `--fresh` (destroy + redeploy), `--ansible-only`, `--destroy`,
  `netdb-up`.
- [`inf/preflight.sh`](inf/preflight.sh) / [`inf/verify.sh`](inf/verify.sh) —
  pre-apply checks / post-deploy health probes.
- [`inf/env.sh.template`](inf/env.sh.template) — every config + secret, with
  docs. Copy to `inf/env.sh` (gitignored).
- [`inf/terraform`](inf/terraform) — VPC + 2 EC2 (control-plane + worker) + EIP
  + Cloudflare DNS; writes the Ansible inventory.
- [`inf/ansible`](inf/ansible) — kubeadm bootstrap + Helm-deploy Olympus + the
  nginx/certbot TLS front, all over SSH.
- [`inf/webfront`](inf/webfront) — vendored nginx + certbot reverse proxy.
- [`inf/netdb`](inf/netdb) — optional persistent NetDB/Technitium DNS server
  (IPAM/DNS/DHCP over MCP). See [`inf/netdb/README.md`](inf/netdb/README.md).
- `inf/deployment/` — Terraform-generated artifacts (`inventory.ini`, `k8s.pem`),
  gitignored.

## No secrets here

This repo is public. No credentials are committed — the Cloudflare token, LLM
keys, OAuth/SMTP secrets, and your domain all live in the gitignored
`inf/env.sh` and are passed at apply time. The committed defaults are
`example.com` placeholders.
