# Two DNS forwarders

## Confirmed scope

- Create two new DNS forwarders, preserving any existing servers discovered during deployment preparation. The user is not aware of any existing servers.
- Both forwarders serve the same clients using the repository's current DNS configuration and upstreams.
- Both forwarders accept public IPv4 DNS queries over UDP and TCP.
- Each forwarder has its own Elastic IP address.
- Terraform allocates two new Elastic IPs rather than reusing existing allocations.
- Both forwarders use the configured `t4g.small` instance type.
- Place the forwarders in different Availability Zones within the configured region, `us-west-1`. Public subnets in `us-west-1a` and `us-west-1c` have been verified.
- Finish deployment by handing over two tested Elastic IPs. Client DNS changes are a separate step.

## Acceptance criteria

Each forwarder must independently pass all of the following before handoff:

- Cloud-init completes successfully.
- The repository's server health check passes on the instance.
- External DNS queries succeed over both UDP and TCP through its Elastic IP.

Client failover testing occurs separately when clients are configured.

## Implementation status

The user confirmed the design and authorized preparing and validating Terraform, with AWS deployment as a later step. Terraform now creates the named pair and two mandatory EIPs, rejects subnets outside the VPC or in the same Availability Zone, and reports both servers through the `forwarders` output.

The ignored local `terraform.tfvars` was migrated to the two-entry map. Its existing first subnet was retained; the second now uses the verified public subnet in `us-west-1c`. DNS client CIDRs were aligned with confirmed public access; the SSH admin CIDR and other existing settings were retained. Existing edits to the provider profile, provider lock file, and interactive guide were preserved.

Terraform initialization and validation succeeded. All five mocked Terraform tests passed. An AWS-backed plan was saved to the ignored `terraform/deploy.tfplan` and inspected: 9 creates, 0 updates, 0 deletions. No provisioning or live acceptance checks have run.

## Before deployment

1. Keep AWS SSO access current with `aws sso login --profile terraform-dev`; authentication is now verified.
2. Inspect existing instances and the active Terraform state. The local state inspected during preparation was empty. If another state manages an existing forwarder, use a separate deployment state or design a migration; do not apply destructive changes to existing servers or EIPs.
3. Verify both public subnets are in the selected VPC and different Availability Zones, with Internet Gateway routes, adequate free addresses, and suitable NACLs. Replace the second-subnet placeholder only with a verified ID. If no suitable subnet exists, settle that infrastructure change separately.
4. Verify the configured AMI publisher/architecture, regional key pair, restricted SSH source, and EC2/EIP quota availability.
5. Run `terraform plan -input=false -out=deploy.tfplan` from `terraform/`. Review for two new EC2 instances, two new EIPs, and no destruction of existing resources. Obtain deployment authorization before applying.
6. After deployment, perform every acceptance check above on both servers and hand over the resulting IPs.

## AWS verification and saved plan

- SSO authentication succeeded for the configured account/profile. Local Terraform state is still empty.
- Existing instances include several named as DNS forwarders, including two running servers in the first subnet and another in the second. Their names are discovery evidence, not proof of their current software configuration. None are imported, modified, or deleted by the plan.
- `dns-1`: `subnet-0a50f746420abc10f`, `us-west-1a` (`usw1-az1`), 4,085 available addresses at inspection.
- `dns-2`: `subnet-06fcfa6b8f308bab8`, `us-west-1c` (`usw1-az3`), 4,079 available addresses at inspection.
- Both use the main route table with an active default route to an attached Internet Gateway and a network ACL allowing all IPv4 ingress/egress.
- `t4g.small` is offered in both selected zones; actual capacity is not guaranteed by discovery or planning.
- Configured AMI `ami-048b768f3c049c97c` is available, ARM64, named `ubuntu/images/hvm-ssd-gp3/ubuntu-resolute-26.04-arm64-server-20261003`, owned by Canonical's `099720109477` account.
- Configured regional RSA key pair `dns_forwader_test_pem` exists. Local possession of its private key and reachability from the configured SSH admin CIDR still require confirmation before live acceptance checks.
- Plan includes two `aws_instance` creates, two `aws_eip` creates, one security group, three ingress rules, and one egress rule. No existing resources change.

## Deployment blocker: Elastic IP quota

EC2 `describe-account-attributes` reports `vpc-max-elastic-ips = 10`; `describe-addresses` lists 10 existing allocations in `us-west-1`. The two new EIPs require a regional limit of at least 12, assuming no other allocations are added. Preserve existing addresses as agreed.

The SSO role cannot call `servicequotas:GetServiceQuota`, so the Service Quotas view and Standard On-Demand vCPU quota were not verified. An authorized administrator must verify/request the EIP limit increase and confirm vCPU headroom before deployment. No quota request or permission change has been submitted. Re-plan after prerequisites are resolved and obtain authorization before applying; a successful plan does not reserve capacity or quota.
