# DNS A-record for the demo hostname → control-plane EIP.
#
# proxied = false (DNS-only / grey-cloud) is REQUIRED: the webfront uses a
# Let's Encrypt HTTP-01 challenge and terminates TLS itself, so traffic
# must hit the origin directly rather than Cloudflare's proxy.
#
# Gated on the token so the stack still plans/applies without Cloudflare
# (you'd just point DNS by hand).
resource "cloudflare_record" "dashboard" {
  count = var.cloudflare_api_token != "" ? 1 : 0

  zone_id = var.cloudflare_zone_id
  name    = var.dns_hostname
  content = aws_eip.control_plane.public_ip
  type    = "A"
  ttl     = 60
  proxied = false

  comment = "olympus-${var.customer_name} demo"
}
