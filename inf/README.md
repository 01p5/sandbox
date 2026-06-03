# Olympus — AWS demo deployment (runbook)

A reproducible deployment of Olympus on AWS: a real 2-node
[kubeadm](https://kubernetes.io/docs/reference/setup-tools/kubeadm/) cluster
(1 control-plane + 1 worker), the Olympus dashboard via its Helm chart, fronted
by an nginx + Let's Encrypt TLS reverse proxy — served at **a domain you
control** (`TF_VAR_dns_hostname`).

> This is *not* the intended production path. Olympus is built for operators who
> own their own infrastructure (Proxmox / bare metal) — see `infra/` in the main
> `01p5` repo. This AWS stack exists so a reviewer can open a link and see it
> running, and so anyone can reproduce it on their own domain.

## Architecture

```
Browser ──https──> Cloudflare DNS (A, DNS-only) ──> control-plane EIP
                                                       │ :80/:443
   ┌──────────────── control-plane (t3.medium) ────────┴───────────┐
   │  webfront: nginx + certbot (docker-compose, host network)      │
   │    • Let's Encrypt HTTP-01 cert for $dns_hostname              │
   │    • proxies 127.0.0.1:30093 (dashboard NodePort)              │
   │  kubeadm control plane (tainted) + Calico CNI                  │
   └───────────────────────────────┬───────────────────────────────┘
                                    │ Calico pod network
   ┌──────────────── worker (t3.large) ─────────────────────────────┐
   │  builds the Olympus image on first boot, imports into          │
   │  containerd, runs the dashboard pod (NodePort 30093)           │
   └─────────────────────────────────────────────────────────────────┘
```

**Terraform provisions, Ansible deploys.** Terraform stands up the two blank
Ubuntu boxes (+ network, EIP, DNS) and writes an Ansible inventory to
`deployment/inventory.ini`. `ansible/site.yml` then does everything over SSH:
containerd + the kubeadm stack on both nodes, `kubeadm init` + Calico on the
control-plane, Helm-deploy the dashboard (with all agent runtimes incl. the
`main` coordinator + `hpc`), bring up the TLS front, then build the image on the
worker and join it. No registry needed (the worker builds the image; the
control-plane taint keeps the pod on the worker). The playbook is idempotent.

`deploy.sh` orchestrates all of this; you don't run terraform/ansible by hand.

## Prerequisites

- **Terraform ≥ 1.6**, **Ansible**, **curl**, **ssh** on your machine.
- **AWS credentials** for the target account (via `~/.aws` or `AWS_*` env). The
  `aws` CLI is optional (Terraform doesn't need it) but lets preflight verify
  creds.
- **A domain in a Cloudflare zone** + an API token with `Zone:DNS:Edit`. Without
  a token, DNS is unmanaged and you point the A-record by hand.

## Configure

Everything project-specific lives in `inf/env.sh` (gitignored). Copy the
template and fill it in:

```bash
cp inf/env.sh.template inf/env.sh
```

Minimum to set:

| Variable | What |
|----------|------|
| `TF_VAR_dns_hostname` | the hostname to serve at, e.g. `olympus.example.com` |
| `DEPLOY_CERTBOT_EMAIL` | a real email for Let's Encrypt |
| `TF_VAR_cloudflare_api_token` + `TF_VAR_cloudflare_zone_id` | manage DNS automatically |
| AWS creds | `~/.aws` or `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` |

Optional: `OLYMPUS_ROUTER=llm` + `OPENAI_API_KEY`/`ANTHROPIC_API_KEY` (LLM
agents), `DEPLOY_AUTH_ALLOWED_DOMAINS` + the `OLYMPUS_GOOGLE_*`/`OLYMPUS_SMTP_*`
secrets (login), and the NetDB block (`deploy.sh netdb-up`). The committed
group_vars defaults are `example.com` placeholders; `deploy.sh` overrides them
from `env.sh`, so nothing project-specific is baked into the repo.

## Deploy

```bash
./inf/preflight.sh        # read-only: tools, creds, DNS token, config
./inf/deploy.sh           # terraform apply + ansible (~15-20 min)
./inf/verify.sh           # health / DNS / TLS / dashboard
```

`deploy.sh` modes: bare (apply if needed + ansible), `--fresh` (destroy +
apply + ansible), `--ansible-only` (re-run the playbook — fast, idempotent),
`--destroy`, `netdb-up` (stand up the persistent NetDB/DNS server). Preflight
runs automatically before the apply paths (`SKIP_PREFLIGHT=1` to bypass);
`verify.sh` runs after.

The terraform step takes a couple of minutes; ansible runs **~15 min**,
dominated by the worker building the dashboard image on-box. The cert is issued
during the run once DNS resolves to the control-plane EIP.

## Outputs

| Output | What |
|--------|------|
| `dashboard_url` | `https://<dns_hostname>/` |
| `public_ip` | control-plane Elastic IP (the DNS target) |
| `control_plane_ssh` / `worker_ssh` | ready-to-paste SSH lines |
| `dns_record` | whether Terraform manages the Cloudflare record |

## Tear-down

```bash
./inf/deploy.sh --destroy
```

Removes the cluster instances + managed DNS record. A fresh `./inf/deploy.sh`
rebuilds it (the EIP, and so the A-record, will change). The optional NetDB
server has its own state and is **not** torn down by this — destroy it from
`inf/netdb/terraform` if you brought it up.

## Notes / caveats

- **The Ansible run is slow** — the image builds on the worker (no registry),
  ~12 min, synchronously over SSH. Re-runs are fast (idempotent).
- **Cert issuance waits for DNS** — the playbook waits for `$dns_hostname` to
  resolve to the control-plane EIP before starting webfront, so the HTTP-01
  challenge doesn't burn Let's Encrypt rate limits. Set `certbot_staging: "1"`
  in `ansible/group_vars/all.yml` while iterating.
- **Router defaults to manual** — runs with no LLM key. Set `OLYMPUS_ROUTER=llm`
  + a key for the LLM-driven agents.
- **Cost** — 2 EC2 (`t3.medium` + `t3.large`) + an EIP. Roughly a few dollars a
  day in `us-west-2`; `--destroy` when you're done. NetDB adds one small `t3.small`.
- **No secrets are committed.** Cloudflare token + provider keys + OAuth/SMTP
  secrets + your domain all come from `inf/env.sh`; `inf/env.sh` and
  `inf/deployment/` are gitignored.
