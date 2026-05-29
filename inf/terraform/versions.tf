# Provider + version pins for the Olympus AWS demo.
#
# A *demonstration* environment: a 2-node kubeadm cluster (1 control-plane
# + 1 worker) on EC2, the Olympus dashboard deployed via its Helm chart,
# fronted by an nginx+certbot TLS reverse proxy with a real Let's Encrypt
# cert, and a Cloudflare DNS record pointing at it.
#
# The production path for Olympus is self-hosted (Proxmox / bare metal);
# this AWS path exists only to give reviewers a reachable URL.

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = "olympus-aws-demo"
      ManagedBy = "terraform"
      Customer  = var.customer_name
    }
  }
}

provider "cloudflare" {
  # Supplied via TF_VAR_cloudflare_api_token (never committed). The
  # provider validates the token's charset even when no record is
  # created, so fall back to a placeholder when it's unset.
  api_token = var.cloudflare_api_token != "" ? var.cloudflare_api_token : "0000000000000000000000000000000000000000"
}
