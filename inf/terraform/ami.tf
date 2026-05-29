# Latest Canonical Ubuntu 24.04 LTS (Noble) amd64 image in the target
# region. Using a data source (not a pinned AMI id) keeps the stack
# region-portable — no hardcoded, region-specific ami-xxxx.
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd*/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}
