# Persistent NetDB / DNS server for the Olympus demo.
#
# This is a SEPARATE terraform root (its own state) from the cluster in
# ../../terraform. It stands up one small EC2 box that runs the whole NetDB
# stack (netdb + Technitium DNS + Kea DHCP) via docker-compose, plus the
# Cloudflare NS delegation that makes Technitium authoritative for
# lab.0lympu5.com.
#
# WHY ITS OWN STATE: the cluster's `deploy.sh --fresh` runs `terraform
# destroy` against ../../terraform only. Keeping this box in a separate root
# means a full cluster teardown/rebuild never touches the DNS server — the
# authoritative zone + IPAM state survive redeploys, as required.

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
      Project   = "olympus-netdb"
      ManagedBy = "terraform"
      Customer  = var.customer_name
    }
  }
}

provider "cloudflare" {
  # Supplied via TF_VAR_cloudflare_api_token (never committed). The provider
  # validates the token charset even when no record is created, so fall back
  # to a placeholder when unset.
  api_token = var.cloudflare_api_token != "" ? var.cloudflare_api_token : "0000000000000000000000000000000000000000"
}
