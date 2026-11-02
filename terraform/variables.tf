variable "aws_region" {
  type    = string
  default = "us-west-1"
}
variable "ami_id" {
  description = "Canonical Ubuntu 26.04 AMI in aws_region; match instance architecture. Pin a tested AMI."
  type        = string
}
variable "instance_type" {
  type    = string
  default = "t4g.small"
}
variable "vpc_id" {
  type = string
}
variable "forwarders" {
  description = "Exactly two named forwarders, each in an existing public subnet in a different Availability Zone. Names are stable Terraform resource keys."
  type = map(object({
    subnet_id = string
  }))
  validation {
    condition     = length(var.forwarders) == 2
    error_message = "Configure exactly two DNS forwarders."
  }
  validation {
    condition     = alltrue([for name, forwarder in var.forwarders : can(regex("^[a-z][a-z0-9-]*$", name)) && can(regex("^subnet-([0-9a-f]{8}|[0-9a-f]{17})$", forwarder.subnet_id))])
    error_message = "Use lowercase forwarder names and valid subnet IDs; replace all placeholder subnet values."
  }
}
variable "key_name" {
  type = string
}
variable "admin_cidr" {
  description = "Trusted SSH source IPv4 CIDR."
  type        = string
  validation {
    condition     = can(cidrnetmask(var.admin_cidr)) && !endswith(var.admin_cidr, "/0")
    error_message = "Use a restricted IPv4 CIDR for SSH."
  }
}
variable "dns_client_cidrs" {
  description = "IPv4 DNS clients; public recursion is the default. Override to restrict access."
  type        = set(string)
  default     = ["0.0.0.0/0"]
  validation {
    condition     = length(var.dns_client_cidrs) > 0 && alltrue([for c in var.dns_client_cidrs : can(cidrnetmask(c))])
    error_message = "Supply a nonempty set of IPv4 client CIDRs."
  }
}
variable "tags" {
  type    = map(string)
  default = {}
}
