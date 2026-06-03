# One small Ubuntu box that runs the whole NetDB stack via docker-compose.
# Terraform only provisions + tags it + emits the Ansible inventory; the
# stack itself is brought up by inf/netdb/ansible/netdb.yml over SSH.
resource "aws_instance" "netdb" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.netdb.id]
  key_name               = aws_key_pair.netdb.key_name

  root_block_device {
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = { Name = "olympus-${var.customer_name}-netdb" }
}

# Standalone EIP so the address is known before provisioning (the Cloudflare
# glue + delegation need it) and STABLE across reboots — the whole point of
# the persistent server.
resource "aws_eip" "netdb" {
  domain = "vpc"
  tags   = { Name = "olympus-${var.customer_name}-netdb-eip" }
}

resource "aws_eip_association" "netdb" {
  allocation_id = aws_eip.netdb.id
  instance_id   = aws_instance.netdb.id
}
