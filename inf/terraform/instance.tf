# Two blank Ubuntu nodes: a control-plane and a worker. Terraform only
# provisions + tags them and emits an Ansible inventory (see inventory.tf);
# all cluster bootstrap + the Olympus deploy is done by Ansible over SSH
# (inf/ansible). No user_data — the AWS key pair is enough to reach them.

resource "aws_instance" "control_plane" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.control_plane_instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.node.id]
  key_name               = aws_key_pair.node.key_name
  private_ip             = var.master_private_ip

  root_block_device {
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = { Name = "olympus-${var.customer_name}-control-plane" }
}

resource "aws_instance" "worker" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.worker_instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.node.id]
  key_name               = aws_key_pair.node.key_name
  private_ip             = var.worker_private_ip

  root_block_device {
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = { Name = "olympus-${var.customer_name}-worker" }
}

# Allocate the EIP standalone so its address is known before the instance
# (the DNS record needs it), then associate.
resource "aws_eip" "control_plane" {
  domain = "vpc"
  tags   = { Name = "olympus-${var.customer_name}-eip" }
}

resource "aws_eip_association" "control_plane" {
  allocation_id = aws_eip.control_plane.id
  instance_id   = aws_instance.control_plane.id
}
