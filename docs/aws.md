# AWS deployment assumptions

Supply `aws_region`, `ami_id`, `instance_type`, `vpc_id`, `subnet_id`, `key_name`, `admin_cidr`, `dns_client_cidrs`, optional `associate_elastic_ip`, and tags. Terraform reads the subnet and rejects a VPC mismatch. It does not create/import your VPC, subnet, key pair, Internet Gateway, route table, NACL, or current working server.

The subnet must be public, with `0.0.0.0/0` routed to an attached Internet Gateway. The instance gets a public IPv4 explicitly. A private-only subnet/NAT gateway cannot accept unsolicited Internet DNS queries. For private clients use reachable private addresses and matching CIDRs/routes.

| Direction | Protocol/port | Source/destination |
|---|---|---|
| Inbound | TCP 22 | `admin_cidr` |
| Inbound | UDP 53 | each `dns_client_cidrs` entry |
| Inbound | TCP 53 | each `dns_client_cidrs` entry |
| Outbound | All IPv4 | anywhere, for apt, DNS, and normal host traffic |

Use actual public client `/32` addresses, not laptop LAN IPs. Clients behind one NAT share its address. UDP and TCP are both required; DNS TCP is not just a diagnostic convenience. Security Groups are stateful: replies are allowed by connection tracking. UFW allows the same DNS CIDRs and preserves SSH.

Custom NACLs are stateless. Allow inbound client queries to 53, outbound replies to client ephemeral ports, outbound upstream queries to 53 and inbound replies to the instance's ephemeral ports. Package installation and SSH also require both directions. Check ordered deny rules and both client/server ephemeral port ranges; a default permissive NACL is simpler for this setup. Check routing and host/client filtering if captures show no requests.

Optional EIP stabilizes the public address across stop/start or instance replacement; allocation/association is managed by `aws_eip.dns`. Without it, the public address can change. Both ordinary public IPv4 and EIPs can incur charges. Record the outputs and review quotas and current regional costs before applying.

Do not normally allow DNS from `0.0.0.0/0`: the retained BIND ACL permits recursive queries, creating an open resolver when perimeter rules allow everyone. Terraform rejects public DNS CIDRs. If deliberately changing that policy, review both Terraform validation and bootstrap's explicit `ALLOW_PUBLIC_DNS` gate, and implement appropriate operational abuse controls. The existing server's public configuration is documented, not used as the default.

AWS credentials are used by Terraform on your deployment workstation. No access keys go in user-data or the repo; no instance IAM role is required for DNS forwarding. SG changes require AWS permissions; running root commands on EC2 alone does not grant them.
