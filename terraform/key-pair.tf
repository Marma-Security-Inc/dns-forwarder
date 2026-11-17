# Only the public key is managed. No private key is generated or stored in state.
resource "aws_key_pair" "dns" {
  count      = var.ssh_public_key == null ? 0 : 1
  key_name   = var.key_name
  public_key = trimspace(var.ssh_public_key)
  tags       = { Name = var.key_name }
}
