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

Each node clones **this sandbox repo** on first boot and runs its role
script (`inf/bootstrap/{control-plane,worker}.sh`, both sourcing
`common.sh`). The worker builds the image (no registry needed); the
control-plane taint keeps the dashboard pod on the worker, so the image is
always where the pod runs.

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
cd inf/terraform
cp terraform.tfvars.example terraform.tfvars   # optional — defaults work

export TF_VAR_cloudflare_api_token=...          # never commit this
# optional LLM agents:
#   export TF_VAR_olympus_router=llm
#   export TF_VAR_openai_api_key=sk-...

terraform init
terraform apply
```

`apply` returns in a few minutes; the cluster then needs **~15–20 min**:
the worker builds the image, joins, the dashboard schedules, and certbot
issues the cert once DNS resolves. Watch it:

```bash
ssh -i ../deployment/k8s.pem ubuntu@$(terraform output -raw public_ip) \
    'sudo tail -f /var/log/olympus-bootstrap.log'
# and the TLS front:
ssh ... 'cd /opt/webfront && sudo docker compose logs -f'
```

When ready:

```bash
curl https://0lympu5.com/healthz     # → {"ok": true}
open  https://0lympu5.com/
```

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

- **First boot is slow** — the image builds on the worker (no registry).
- **Provider keys + the join token live in user_data** (IMDS-readable).
  Fine for a throwaway demo; never reuse a production key.
- **Cert issuance needs DNS live first** — the control-plane waits for
  `0lympu5.com` to resolve to its EIP before starting webfront, so the
  HTTP-01 challenge doesn't burn Let's Encrypt rate limits. Set
  `certbot_staging = "1"` if you're iterating.
- **No secrets are committed.** Token + keys come from `TF_VAR_*` env.
