resource "aws_security_group" "dns" {
  name_prefix = "dns-forwarder-"
  description = "Restricted SSH and configurable recursive DNS clients"
  vpc_id      = var.vpc_id
}
resource "aws_vpc_security_group_ingress_rule" "ssh" {
  security_group_id = aws_security_group.dns.id
  cidr_ipv4         = var.admin_cidr
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
}
resource "aws_vpc_security_group_ingress_rule" "dns_udp" {
  for_each          = var.dns_client_cidrs
  security_group_id = aws_security_group.dns.id
  cidr_ipv4         = each.value
  ip_protocol       = "udp"
  from_port         = 53
  to_port           = 53
}
resource "aws_vpc_security_group_ingress_rule" "dns_tcp" {
  for_each          = var.dns_client_cidrs
  security_group_id = aws_security_group.dns.id
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = 53
  to_port           = 53
}
resource "aws_vpc_security_group_egress_rule" "outbound" {
  security_group_id = aws_security_group.dns.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}
