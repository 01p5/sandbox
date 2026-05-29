# Olympus — sandbox

A **demonstration environment** for [Olympus](https://github.com/01p5/01p5),
deliberately kept out of the main repo.

Olympus is built for operators who own their own infrastructure
(Proxmox / bare metal) — that's the supported, intended path and it lives
in `01p5` under `infra/terraform/pve`. This sandbox provides the one thing
that path can't: a public AWS deployment a reviewer can reach. It stands up
a real 2-node kubeadm cluster on EC2, deploys the Olympus dashboard, and
fronts it with TLS at **https://0lympu5.com/**.

## Layout

- [`inf/terraform`](inf/terraform) — the AWS demo: VPC + 2 EC2 (control-plane
  + worker), Cloudflare DNS, outputs.
- [`inf/bootstrap`](inf/bootstrap) — per-node first-boot scripts
  (`common.sh`, `control-plane.sh`, `worker.sh`) the nodes clone + run.
- [`inf/webfront`](inf/webfront) — vendored nginx + certbot TLS reverse
  proxy (Let's Encrypt), run via docker-compose on the control-plane.
- [`inf/env.sh.template`](inf/env.sh.template) — optional env exports
  (region, Cloudflare token, provider keys); copy to `inf/env.sh`
  (gitignored).
- `inf/deployment/` — Terraform-generated artifacts (`k8s.pem`), gitignored.

## Quick start

```bash
cd inf/terraform
export TF_VAR_cloudflare_api_token=...   # never commit
terraform init && terraform apply
# ~15-20 min later (image build + cert issuance):
open "$(terraform output -raw dashboard_url)"
```

See [`inf/README.md`](inf/README.md) for the full runbook, architecture,
and tear-down.

## No secrets here

This repo is public. No credentials are committed — the Cloudflare token
and any LLM provider keys are supplied at apply time via `TF_VAR_*` env
vars / gitignored `terraform.tfvars`.
