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
