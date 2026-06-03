# Ansible inventory for the netdb play. Written to ../deployment (gitignored).
resource "local_file" "inventory" {
  filename        = "${path.module}/../deployment/inventory.ini"
  file_permission = "0644"
  content         = <<-EOT
    [netdb]
    netdb ansible_host=${aws_eip.netdb.public_ip}

    [netdb:vars]
    ansible_user=ubuntu
    ansible_ssh_private_key_file=${abspath("${path.module}/../deployment/netdb.pem")}
    ansible_python_interpreter=/usr/bin/python3
    netdb_public_ip=${aws_eip.netdb.public_ip}
    delegated_zone=${var.delegated_zone}
    ns_hostname=${var.ns_hostname}
  EOT

  depends_on = [aws_eip_association.netdb]
}
