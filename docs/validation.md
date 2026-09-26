# Validation on the source server

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
