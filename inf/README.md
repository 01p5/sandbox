# Olympus — AWS demo deployment

A **throwaway demonstration** of Olympus on AWS: a real 2-node
[kubeadm](https://kubernetes.io/docs/reference/setup-tools/kubeadm/)
cluster (1 control-plane + 1 worker), the Olympus dashboard deployed via
its Helm chart, fronted by an nginx + Let's Encrypt TLS reverse proxy,
reachable at **https://0lympu5.com/**.

> This is *not* the intended production path. Olympus is built for
> operators who own their own infrastructure (Proxmox / bare metal) — see
> `infra/terraform/pve` in the main `01p5` repo. This AWS stack exists only
> so a reviewer can open a link and see the thing running.

## Architecture

```
Browser ──https──> Cloudflare DNS (A, DNS-only) ──> control-plane EIP
                                                       │ :80/:443
   ┌──────────────── control-plane (t3.medium) ────────┴───────────┐
   │  webfront: nginx + certbot (docker-compose, host network)      │
   │    • Let's Encrypt HTTP-01 cert for 0lympu5.com               │
   │    • proxies 127.0.0.1:30093 (dashboard NodePort)             │
   │  kubeadm control plane (tainted) + Calico CNI                  │
   └───────────────────────────────┬───────────────────────────────┘
                                    │ Calico pod network
   ┌──────────────── worker (t3.large) ─────────────────────────────┐
   │  builds the Olympus image on first boot, imports into          │
   │  containerd, runs the dashboard pod (NodePort 30093)           │
   └─────────────────────────────────────────────────────────────────┘
```

**Terraform provisions, Ansible deploys.** Terraform stands up the two
blank Ubuntu boxes (+ network, EIP, DNS) and writes an Ansible inventory to
`../deployment/inventory.ini`. `inf/ansible/site.yml` then does everything
over SSH: containerd + the kubeadm stack on both nodes, `kubeadm init` +
Calico on the control-plane, Helm-deploy the dashboard, bring up the TLS
front, then build the image on the worker and join it. The worker builds
the image (no registry needed); the control-plane taint keeps the dashboard
pod on the worker, so the image is always where the pod runs. The playbook
is idempotent — re-run it freely; nothing is rebuilt that already exists.

## Why these choices (vs the k3s single-node it replaced)

- **kubeadm 1.30 + Calico** — a "real" cluster, matching the conventions of
  the main repo's PVE path.
- **NodePort 30093, not LoadBalancer** — kubeadm has no built-in
  LoadBalancer (k3s gave us one for free). nginx proxies to the NodePort on
  localhost; the port stays private (SG opens only 22/80/443).
- **DNS-only Cloudflare record** — required for the HTTP-01 cert and for
  nginx to terminate TLS directly.

## Prerequisites

- Terraform ≥ 1.6, AWS credentials for the target account.
- A Cloudflare API token with `Zone:DNS:Edit` on the zone (export as
  `TF_VAR_cloudflare_api_token`). Without it, DNS is unmanaged and you point
  the record by hand.

## Deploy

```bash
# 1) provision + write the Ansible inventory
cd inf/terraform
cp terraform.tfvars.example terraform.tfvars   # optional — defaults work
export TF_VAR_cloudflare_api_token=...          # never commit this
terraform init
terraform apply

# 2) bootstrap the cluster + deploy Olympus over SSH
cd ../ansible
ansible-playbook site.yml
#   optional LLM agents:
#     ansible-playbook site.yml -e olympus_router=llm -e openai_api_key=sk-...
#
#   full public-demo wiring (auth + email-OTP + hardening):
#     source ../env.sh                                  # see env.sh.template
#     ansible-playbook site.yml \
#         -e olympus_router=llm \
#         -e openai_api_key="$OPENAI_API_KEY" \
#         -e session_secret="$OLYMPUS_SESSION_SECRET" \
#         -e google_client_id="$OLYMPUS_GOOGLE_CLIENT_ID" \
#         -e google_client_secret="$OLYMPUS_GOOGLE_CLIENT_SECRET" \
#         -e smtp_host="$OLYMPUS_SMTP_HOST" \
#         -e smtp_username="$OLYMPUS_SMTP_USERNAME" \
#         -e smtp_password="$OLYMPUS_SMTP_PASSWORD"
```

`terraform apply` takes a couple of minutes. `ansible-playbook` then runs
**~15 min**, dominated by the worker building the dashboard image (no
registry, so it's built on-box). The certbot cert is issued during the run
once DNS resolves to the control-plane EIP.

When it finishes:

```bash
curl https://0lympu5.com/healthz     # → {"ok": true}
open  https://0lympu5.com/
```

Re-running `ansible-playbook site.yml` is safe and fast (idempotent) — it's
the fix-and-retry loop, no instance rebuilds.

## Outputs

| Output | What |
|--------|------|
| `dashboard_url` | `https://0lympu5.com/` |
| `public_ip` | control-plane Elastic IP (DNS target) |
| `control_plane_ssh` / `worker_ssh` | ready-to-paste SSH lines |
| `dns_record` | whether Terraform manages the Cloudflare record |

## Tear-down

```bash
terraform destroy
```

## Notes / caveats

- **The Ansible run is slow** — the image builds on the worker (no
  registry), ~12 min, run synchronously over SSH.
- **Provider keys** are passed to Ansible via `-e` at runtime and stored as
  a k8s Secret. The kubeadm join token is generated on the control-plane at
  deploy time (`kubeadm token create`), not pre-shared. Nothing sensitive
  lands in EC2 user_data (there is none).
- **Cert issuance waits for DNS** — the playbook waits for `0lympu5.com` to
  resolve to the control-plane EIP before starting webfront, so the HTTP-01
  challenge doesn't burn Let's Encrypt rate limits. Set
  `certbot_staging: "1"` in `group_vars/all.yml` if you're iterating.
- **No secrets are committed.** Cloudflare token via `TF_VAR_*`; provider
  keys via `ansible-playbook -e`. `inf/env.sh` and `inf/deployment/` are
  gitignored.
- **Tear-down replaces the cluster.** `terraform destroy` removes the
  instances; a fresh apply + playbook rebuilds it (and the EIP changes).
