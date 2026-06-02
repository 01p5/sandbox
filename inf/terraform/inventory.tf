# Emit the Ansible inventory the deploy uses. Written to ../deployment
# (gitignored). ansible_host is the public IP; node_ip is the private IP
# kubeadm advertises/joins on; public_ip (control-plane) is what the TLS
# front waits for DNS to resolve to.
resource "local_file" "inventory" {
  filename        = "${path.module}/../deployment/inventory.ini"
  file_permission = "0644"
  content         = <<-EOT
    [control_plane]
    cp ansible_host=${aws_eip.control_plane.public_ip} node_ip=${var.master_private_ip} public_ip=${aws_eip.control_plane.public_ip}

    [workers]
    w1 ansible_host=${aws_instance.worker.public_ip} node_ip=${var.worker_private_ip}

    [all:vars]
    ansible_user=ubuntu
    ansible_ssh_private_key_file=${abspath("${path.module}/../deployment/k8s.pem")}
    ansible_python_interpreter=/usr/bin/python3
  EOT

  depends_on = [aws_eip_association.control_plane]
}

# Hosts to register into Olympus's RUNTIME inventory (the user-managed store the
# ansible / sysadmin agents target — distinct from the cluster inventory.ini
# above). The deploy seeds these via `olympus-inventory add-host` after apply
# (idempotent). Add entries here — or have the Programmer agent author them —
# referencing an SSH key already in the store BY NAME (e.g. "cluster"); never
# put key material in terraform. Do NOT list the cluster's own nodes:
# self-protection hard-blocks the agents from managing the hosts Olympus runs on.
locals {
  olympus_inventory_hosts = [
    # {
    #   name     = "web1"
    #   address  = aws_instance.web.public_ip
    #   ssh_user = "ubuntu"
    #   ssh_port = 22
    #   key      = "cluster"        # key NAME already in the store
    #   groups   = ["web"]
    #   vars     = { role = "frontend" }
    # },
  ]
}

output "olympus_inventory_hosts" {
  description = "Hosts the deploy seeds into the Olympus runtime inventory."
  value       = local.olympus_inventory_hosts
}

# Mirror to a file the ansible bootstrap reads (lookup on the controller), so
# seeding needs no terraform CLI at ansible time. Local-only resource.
resource "local_file" "inventory_hosts" {
  filename        = "${path.module}/../deployment/inventory_hosts.json"
  file_permission = "0644"
  content         = jsonencode(local.olympus_inventory_hosts)
}
