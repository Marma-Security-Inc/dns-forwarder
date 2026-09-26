# AWS deployment assumptions

Supply `aws_region`, `ami_id`, `instance_type`, `vpc_id`, `subnet_id`, `key_name`, `admin_cidr`, optional `dns_client_cidrs` (defaults to `["0.0.0.0/0"]`), optional `associate_elastic_ip`, and tags. Terraform reads the subnet and rejects a VPC mismatch. It does not create/import your VPC, subnet, key pair, Internet Gateway, route table, NACL, or current working server.

The subnet must be public, with `0.0.0.0/0` routed to an attached Internet Gateway. The instance gets a public IPv4 explicitly. A private-only subnet/NAT gateway cannot accept unsolicited Internet DNS queries. For private clients use reachable private addresses and matching CIDRs/routes.

| Direction | Protocol/port | Source/destination |
|---|---|---|
| Inbound | TCP 22 | `admin_cidr` |
| Inbound | UDP 53 | each `dns_client_cidrs` entry |
| Inbound | TCP 53 | each `dns_client_cidrs` entry |
| Outbound | All IPv4 | anywhere, for apt, DNS, and normal host traffic |

For restricted client access, use actual public client `/32` addresses, not laptop LAN IPs. Clients behind one NAT share its address. UDP and TCP are both required; DNS TCP is not just a diagnostic convenience. Security Groups are stateful: replies are allowed by connection tracking. UFW allows the same DNS CIDRs and preserves SSH.

Custom NACLs are stateless. Allow inbound client queries to 53, outbound replies to client ephemeral ports, outbound upstream queries to 53 and inbound replies to the instance's ephemeral ports. Package installation and SSH also require both directions. Check ordered deny rules and both client/server ephemeral port ranges; a default permissive NACL is simpler for this setup. Check routing and host/client filtering if captures show no requests.

Optional EIP stabilizes the public address across stop/start or instance replacement; allocation/association is managed by `aws_eip.dns`. Without it, the public address can change. Both ordinary public IPv4 and EIPs can incur charges. Record the outputs and review quotas and current regional costs before applying.

DNS access now defaults to `0.0.0.0/0` as explicitly authorized. With BIND recursion enabled this is a public recursive resolver, with DNS amplification/abuse and bandwidth-charge risks. Override `dns_client_cidrs` to restrict it. Both the Terraform Security Group and UFW receive the same DNS CIDRs.

Terraform continues to require a restricted `admin_cidr` for TCP/22. Manual bootstrap may omit `ADMIN_CIDR`; in that mode UFW allows detected SSH ports from anywhere and the provider firewall must restrict SSH sources. Explicit or saved admin CIDRs retain restricted UFW behavior. PEM keys authenticate users after network access is allowed; they do not override firewall rules. Bootstrap does not alter SSH authentication.

AWS credentials are used by Terraform on your deployment workstation. No access keys go in user-data or the repo; no instance IAM role is required for DNS forwarding. SG changes require AWS permissions; running root commands on EC2 alone does not grant them.
