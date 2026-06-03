# Dedicated keypair for the NetDB box. Private half lands under
# ../deployment (gitignored) for the netdb Ansible play to use. Separate
# from the cluster's key so the two roots stay independent.
resource "tls_private_key" "netdb" {
  algorithm = "ED25519"
}

resource "aws_key_pair" "netdb" {
  key_name   = "olympus-${var.customer_name}-netdb-key"
  public_key = tls_private_key.netdb.public_key_openssh
}

resource "local_sensitive_file" "private_key" {
  content         = tls_private_key.netdb.private_key_openssh
  filename        = "${path.module}/../deployment/netdb.pem"
  file_permission = "0600"
}
