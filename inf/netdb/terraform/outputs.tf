output "netdb_public_ip" {
  description = "Elastic IP of the NetDB/DNS server. Stable across reboots; survives cluster redeploys. Set this as netdb_mcp_host in the cluster's group_vars."
  value       = aws_eip.netdb.public_ip
}

output "netdb_mcp_url" {
  description = "MCP endpoint Olympus wires into OLYMPUS_MCP_SERVERS."
  value       = "http://${aws_eip.netdb.public_ip}:8080/mcp"
}

output "technitium_console" {
  description = "Technitium admin console (operator-only via admin_cidr)."
  value       = "http://${aws_eip.netdb.public_ip}:5380/"
}

output "netdb_ssh" {
  description = "SSH into the NetDB box (key at ../deployment/netdb.pem)."
  value       = "ssh -i ${path.module}/../deployment/netdb.pem ubuntu@${aws_eip.netdb.public_ip}"
}

output "delegation_check" {
  description = "Verify the Cloudflare NS delegation once applied."
  value       = "dig NS ${var.delegated_zone} +short   # expect ${var.ns_hostname}"
}
