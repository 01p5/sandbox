# Two nodes: a control-plane and a worker. Each boots a tiny user_data
# that clones THIS sandbox repo and runs its role script (which sources
# common.sh). Keeping the heavy scripts in the repo — not inline — sidesteps
# the 16 KB user_data limit and keeps the demo reproducible from the public
# repo.

# Fixed kubeadm bootstrap token (format: [a-z0-9]{6}.[a-z0-9]{16}).
resource "random_string" "token_id" {
  length  = 6
  upper   = false
  special = false
}

resource "random_string" "token_secret" {
  length  = 16
  upper   = false
  special = false
}

locals {
  join_token = "${random_string.token_id.result}.${random_string.token_secret.result}"

  # Shared knobs both roles get.
  common_vars = {
    sandbox_repo_url = var.sandbox_repo_url
    sandbox_repo_ref = var.sandbox_repo_ref
    olympus_repo_url = var.olympus_repo_url
    olympus_repo_ref = var.olympus_repo_ref
    master_ip        = var.master_private_ip
    join_token       = local.join_token
    pod_cidr         = var.pod_cidr
    k8s_version      = var.kubernetes_version
    node_port        = var.dashboard_node_port
    public_ip        = aws_eip.control_plane.public_ip
    dns_hostname     = var.dns_hostname
    certbot_email    = var.certbot_email
    certbot_staging  = var.certbot_staging
    olympus_router   = var.olympus_router
  }

  control_plane_user_data = templatefile("${path.module}/user_data.sh.tftpl", merge(local.common_vars, {
    role              = "control-plane"
    openai_api_key    = var.openai_api_key
    anthropic_api_key = var.anthropic_api_key
  }))

  # The worker never needs the provider keys — keep them out of its user_data.
  worker_user_data = templatefile("${path.module}/user_data.sh.tftpl", merge(local.common_vars, {
    role              = "worker"
    openai_api_key    = ""
    anthropic_api_key = ""
  }))
}

resource "aws_instance" "control_plane" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.control_plane_instance_type
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.node.id]
  key_name                    = aws_key_pair.node.key_name
  private_ip                  = var.master_private_ip
  user_data                   = local.control_plane_user_data
  user_data_replace_on_change = true

  root_block_device {
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = { Name = "olympus-${var.customer_name}-control-plane" }
}

resource "aws_instance" "worker" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.worker_instance_type
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.node.id]
  key_name                    = aws_key_pair.node.key_name
  private_ip                  = var.worker_private_ip
  user_data                   = local.worker_user_data
  user_data_replace_on_change = true

  root_block_device {
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = { Name = "olympus-${var.customer_name}-worker" }
}

# Allocate the EIP standalone (no instance ref) so its public_ip is known
# before the instance — the user_data + DNS record both need it, which
# would otherwise be a dependency cycle. Associate it separately.
resource "aws_eip" "control_plane" {
  domain = "vpc"
  tags   = { Name = "olympus-${var.customer_name}-eip" }
}

resource "aws_eip_association" "control_plane" {
  allocation_id = aws_eip.control_plane.id
  instance_id   = aws_instance.control_plane.id
}
