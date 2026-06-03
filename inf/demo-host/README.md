# Demo: terraform → inventory → ansible (reproducible)

A repeatable, on-camera demo: an agent provisions a host with Terraform, it
auto-registers into Olympus's runtime inventory, an agent runs Ansible against
it, then we tear it down. Validated end-to-end on the sandbox
(`https://0lympu5.com`, logged in as an `@tianleyu.com` admin).

**Proven result:** `terraform apply` (in the pod, with the wired AWS creds) →
`POST /inventory/sync-terraform` → `demo-host` on the Hosts page →
`ansible run_module uptime` over SSH →
`00:02:41 up 2 min, 1 user, load average: 0.11, 0.04, 0.01` → `terraform destroy`.

> Prereqs (already done on this sandbox): `hardening.selfProtect: false`, AWS +
> Cloudflare creds wired into the dashboard pod, login locked to `tianleyu.com`
> with admin. The `cluster` SSH key is already in the inventory store, and the
> stack launches the host with the matching `olympus-sandbox-key` keypair in the
> cluster subnet (SG allows SSH from the cluster), so it's reachable + loginable.

## What's here

- `main.tf` — the validated stack: one `t3.micro` Ubuntu host in the sandbox
  VPC/subnet, SG allowing SSH from the cluster nodes, launched with the cluster
  keypair, plus the `olympus_inventory_hosts` output. (Network ids are this
  sandbox's; re-grab them from `terraform state show` in `inf/terraform` if you
  `--fresh` the cluster.)
- `stage.sh` — copy the stack into the dashboard pod (run once per session).
- `reset.sh` — destroy the host + remove it from the inventory (between takes).

## One-time per session

```bash
./inf/demo-host/stage.sh        # puts main.tf at /tmp/demo-host in the pod
```

## The take (in the dashboard chat, as an admin)

1. **Provision (agent + Terraform).** Send:
   > *"Use the terraform agent to apply the stack at `/tmp/demo-host` — it
   > provisions a demo host and exposes an `olympus_inventory_hosts` output."*

   The coordinator dispatches → terraform agent runs `tf_init`/`tf_plan`/`tf_apply`
   → **Approve** the `tf_apply` card. (For a richer beat, first ask the
   *programmer* agent to write the stack — see "Agent-authored" below.)

2. **Register (operator one-liner).** Seed the inventory from the stack's output.
   Easiest: paste this in the browser devtools console (you're already the
   authenticated admin, so the session cookie rides along):
   ```js
   fetch('/inventory/sync-terraform', {method:'POST',
     headers:{'Content-Type':'application/json'}, credentials:'same-origin',
     body: JSON.stringify({working_dir:'/tmp/demo-host'})}).then(r=>r.json()).then(console.log)
   // → {added:["demo-host"], skipped:[], errors:[]}
   ```

3. **Show it landed.** Open **Hosts** → `demo-host · ubuntu@10.20.x.x · key:
   cluster · "synced from terraform"`.

4. **Manage it (agent + Ansible).** Send:
   > *"Use ansible to run the command `uptime` on the `demo-host` host and show
   > me the output."*

   → ansible agent `list_inventory` → **Approve** `run_module` → real `uptime`
   output from the new box.

## Reset between takes

```bash
./inf/demo-host/reset.sh        # terraform destroy + remove-host
```

Re-run from step 1 for the next take. (`stage.sh` only needs re-running if the
pod restarted.)

## Variations

- **Agent-authored stack** (more impressive): instead of `stage.sh`, ask the
  programmer agent on camera —
  > *"Write a terraform stack to `/tmp/demo-host/main.tf` that provisions a
  > t3.micro Ubuntu host (ami-0866907c81fbbd49e) in subnet
  > subnet-0360263bcdbc0dec3 with key_name olympus-sandbox-key and a security
  > group in vpc vpc-0f203203db131039e allowing SSH from sg-099abd133be8353cb,
  > and expose it as an `olympus_inventory_hosts` output (name demo-host,
  > ssh_user ubuntu, key cluster, groups [demo])."*

  then continue from step 1's apply.

- **One-click register:** a "Sync from Terraform" button on the Hosts page can
  replace the devtools snippet in step 2 (ask and it can be added).
