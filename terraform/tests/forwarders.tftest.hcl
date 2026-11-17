# Requires Terraform >= 1.7. Every AWS operation is mocked; no credentials or cloud resources.
mock_provider "aws" {}

variables {
  aws_region       = "us-east-1"
  instance_type    = "t4g.small"
  dns_client_cidrs = ["0.0.0.0/0"]
  ami_id           = "ami-00000000000000000"
  vpc_id           = "vpc-00000000000000000"
  key_name         = "test-only"
  ssh_public_key   = null
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
    availability_zone_id = "use1-az4"
  }
}

override_data {
  target = data.aws_subnet.selected["dns-2"]
  values = {
    vpc_id               = "vpc-00000000000000000"
    availability_zone_id = "use1-az6"
  }
}

run "redundant_pair" {
  # A mocked apply also verifies each EIP's attachment and output mapping.
  command = apply

  assert {
    condition     = length(aws_key_pair.dns) == 0 && alltrue([for instance in aws_instance.dns : instance.key_name == "test-only"])
    error_message = "Without a public key, both instances must use the existing regional key pair."
  }
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
      availability_zone_id = "use1-az4"
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
      availability_zone_id = "use1-az6"
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

run "import_public_key_for_both_forwarders" {
  command = apply
  variables {
    # Synthetic OpenSSH public-key fixture; no private counterpart is used.
    ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA test-only"
  }
  assert {
    condition     = length(aws_key_pair.dns) == 1 && aws_key_pair.dns[0].public_key == var.ssh_public_key
    error_message = "Only one public key must be imported into the destination region."
  }
  assert {
    condition     = alltrue([for instance in aws_instance.dns : instance.key_name == aws_key_pair.dns[0].key_name])
    error_message = "Both forwarders must use the newly imported regional key pair."
  }
}

run "reject_private_key_input" {
  command = plan
  variables {
    ssh_public_key = "-----BEGIN OPENSSH PRIVATE KEY-----"
  }
  expect_failures = [var.ssh_public_key]
}
