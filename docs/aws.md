# AWS deployment assumptions

Supply `aws_region`, `ami_id`, `instance_type`, `vpc_id`, `forwarders` (exactly two named entries, each with `subnet_id`), `key_name`, optional `ssh_public_key`, `admin_cidr`, optional `dns_client_cidrs` (defaults to `["0.0.0.0/0"]`), and tags. Terraform reads both subnets and rejects a VPC mismatch or placement in the same Availability Zone. It does not create/import your VPC, subnets, Internet Gateway, route table, NACL, or current working servers. When `ssh_public_key` is supplied, it creates the named regional EC2 key pair through public-key import; otherwise `key_name` must already exist in the selected region. No private key is generated or managed.

Both subnets must be public, with `0.0.0.0/0` routed to an attached Internet Gateway. Each instance gets an initial public IPv4 explicitly so cloud-init can install packages before EIP association. A private-only subnet/NAT gateway cannot accept unsolicited Internet DNS queries. For private clients use reachable private addresses and matching CIDRs/routes.

| Direction | Protocol/port | Source/destination |
|---|---|---|
| Inbound | TCP 22 | `admin_cidr` |
| Inbound | UDP 53 | each `dns_client_cidrs` entry |
| Inbound | TCP 53 | each `dns_client_cidrs` entry |
| Outbound | All IPv4 | anywhere, for apt, DNS, and normal host traffic |

For restricted client access, use actual public client `/32` addresses, not laptop LAN IPs. Clients behind one NAT share its address. UDP and TCP are both required; DNS TCP is not just a diagnostic convenience. Security Groups are stateful: replies are allowed by connection tracking. UFW allows the same DNS CIDRs and preserves SSH.

Custom NACLs are stateless. Allow inbound client queries to 53, outbound replies to client ephemeral ports, outbound upstream queries to 53 and inbound replies to the instance's ephemeral ports. Package installation and SSH also require both directions. Check ordered deny rules and both client/server ephemeral port ranges; a default permissive NACL is simpler for this setup. Check routing and host/client filtering if captures show no requests.

Two new EIPs stabilize the public addresses across stop/start or instance replacement; allocation/association is managed by `aws_eip.dns`, keyed by forwarder name. Keep names stable to retain the EIPs. Outputs are grouped under `terraform output -json forwarders`. Both ordinary public IPv4 and EIPs can incur charges. Record the outputs and review quotas and current regional costs before applying.

DNS access now defaults to `0.0.0.0/0` as explicitly authorized. With BIND recursion enabled this is a public recursive resolver, with DNS amplification/abuse and bandwidth-charge risks. Override `dns_client_cidrs` to restrict it. Both the Terraform Security Group and UFW receive the same DNS CIDRs.

Terraform continues to require a restricted `admin_cidr` for TCP/22. Manual bootstrap may omit `ADMIN_CIDR`; in that mode UFW allows detected SSH ports from anywhere and the provider firewall must restrict SSH sources. Explicit or saved admin CIDRs retain restricted UFW behavior. PEM keys authenticate users after network access is allowed; they do not override firewall rules. Bootstrap does not alter SSH authentication.

AWS credentials are used by Terraform on your deployment workstation. No access keys go in user-data or the repo; no instance IAM role is required for DNS forwarding. SG changes require AWS permissions; running root commands on EC2 alone does not grant them.

Preparation now targets `us-east-1` to use available regional EIP headroom. Region-specific inputs and the planned SSH public-key import are recorded in [the deployment notes](two-forwarders.md). EC2 reports the EIP limit through `describe-account-attributes`; the broader vCPU quota still requires verification when Service Quotas access is available.
