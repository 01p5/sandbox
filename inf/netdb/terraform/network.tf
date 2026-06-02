# Self-contained VPC + public subnet for the NetDB/DNS box.
data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "olympus-${var.customer_name}-netdb-vpc" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "olympus-${var.customer_name}-netdb-igw" }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true
  tags                    = { Name = "olympus-${var.customer_name}-netdb-public" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "olympus-${var.customer_name}-netdb-rt" }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "netdb" {
  name        = "olympus-${var.customer_name}-netdb"
  description = "Olympus NetDB / Technitium DNS server"
  vpc_id      = aws_vpc.main.id

  # Authoritative DNS — must be reachable by resolvers worldwide.
  ingress {
    description = "DNS (UDP)"
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "DNS (TCP) — zone transfers / large responses"
    from_port   = 53
    to_port     = 53
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # netdb HTTP UI + /mcp — Olympus reaches this. Lock to the cluster IP(s)
  # in prod; netdb basic-auth is the backstop when left open.
  ingress {
    description = "netdb HTTP + MCP"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [var.mcp_ingress_cidr]
  }

  # SSH (Ansible) + Technitium admin console — operator only.
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }
  ingress {
    description = "Technitium web console (HTTP/HTTPS)"
    from_port   = 5380
    to_port     = 5380
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }
  ingress {
    description = "Technitium web console (HTTPS)"
    from_port   = 53443
    to_port     = 53443
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  egress {
    description = "All outbound (apt, docker pulls, Cloudflare API, upstream DNS)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "olympus-${var.customer_name}-netdb-sg" }
}
