# Terraform only provisions infrastructure + emits the Ansible inventory.
# Cluster/deploy knobs (k8s version, pod CIDR, NodePort, Olympus repo,
# router, certbot) live in Ansible group_vars; provider keys are passed to
# Ansible at runtime. The only secret here is the Cloudflare token (DNS).

# --- identity / region ---
variable "aws_region" {
  type        = string
  description = "AWS region to deploy the demo into."
  default     = "us-west-2" # Oregon
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
variable "control_plane_instance_type" {
  type        = string
  description = "EC2 type for the control-plane node."
  default     = "t3.medium" # 2 vCPU / 4 GiB
}

variable "worker_instance_type" {
  type        = string
  description = "EC2 type for the worker (builds the Olympus image — give it headroom)."
  default     = "t3.large" # 2 vCPU / 8 GiB
}

variable "root_volume_size" {
  type        = number
  description = "Root EBS volume size in GiB for each node."
  default     = 40
}

# --- network ---
variable "vpc_cidr" {
  type        = string
  description = "CIDR for the demo VPC."
  default     = "10.20.0.0/16"
}

variable "subnet_cidr" {
  type        = string
  description = "CIDR for the single public subnet."
  default     = "10.20.1.0/24"
}

variable "master_private_ip" {
  type        = string
  description = "Static private IP for the control-plane node (apiserver advertise address)."
  default     = "10.20.1.10"
}

variable "worker_private_ip" {
  type        = string
  description = "Static private IP for the worker node."
  default     = "10.20.1.11"
}

variable "ssh_ingress_cidr" {
  type        = string
  description = "CIDR allowed to reach SSH (22). Ansible runs over this."
  default     = "0.0.0.0/0"
}

variable "web_ingress_cidr" {
  type        = string
  description = "CIDR allowed to reach the TLS front (80/443)."
  default     = "0.0.0.0/0"
}

# --- DNS ---
# Set these to YOUR domain (via env.sh / TF_VAR_*). The placeholder default is
# example.com so a stray apply can't point at someone else's zone.
variable "dns_hostname" {
  type        = string
  description = "Hostname the demo is served at (DNS A-record + cert CN). Set to your own, e.g. olympus.example.com."
  default     = "olympus.example.com"
}

variable "cloudflare_api_token" {
  type        = string
  description = "Cloudflare API token (Zone:DNS:Edit). Via TF_VAR_cloudflare_api_token — NEVER commit. Blank disables DNS management."
  default     = ""
  sensitive   = true
}

variable "cloudflare_zone_id" {
  type        = string
  description = "Cloudflare zone id for YOUR domain (not secret; find it on the zone's Overview page). Required when managing DNS."
  default     = ""
}
