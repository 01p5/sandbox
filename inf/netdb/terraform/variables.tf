# --- identity / region ---
variable "aws_region" {
  type        = string
  description = "AWS region. Match the cluster's region so latency to /mcp is low."
  default     = "us-west-2"
}

variable "customer_name" {
  type        = string
  description = "Short slug used to name + tag every resource."
  default     = "sandbox"

  validation {
    condition     = can(regex("^[a-z0-9-]{1,24}$", var.customer_name))
    error_message = "customer_name must be 1-24 chars of [a-z0-9-]."
  }
}

# --- instance shape ---
variable "instance_type" {
  type        = string
  description = "EC2 type for the NetDB/DNS box. The stack is light (Go + Technitium + Kea)."
  default     = "t3.small" # 2 vCPU / 2 GiB
}

variable "root_volume_size" {
  type        = number
  description = "Root EBS (GiB) — holds the netdb SQLite, Technitium zones, Kea leases. Persistent."
  default     = 20
}

# --- network ---
# Own VPC, distinct CIDR from the cluster (10.30/10.20) so the two stacks
# never collide and this one is fully self-contained.
variable "vpc_cidr" {
  type        = string
  default     = "10.21.0.0/16"
  description = "CIDR for the NetDB VPC (distinct from the sandbox cluster's 10.20.0.0/16)."
}

variable "subnet_cidr" {
  type        = string
  default     = "10.21.1.0/24"
  description = "CIDR for the single public subnet."
}

variable "admin_cidr" {
  type        = string
  description = "CIDR allowed to reach SSH (22) + the Technitium console (5380). Lock this down to your IP in prod; Ansible runs over SSH from here."
  default     = "0.0.0.0/0"
}

variable "mcp_ingress_cidr" {
  type        = string
  description = "CIDR allowed to reach netdb's HTTP/MCP port (8080). Set to the Olympus cluster's public IP(s) so only it can drive the IPAM tools. Defaults open (netdb basic-auth is the backstop)."
  default     = "0.0.0.0/0"
}

# --- DNS / delegation ---
# Set these to YOUR domain. The parent zone must already exist in your
# Cloudflare account; this module only adds the NS + glue records that
# delegate <delegated_zone> to your Technitium server.
variable "delegated_zone" {
  type        = string
  description = "Zone Technitium becomes authoritative for (Cloudflare NS-delegates it here). e.g. lab.example.com."
  default     = "lab.example.com"
}

variable "ns_hostname" {
  type        = string
  description = "Authoritative NS hostname (SOA MNAME + the NS target + glue A). Conventionally ns1.<delegated_zone>."
  default     = "ns1.lab.example.com"
}

variable "cloudflare_zone_name" {
  type        = string
  description = "Name of the PARENT Cloudflare zone the records live in (e.g. example.com). Used to strip the suffix when building relative record names."
  default     = "example.com"
}

variable "cloudflare_api_token" {
  type        = string
  description = "Cloudflare API token (Zone:DNS:Edit on the parent zone). Via TF_VAR_cloudflare_api_token — NEVER commit. Blank disables the NS delegation (add it by hand)."
  default     = ""
  sensitive   = true
}

variable "cloudflare_zone_id" {
  type        = string
  description = "Cloudflare zone id of the PARENT zone where the NS + glue records live. Find it on the zone's Overview page."
  default     = ""
}
