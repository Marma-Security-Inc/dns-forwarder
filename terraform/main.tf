provider "aws" {
  region = var.aws_region
  default_tags {
    tags = merge({ Project = "dns-forwarder", ManagedBy = "Terraform" }, var.tags)
  }
}
data "aws_subnet" "selected" {
  id = var.subnet_id
}
locals {
  user_data = templatefile("${path.module}/../cloud-init/dns-forwarder.yaml", {
    bind_config = filebase64("${path.module}/../config/named.conf.options")
    helper      = filebase64("${path.module}/../scripts/forwarder_config.py")
    bootstrap   = filebase64("${path.module}/../scripts/bootstrap.sh")
    health      = filebase64("${path.module}/../scripts/health-check.sh")
    diagnose    = filebase64("${path.module}/../scripts/diagnose.sh")
    settings    = base64encode(jsonencode({ admin_cidr = var.admin_cidr, dns_client_cidrs = sort(tolist(var.dns_client_cidrs)) }))
  })
}
