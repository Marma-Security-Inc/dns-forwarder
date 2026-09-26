resource "aws_instance" "dns" {
  depends_on = [
    aws_vpc_security_group_ingress_rule.ssh,
    aws_vpc_security_group_ingress_rule.dns_udp,
    aws_vpc_security_group_ingress_rule.dns_tcp,
    aws_vpc_security_group_egress_rule.outbound,
  ]
  ami                         = var.ami_id
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  key_name                    = var.key_name
  vpc_security_group_ids      = [aws_security_group.dns.id]
  associate_public_ip_address = true
  user_data_base64            = base64gzip(local.user_data)
  user_data_replace_on_change = true
  metadata_options {
    http_tokens = "required"
  }
  root_block_device {
    encrypted   = true
    volume_type = "gp3"
    volume_size = 12
  }
  tags = { Name = "dns-forwarder" }
  lifecycle {
    precondition {
      condition     = data.aws_subnet.selected.vpc_id == var.vpc_id
      error_message = "subnet_id must belong to vpc_id."
    }
    precondition {
      condition     = length(base64gzip(local.user_data)) <= 21844
      error_message = "Compressed user-data exceeds EC2's 16 KiB limit."
    }
  }
}
resource "aws_eip" "dns" {
  count    = var.associate_elastic_ip ? 1 : 0
  domain   = "vpc"
  instance = aws_instance.dns.id
  tags     = { Name = "dns-forwarder" }
}
