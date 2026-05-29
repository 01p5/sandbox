output "dashboard_url" {
  description = "Olympus dashboard over TLS (ready ~15-20 min after apply — worker builds the image, then certbot issues the cert)."
  value       = "https://${var.dns_hostname}/"
}

output "public_ip" {
  description = "Elastic IP of the control-plane node (DNS A-record points here)."
  value       = aws_eip.control_plane.public_ip
}

output "control_plane_ssh" {
  description = "SSH into the control-plane (key at ../deployment/k8s.pem)."
  value       = "ssh -i ${path.module}/../deployment/k8s.pem ubuntu@${aws_eip.control_plane.public_ip}"
}

output "worker_ssh" {
  description = "SSH into the worker (the node that builds the image)."
  value       = "ssh -i ${path.module}/../deployment/k8s.pem ubuntu@${aws_instance.worker.public_ip}"
}

output "bootstrap_log_hint" {
  description = "Watch first-boot progress on either node."
  value       = "ssh ... 'sudo tail -f /var/log/olympus-bootstrap.log'"
}

output "dns_record" {
  description = "Whether Terraform is managing the Cloudflare DNS record."
  value       = var.cloudflare_api_token != "" ? "${var.dns_hostname} A -> ${aws_eip.control_plane.public_ip} (DNS-only)" : "unmanaged — set TF_VAR_cloudflare_api_token or point DNS by hand"
}
