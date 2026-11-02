resource "aws_instance" "dns" {
  for_each = var.forwarders
  depends_on = [
    aws_vpc_security_group_ingress_rule.ssh,
    aws_vpc_security_group_ingress_rule.dns_udp,
    aws_vpc_security_group_ingress_rule.dns_tcp,
    aws_vpc_security_group_egress_rule.outbound,
  ]
  ami                         = var.ami_id
  instance_type               = var.instance_type
  subnet_id                   = each.value.subnet_id
  key_name                    = var.key_name
  vpc_security_group_ids      = [aws_security_group.dns.id]
  associate_public_ip_address = true
  user_data_base64            = local.user_data_base64
  user_data_replace_on_change = true
  metadata_options {
    http_tokens = "required"
  }
  root_block_device {
    encrypted   = true
    volume_type = "gp3"
    volume_size = 12
  }
  tags = { Name = "dns-forwarder-${each.key}" }
  lifecycle {
    precondition {
      condition     = data.aws_subnet.selected[each.key].vpc_id == var.vpc_id
      error_message = "Each forwarder's subnet must belong to vpc_id."
    }
    precondition {
      condition     = length(toset([for subnet in data.aws_subnet.selected : subnet.availability_zone_id])) == 2
      error_message = "The two forwarders must use subnets in different Availability Zones."
    }
    precondition {
      condition     = length(local.user_data_base64) <= 21844
      error_message = "Compressed user-data exceeds EC2's 16 KiB limit."
    }
  }
}
resource "aws_eip" "dns" {
  for_each = var.forwarders
  domain   = "vpc"
  instance = aws_instance.dns[each.key].id
  tags     = { Name = "dns-forwarder-${each.key}" }
}
