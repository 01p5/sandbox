# ---------------------------------------------------------------------------
# Identity / region
# ---------------------------------------------------------------------------

variable "aws_region" {
  type        = string
  description = "AWS region to deploy the demo into."
  default     = "us-west-2" # Oregon
}

variable "customer_name" {
  type        = string
  description = "Short slug used to name + tag every resource (lowercase, no spaces)."
  default     = "sandbox"

  validation {
    condition     = can(regex("^[a-z0-9-]{1,24}$", var.customer_name))
    error_message = "customer_name must be 1-24 chars of [a-z0-9-]."
  }
}

# ---------------------------------------------------------------------------
# Instance shape
# ---------------------------------------------------------------------------

variable "control_plane_instance_type" {
  type        = string
  description = "EC2 type for the control-plane node (no image build runs here)."
  default     = "t3.medium" # 2 vCPU / 4 GiB
}

variable "worker_instance_type" {
  type        = string
  description = "EC2 type for the worker. It builds the Olympus image on first boot (multi-stage node+python), so give it headroom."
  default     = "t3.large" # 2 vCPU / 8 GiB
}

variable "root_volume_size" {
  type        = number
  description = "Root EBS volume size in GiB for each node."
  default     = 40
}

# ---------------------------------------------------------------------------
# Network
# ---------------------------------------------------------------------------

variable "vpc_cidr" {
  type        = string
  description = "CIDR for the demo VPC."
  default     = "10.20.0.0/16"
}

variable "subnet_cidr" {
  type        = string
  description = "CIDR for the single public subnet (both nodes live here)."
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
  description = "CIDR allowed to reach SSH (22). Default is wide open for demo convenience."
  default     = "0.0.0.0/0"
}

variable "web_ingress_cidr" {
  type        = string
  description = "CIDR allowed to reach the TLS front (80/443)."
  default     = "0.0.0.0/0"
}

# ---------------------------------------------------------------------------
# Kubernetes
# ---------------------------------------------------------------------------

variable "kubernetes_version" {
  type        = string
  description = "kubeadm/kubelet/kubectl minor version (pkgs.k8s.io channel), e.g. \"1.30\"."
  default     = "1.30"
}

variable "pod_cidr" {
  type        = string
  description = "Pod network CIDR for Calico (must not overlap the VPC)."
  default     = "192.168.0.0/16"
}

variable "dashboard_node_port" {
  type        = number
  description = "Fixed NodePort the dashboard service is pinned to (nginx proxies to it on localhost)."
  default     = 30093

  validation {
    condition     = var.dashboard_node_port >= 30000 && var.dashboard_node_port <= 32767
    error_message = "dashboard_node_port must be in the NodePort range 30000-32767."
  }
}

# ---------------------------------------------------------------------------
# Olympus source (built on the worker, chart pulled on the control-plane)
# ---------------------------------------------------------------------------

variable "olympus_repo_url" {
  type        = string
  description = "Public git URL of the Olympus repo the worker clones + builds."
  default     = "https://github.com/01p5/01p5.git"
}

variable "olympus_repo_ref" {
  type        = string
  description = "Branch/tag/commit of the Olympus repo to build."
  default     = "main"
}

variable "sandbox_repo_url" {
  type        = string
  description = "Public git URL of THIS sandbox repo (each node clones it for its bootstrap scripts + the webfront stack)."
  default     = "https://github.com/01p5/sandbox.git"
}

variable "sandbox_repo_ref" {
  type        = string
  description = "Branch/tag/commit of the sandbox repo to use for bootstrap."
  default     = "main"
}

variable "olympus_router" {
  type        = string
  description = "Orchestrator router mode: \"manual\" (no LLM key needed) or \"llm\"."
  default     = "manual"

  validation {
    condition     = contains(["manual", "llm"], var.olympus_router)
    error_message = "olympus_router must be \"manual\" or \"llm\"."
  }
}

# Provider keys are never committed; pass via TF_VAR_* / gitignored tfvars.
# They land in the control-plane user_data (IMDS-readable) — fine for a
# throwaway demo, never a production key.
variable "openai_api_key" {
  type        = string
  description = "Optional OpenAI API key, injected as a k8s Secret. Leave blank to omit."
  default     = ""
  sensitive   = true
}

variable "anthropic_api_key" {
  type        = string
  description = "Optional Anthropic API key, injected as a k8s Secret. Leave blank to omit."
  default     = ""
  sensitive   = true
}

# ---------------------------------------------------------------------------
# DNS + TLS
# ---------------------------------------------------------------------------

variable "dns_hostname" {
  type        = string
  description = "Hostname the demo is served at (DNS A-record + Let's Encrypt cert CN)."
  default     = "0lympu5.com"
}

variable "cloudflare_api_token" {
  type        = string
  description = "Cloudflare API token (Zone:DNS:Edit). Supply via TF_VAR_cloudflare_api_token — NEVER commit. Blank disables DNS management."
  default     = ""
  sensitive   = true
}

variable "cloudflare_zone_id" {
  type        = string
  description = "Cloudflare zone id for the domain (not secret)."
  default     = "63b9172374ab880f8fe2f2311f05dc6e" # 0lympu5.com
}

variable "certbot_email" {
  type        = string
  description = "Contact email Let's Encrypt registers for the cert."
  default     = "admin@01p5.com"
}

variable "certbot_staging" {
  type        = string
  description = "\"1\" to use Let's Encrypt staging (untrusted, no rate limits) while shaking things out; \"0\" for real certs."
  default     = "0"
}
