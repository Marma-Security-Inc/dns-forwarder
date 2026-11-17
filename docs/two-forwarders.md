# Two DNS forwarders

## Confirmed scope

- Create two new DNS forwarders, preserving all existing servers and Elastic IPs.
- Both serve the same clients using the repository's current DNS configuration and upstreams.
- Accept public IPv4 DNS queries over UDP and TCP.
- Use two `t4g.small` instances in different Availability Zones.
- Allocate one new Elastic IP per forwarder.
- Prepare the deployment in **us-east-1 (N. Virginia)**, as approved after the us-west-1 EIP quota blocker was discovered.
- Reuse the `dns_forwader_test_pem` SSH key by importing only its public key into us-east-1 during a future Terraform apply. The private key is unchanged.
- Finish deployment by handing over two tested Elastic IPs. Client DNS changes and client failover testing are separate steps.

## Acceptance criteria

Each forwarder must independently pass all of the following before handoff:

- Cloud-init completes successfully.
- The repository's server health check passes on the instance.
- External DNS queries succeed over both UDP and TCP through its Elastic IP.
- Filtering acceptance: `darkside.cloud` must return the sinkhole response used by the working forwarder (`54.153.85.211`, observed answer `45.54.28.15`), rather than merely any successful A response.

## Current AWS preparation

The prior us-west-1 preparation was committed as `c05dab0` before beginning the region switch. After reviewing the us-east-1 plan, the user ran Terraform apply and approved creation. Terraform reported 10 resources added, 0 changed, and 0 destroyed.

- AWS profile: `terraform-dev`; SSO authentication succeeded.
- VPC: `vpc-08b5f9f38f7153a35` (existing default VPC in us-east-1).
- `dns-1`: `subnet-04c7744fe6aace06e`, `us-east-1a` (`use1-az4`).
- `dns-2`: `subnet-01b615b886b1596d7`, `us-east-1b` (`use1-az6`).
- Both existing subnets use main route table `rtb-0959c78e7324a7ca5`, with an active default route to attached Internet Gateway `igw-09f750602dba94903`. Their network ACL allows IPv4 ingress and egress. Each had over 4,000 available addresses at inspection.
- `t4g.small` is offered in both selected zones. Discovery and planning do not reserve capacity.
- Pinned AMI: `ami-01d67980b168ae293`, Canonical account `099720109477`, ARM64 Ubuntu 26.04 image dated `20261003`, matching the image version previously selected in us-west-1.
- EC2 reports a regional EIP limit of 5, with 2 already allocated. Two new allocations fit within the observed limit; headroom can change before apply.
- Existing us-east-1 key pairs do not match the configured west-region key. Its public key was read from EC2 and placed in the ignored local tfvars. An `ImportKeyPair` dry run confirmed import permission during preparation; the user subsequently created the regional key pair through Terraform apply.
- Local Terraform state now contains the two new instances, their EIPs, the imported key pair, and the shared security group/rules. Existing resources were not imported, changed, or deleted.

## Configuration and saved plans

The active ignored `terraform/terraform.tfvars` selects us-east-1 and supplies `ssh_public_key`. Terraform manages one `aws_key_pair` when this optional input is set; both instances depend on that regional key pair. Leave it null to use an existing regional key pair without managing it. Never provide private key material. A key-name collision must be resolved before apply rather than replacing an existing unmanaged key.

The west-region settings were retained in ignored `terraform/regions/us-west-1.tfvars`, and its old plan was renamed to `terraform/deploy-us-west-1.tfplan`. Those are historical snapshots; do not apply the old west-region plan. The selected region's AMI, VPC, subnets, and key configuration must always match.

The current ignored plan is **`terraform/deploy-us-east-1.tfplan`**. It was inspected for:

- 2 EC2 instance creates.
- 2 Elastic IP creates, one per instance.
- 1 regional SSH public-key import (`aws_key_pair`).
- 1 security group, 3 ingress rules, and 1 egress rule.
- **10 creates, 0 updates, 0 deletions.**

Terraform validation and all 7 mocked tests passed. The user applied the current configuration successfully. The saved pre-deployment plans are now historical snapshots; generate a fresh plan for future changes. The region-switch changes are separate from the prior commit.

## Live deployment and acceptance status

