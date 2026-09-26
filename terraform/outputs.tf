output "instance_id" {
  value = aws_instance.dns.id
}
output "private_ip" {
  value = aws_instance.dns.private_ip
}
output "public_ip" {
  value = var.associate_elastic_ip ? aws_eip.dns[0].public_ip : aws_instance.dns.public_ip
}
output "elastic_ip" {
  value = var.associate_elastic_ip ? aws_eip.dns[0].public_ip : null
}
output "security_group_id" {
  value = aws_security_group.dns.id
}
