# Generate an SSH keypair for the demo node and drop the private half
# under ../deployment/ (gitignored). Regenerated on every fresh apply;
# fine for a throwaway demo.
resource "tls_private_key" "node" {
  algorithm = "ED25519"
}

resource "aws_key_pair" "node" {
  key_name   = "olympus-${var.customer_name}-key"
  public_key = tls_private_key.node.public_key_openssh
}

resource "local_sensitive_file" "private_key" {
  content         = tls_private_key.node.private_key_openssh
  filename        = "${path.module}/../deployment/k8s.pem"
  file_permission = "0600"
}