- `dns-1`: instance `i-0d28e0f7b0d029a34`, Elastic IP **54.80.104.29**, allocation `eipalloc-0ba0f5ba45ee418bd`.
- `dns-2`: instance `i-0eb7232aca4105c64`, Elastic IP **184.192.128.142**, allocation `eipalloc-09135273eff9e1590`.
- Shared security group: `sg-0389997db429cd6a6`.
- PASS: external `darkside.cloud` A queries over UDP and TCP through each EIP, all returning `NOERROR` with an A answer. Checked from the deployment workstation on 2026-11-02.
- Both instances were running. At the latest status inspection, system checks were OK for both; instance checks were OK for dns-2 and still initializing for dns-1. This is separate from the application health evidence below.
- PASS (startup evidence): EC2 console output for both instances records `PASS: DNS forwarder host health (external reachability not tested)` and cloud-init completion, at 11:28:06 UTC for dns-1 and 11:28:09 UTC for dns-2 on 2026-11-02. This verifies the health check executed by bootstrap; a separate SSH rerun was not possible.
- The matching SSH key was located in the local PEM folder with mode 0400. No private key contents were displayed or copied.
- SSH from the deployment workstation times out because the security group permits TCP/22 only from `202.141.35.119/32`, while the workstation's observed public egress is `120.138.12.74`. The same restricted admin CIDR was supplied to host UFW during bootstrap. No security group or host firewall rules were changed. Access requires the allowed network or a separately planned change to both firewall layers.
- Client configuration and client failover testing remain separate steps.

## Remaining handoff and future-change checks

1. Keep SSO authentication current. Verify the intended account, region, workspace, and state.
2. The matching private-key file has been located. Resolve SSH source reachability before administrative access: use the permitted network or plan an intentional update to both the security group and host UFW. The public-key import does not change the private key.
3. For future scale-out, recheck quota headroom. The SSO role was denied `servicequotas:GetServiceQuota` during preparation; the successful apply establishes that the current pair could be provisioned, but does not establish remaining vCPU or EIP headroom.
4. Regenerate and review the plan if settings, code, state, or AWS prerequisites change: `terraform -chdir=terraform plan -input=false -out=deploy-us-east-1.tfplan`. Require no changes or deletions to existing resources.
5. Obtain authorization for future infrastructure changes before applying. Review public IPv4 and instance charges; an increase in network distance from clients or upstream resolvers may affect DNS latency in the new region.
6. DNS acceptance checks passed: console logs show cloud-init completion and successful bootstrap host health on both instances; external UDP/TCP queries also passed for both EIPs. A separate SSH health rerun remains blocked by the source-IP restriction. Client rollout and failover testing remain separate.

## Historical us-west-1 preparation

The prior plan used VPC `vpc-097677e9334295204`, public subnets in `us-west-1a` and `us-west-1c`, and 9 creates with no changes or deletions. Its existing key pair required no new import. Discovery found several servers named as DNS forwarders outside the empty local state; all remain untouched.

EC2 reported an EIP limit of 10 with all 10 allocations in use in us-west-1. This led to the approved region change rather than reusing or releasing existing addresses. No quota or permission changes were submitted.

## Filtering discrepancy — unresolved

The user clarified that sinkhole behavior is required. Earlier successful A-response checks established reachability only and are insufficient for filtering acceptance.

The deployed user-data for dns-1 contains only `103.247.36.36` and `103.247.37.37` with `forward only`. DNSFilter's `myip.dnsfilter.com` diagnostic through each new forwarder returns its own EIP, demonstrating that queries reach DNSFilter under those new source addresses. The working forwarder returns its existing EIP in the same diagnostic.

At the latest check, the working forwarder returned `45.54.28.15` for `darkside.cloud`, while both new forwarders returned `198.49.23.145` with about 14,061 seconds of remaining TTL. Upstream Site/policy assignment for the new EIPs and cached unfiltered responses are the leading explanations; the DNSFilter account configuration has not been inspected. No connected DNSFilter tool is available.

Verify that both new EIPs belong to the intended DNSFilter Site and have the same filtering policy as the working server. After correcting policy, flush the specific BIND cache entry (`sudo rndc flushname darkside.cloud`) on both servers through an authorized administrative path, or allow the cached TTL to expire, then retest UDP and TCP. SSH from this workstation remains blocked by the configured source-IP restriction. Do not declare filtering handoff complete until the sinkhole check passes.

### Active policy diagnostic

Fresh `debug.dnsfilter.com TXT` responses at 11:47:39 UTC on 2026-11-02 reported `policy_source=ip_address` for all three forwarders, but different policy IDs:

- Working `54.153.85.211`: policy `1507036`, network `10674651`.
- New `54.80.104.29`: policy `1507317`, network `10681472`.
- New `184.192.128.142`: policy `1510130`, network `10681476`.

The user reported matching policies; these diagnostic responses establish different assigned policy objects. They do not establish whether the policy contents are equivalent. Compare their settings or assign the working policy `1507036` to both new Sites. The new forwarders still held an unfiltered answer with 13,583 seconds remaining TTL. Policy correction alone will not evict that BIND cache entry. DNSFilter dashboard access and SSH source access remain unavailable to the agent.
