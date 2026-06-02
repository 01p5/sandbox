# NetDB / Technitium DNS server (optional)

Stands up [NetDB](https://github.com/01p5/netdb) (IPAM) + Technitium (DNS) + Kea
(DHCP) on a **dedicated, persistent EC2 box** and wires its ~32 tools into
Olympus's **sysadmin** agent over MCP. The box has its **own terraform state**,
so a cluster `deploy.sh --fresh` never tears it down — your authoritative zone +
IPAM data survive redeploys.

This is optional: skip it and Olympus runs exactly as before (`netdb_mcp_host`
empty ⇒ no netdb MCP server wired).

## One-time bring-up

1. **Pick your zone.** NetDB's Technitium becomes authoritative for a subdomain
   you delegate to it (e.g. `lab.example.com`). The parent zone
   (`example.com`) must already exist in your Cloudflare account.
   Set in `terraform/terraform.tfvars` (copy from `.example`):
   ```hcl
   delegated_zone       = "lab.example.com"
   ns_hostname          = "ns1.lab.example.com"
   cloudflare_zone_name = "example.com"
   cloudflare_zone_id   = "<your-zone-id>"
   admin_cidr           = "<your-ip>/32"      # SSH + Technitium console
   mcp_ingress_cidr     = "<cluster-eip>/32"  # who can drive netdb /mcp
   ```
2. **Creds** in `inf/env.sh`: `TF_VAR_cloudflare_api_token` (Zone:DNS:Edit),
   `DNS_SERVER_ADMIN_PASSWORD` (Technitium admin), optional
   `NETDB_CLOUDFLARE_TOKEN` (netdb's own Cloudflare provider).
3. **Run it** (creates a new EC2 + EIP + Cloudflare NS delegation — has cost):
   ```bash
   ./inf/deploy.sh netdb-up
   ```
   It prints the server EIP.
4. **Wire Olympus**: set `netdb_mcp_host: "<that EIP>"` in
   `inf/ansible/group_vars/all.yml`, then `./inf/deploy.sh --ansible-only`.

## Verify

```bash
dig NS lab.example.com +short          # -> ns1.lab.example.com (delegation live)
curl http://<eip>:8080/healthz         # -> ok
```
In the dashboard, the `/mcp` "NetDB integration" card shows connected (32 tools
on the sysadmin agent). Ask the agent to create a host + A record → approval
card → the record resolves under your delegated zone.

## Layout

- `terraform/` — separate root: own VPC/subnet/SG, the EC2 + EIP, Cloudflare NS
  delegation. Own state (never destroyed by the cluster's `--fresh`).
- `ansible/netdb.yml` — installs Docker, brings up the netdb compose stack
  (`docker-compose.yml` + `compose.prod.yaml`, publishes `:53`), seeds the zone.

> Deeper docs/scripts are coming — this is the working integration.
