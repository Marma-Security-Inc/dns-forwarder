# Validation on the source server

## us-east-1 live deployment (2026-11-02)

- PASS: user-approved Terraform apply reported 10 resources created, 0 changed, 0 destroyed. Local state contains both new instances and their EIPs.
- PASS: external UDP and TCP DNS queries to `54.80.104.29` and `184.192.128.142` returned `NOERROR` and an A answer for `darkside.cloud`.
- PASS (startup evidence): EC2 console logs on both instances contain a successful DNS forwarder host health result and cloud-init completion. Completion times: 11:28:06 UTC (dns-1), 11:28:09 UTC (dns-2), 2026-11-02. No separate SSH health rerun is claimed.
- Both instances are running. Last inspected EC2 system checks were OK on both, with the instance check OK on dns-2 and still initializing on dns-1.
- SSH limitation: the matching key was located, but TCP/22 times out from the workstation. Observed public source `120.138.12.74` differs from security group's permitted `202.141.35.119/32`. The configured host firewall uses the same admin CIDR. No firewall changes were made.


## us-east-1 preparation and SSH public-key import (2026-11-02)

- PASS: `terraform validate` and formatting checks.
- PASS: 7 mocked Terraform tests, adding coverage for a single public-key import shared by both forwarders, reuse of existing key pairs when import is omitted, and rejection of private-key input. Existing topology, EIP, and DNS checks remain covered.
- PASS: AWS-backed plan saved as ignored `terraform/deploy-us-east-1.tfplan`; programmatic inspection confirms the selected region, AMI, subnet IDs, shared imported key, 10 creates, 0 changes, and 0 deletions.
- PASS: `ImportKeyPair --dry-run` confirmed import permission without creating the key pair. Only public key material was read; no private key was accessed.
- PASS: EIP headroom observed at 2 allocated against a limit of 5. Selected subnets have different zones, Internet Gateway routing, and permissive IPv4 NACLs; ARM64 AMI ownership and regional t4g.small offerings verified.
- UNVERIFIED: Standard On-Demand vCPU quota, instance capacity at apply time, local possession of the private key, and current SSH source reachability.
- NOT RUN: Terraform apply or live acceptance checks. No AWS resources were created or modified.

## Two-forwarder preparation (2026-11-02, local workstation)

- PASS: Terraform initialization with the existing AWS provider lock file (`terraform init -backend=false -lockfile=readonly`).
- PASS: Terraform formatting and configuration validation, using Terraform 1.16.5 and AWS provider 6.67.0.
- PASS: five offline Terraform tests: two instances with matching EIP attachments/outputs, shared configuration and public UDP/TCP DNS; rejection of same-zone placement; rejection of a subnet in another VPC; rejection of a single forwarder; and rejection of placeholder subnet IDs.
- PASS: after SSO renewal, AWS-backed plan saved and inspected: 9 creates, 0 changes, 0 deletions. Selected public subnets are in different zones with an Internet Gateway route; AMI architecture and key pair existence verified.
- BLOCKED: two new EIPs require quota headroom; EC2 reports a limit of 10 and 10 allocations already exist. Service Quotas reads are denied for this profile; vCPU quota remains unverified.
- NOT RUN: provisioning, cloud-init completion, instance health checks, or external DNS acceptance tests. No AWS resources or quotas were changed.

Run `terraform -chdir=terraform test` with Terraform >= 1.7 for the mocked tests. All AWS operations in that test suite are mocked; a successful test does not establish AMI validity, subnet reachability, AWS quotas, or live service health. See [deployment status and prerequisites](two-forwarders.md).

## Original baseline (2026-09-24)

Validated 2026-09-24 on Ubuntu 26.04 ARM64.

| Check | Result |
|---|---|
| `bash -n scripts/bootstrap.sh` | PASS |
| `bash -n scripts/health-check.sh` | PASS |
| `bash -n scripts/diagnose.sh` | PASS |
| Live `named-checkconf` | PASS |
| Repository options `named-checkconf` | PASS |
| Live/repository options byte comparison | PASS, identical |
| Rendered cloud-init YAML and five decoded file payloads | PASS |
| `cloud-init schema -c /tmp/dns-forwarder-rendered.yaml` | PASS (unprivileged datasource warnings; schema valid) |
| Compressed representative user-data | 6,351 bytes, below EC2 16 KiB limit |
| Live health check, explicit existing public DNS CIDR | PASS, exit 0 |
| BIND active/enabled, UDP/TCP named listeners | PASS |
| Localhost/private-IP DNS, UDP and TCP | PASS |
| All three upstreams, UDP and TCP | PASS |
| UFW active and expected inbound/outbound rules | PASS |
| ShellCheck | SKIPPED: not installed |
| Terraform fmt/init/validate | SKIPPED: Terraform not installed |
| Fresh EC2 provisioning / bootstrap end-to-end | NOT RUN: no AWS resources deployed |

The cloud-init rendering test substituted representative settings and checked the YAML schema and decoded scripts against repository bytes. It did not execute Terraform template evaluation or validate the AWS provider schema. Run `terraform fmt -recursive`, `terraform init -backend=false`, and `terraform validate` on a Terraform-equipped machine before deployment. No large validation tools were installed. Bootstrap was syntax-checked, not executed against the working server; its fresh-host installation and rerun behavior still need deployment validation.

The current host predates settings.json, so the read-only health invocation was:

```bash
sudo env DNS_CLIENT_CIDRS=0.0.0.0/0 ./scripts/health-check.sh
```

This reflects the explicitly authorized live public rule; it is not a deployment default. Host health checks do not establish external reachability. The user's earlier Mac test established UDP/TCP access from that network; no new external client test was performed during repository creation.

Git had no configured author identity. The initial commit uses a repository-local automation identity (`DNS Forwarder Automation <dns-forwarder@localhost>`), not an inferred personal identity. No remote is configured or pushed.

## Public DNS and optional manual admin CIDR (2026-09-26)

* PASS: `python3 -m unittest discover -s tests -v` (12 isolated tests).
* PASS: all three `bash -n` checks.
* PASS: six embedded cloud-init payloads decoded and compared with repository files; rendered cloud-init schema valid. Representative gzip payload: 7,610 bytes.
* PASS: read-only SSH discovery on the live host identified port 22.
* PASS: updated live health check with no CIDR environment override; BIND and all UDP/TCP checks healthy.
* PASS: original BIND configuration and historical baseline remain unmodified.
* SKIPPED: Terraform fmt/init/validate and ShellCheck (not installed).
* NOT RUN: full bootstrap on a fresh VPS or Terraform deployment. No live service, firewall, SSH authentication, or AWS changes were made.

Tests cover missing/explicit/persisted settings, public DNS overrides, invalid settings, custom SSH ports, systemd socket activation, malformed session metadata, and executing the actual bootstrap SSH firewall section with mocked system tools. Missing SSH listeners and invalid sshd configuration result in zero UFW calls. No real firewall commands are executed by those tests.

Current defaults supersede the original report's restricted deployment defaults: DNS is public IPv4 when no client settings exist; manual admin CIDR is optional. Terraform still requires restricted SSH sources. The original baseline output is preserved as historical evidence.
