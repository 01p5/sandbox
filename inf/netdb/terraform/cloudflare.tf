# Delegate <delegated_zone> to this Technitium server.
#
# Two records in the PARENT Cloudflare zone (<cloudflare_zone_name>):
#   - NS  <label>        -> <ns_hostname>   (delegation)
#   - A   <ns label>     -> <netdb EIP>     (glue; the NS host is in-bailiwick)
# After these propagate, resolvers asking for *.<delegated_zone> are referred
# to this box, which Technitium answers authoritatively (zone seeded by the
# netdb Ansible play).
#
# Gated on the token so the root still plans/applies without Cloudflare
# (you'd add the two records by hand).

locals {
  # Cloudflare record names are relative to the zone, so strip the parent
  # zone suffix: "lab.example.com" (zone "example.com") -> "lab".
  zone_suffix       = ".${var.cloudflare_zone_name}"
  delegated_label   = trimsuffix(var.delegated_zone, local.zone_suffix)
  ns_label          = trimsuffix(var.ns_hostname, local.zone_suffix)
  manage_cloudflare = var.cloudflare_api_token != "" ? 1 : 0
}

resource "cloudflare_record" "delegation_ns" {
  count = local.manage_cloudflare

  zone_id = var.cloudflare_zone_id
  name    = local.delegated_label # "lab"
  content = var.ns_hostname       # "ns1.lab.0lympu5.com"
  type    = "NS"
  ttl     = 3600
  comment = "olympus-${var.customer_name} netdb delegation"
}

resource "cloudflare_record" "ns_glue" {
  count = local.manage_cloudflare

  zone_id = var.cloudflare_zone_id
  name    = local.ns_label # "ns1.lab"
  content = aws_eip.netdb.public_ip
  type    = "A"
  ttl     = 60
  proxied = false # authoritative NS must be reachable directly, not via CF proxy
  comment = "olympus-${var.customer_name} netdb NS glue"
}
