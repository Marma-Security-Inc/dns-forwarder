output "forwarders" {
  description = "Instance and stable public address details, keyed by forwarder name."
  value = {
    for name, instance in aws_instance.dns : name => {
      instance_id          = instance.id
      private_ip           = instance.private_ip
      public_ip            = aws_eip.dns[name].public_ip
      elastic_ip_id        = aws_eip.dns[name].id
      subnet_id            = instance.subnet_id
      availability_zone_id = data.aws_subnet.selected[name].availability_zone_id
    }
  }
}
output "security_group_id" {
  value = aws_security_group.dns.id
}
