terraform {
  required_providers { aws = { source = "hashicorp/aws", version = "~> 5.0" } }
}
provider "aws" { region = "us-west-2" }

resource "aws_security_group" "demo" {
  name_prefix = "olympus-demo-host-"
  vpc_id      = "vpc-0f203203db131039e"
  ingress {
    description     = "ssh from the cluster nodes"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = ["sg-099abd133be8353cb"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "olympus-demo-host" }
}

resource "aws_instance" "demo" {
  ami                    = "ami-0866907c81fbbd49e"
  instance_type          = "t3.micro"
  subnet_id              = "subnet-0360263bcdbc0dec3"
  key_name               = "olympus-sandbox-key"
  vpc_security_group_ids = [aws_security_group.demo.id]
  tags                   = { Name = "olympus-demo-host" }
}

locals {
  olympus_inventory_hosts = [{
    name     = "demo-host"
    address  = aws_instance.demo.private_ip
    ssh_user = "ubuntu"
    ssh_port = 22
    key      = "cluster"
    groups   = ["demo"]
    vars     = { role = "demo" }
  }]
}

output "olympus_inventory_hosts" {
  value = local.olympus_inventory_hosts
}
