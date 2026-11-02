# Requires Terraform >= 1.7. Every AWS operation is mocked; no credentials or cloud resources.
mock_provider "aws" {}

variables {
  aws_region       = "us-west-1"
  instance_type    = "t4g.small"
  dns_client_cidrs = ["0.0.0.0/0"]
  ami_id           = "ami-00000000000000000"
  vpc_id           = "vpc-00000000000000000"
  key_name         = "test-only"
  admin_cidr       = "203.0.113.10/32"
  forwarders = {
    dns-1 = { subnet_id = "subnet-00000000000000001" }
    dns-2 = { subnet_id = "subnet-00000000000000002" }
  }
}

override_data {
  target = data.aws_subnet.selected["dns-1"]
  values = {
    vpc_id               = "vpc-00000000000000000"
    availability_zone_id = "usw1-az1"
  }
}

override_data {
  target = data.aws_subnet.selected["dns-2"]
  values = {
    vpc_id               = "vpc-00000000000000000"
    availability_zone_id = "usw1-az2"
  }
}

run "redundant_pair" {
  # A mocked apply also verifies each EIP's attachment and output mapping.
  command = apply

  assert {
    condition     = length(aws_instance.dns) == 2 && length(aws_eip.dns) == 2
    error_message = "The deployment must contain two instances and two EIPs."
  }
  assert {
    condition     = alltrue([for name, eip in aws_eip.dns : eip.instance == aws_instance.dns[name].id && output.forwarders[name].public_ip == eip.public_ip])
    error_message = "Each forwarder must have its own associated EIP reported in outputs."
  }
  assert {
    condition     = length(toset([for forwarder in output.forwarders : forwarder.availability_zone_id])) == 2
    error_message = "Forwarders must occupy different Availability Zones."
  }
  assert {
    condition     = alltrue([for instance in aws_instance.dns : instance.instance_type == "t4g.small" && instance.user_data_base64 == local.user_data_base64])
    error_message = "Both forwarders must use t4g.small and identical user-data."
  }
  assert {
    condition     = aws_vpc_security_group_ingress_rule.dns_udp["0.0.0.0/0"].from_port == 53 && aws_vpc_security_group_ingress_rule.dns_tcp["0.0.0.0/0"].from_port == 53
    error_message = "Public DNS must be allowed over both UDP and TCP."
  }
}

run "reject_same_zone" {
  command = plan
  override_data {
    target = data.aws_subnet.selected["dns-2"]
    values = {
      vpc_id               = "vpc-00000000000000000"
      availability_zone_id = "usw1-az1"
    }
  }
  expect_failures = [aws_instance.dns]
}

run "reject_wrong_vpc" {
  command = plan
  override_data {
    target = data.aws_subnet.selected["dns-2"]
    values = {
      vpc_id               = "vpc-00000000000000099"
      availability_zone_id = "usw1-az2"
    }
  }
  expect_failures = [aws_instance.dns]
}

run "reject_single_forwarder" {
  command = plan
  variables {
    forwarders = {
      dns-1 = { subnet_id = "subnet-00000000000000001" }
    }
  }
  expect_failures = [var.forwarders]
}

run "reject_placeholder_subnet" {
  command = plan
  variables {
    forwarders = {
      dns-1 = { subnet_id = "subnet-00000000000000001" }
      dns-2 = { subnet_id = "subnet-REPLACE" }
    }
  }
  expect_failures = [var.forwarders]
}
