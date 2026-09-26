# BIND DNS forwarder on Ubuntu EC2

Terraform + cloud-init reproduce the working server's BIND behavior. The byte-for-byte configuration in `config/named.conf.options` was copied from the live Ubuntu 26.04 ARM64 server running BIND 9.20.24. See [recorded baseline](docs/live-baseline.txt). No live BIND/firewall changes are required to create this repository.

Clients reach an EC2 IPv4 address over UDP/TCP 53; the Security Group and UFW control access; BIND forwards to `103.247.36.36`, `103.247.37.37`, and `8.8.8.8`, in that configured order. This is not guaranteed primary/secondary ordering: upstreams return different answers for `darkside.cloud`. Google returns `198.49.23.145`; the other two return `45.54.28.15`. Health checks intentionally accept either successful A response.

**New deployments default to public IPv4 DNS recursion** (`0.0.0.0/0` on UDP/TCP 53), as explicitly authorized. BIND retains `allow-query { any; };` and `allow-recursion { any; };`. A public resolver can be abused for reflection/amplification and incur bandwidth charges. Override DNS client CIDRs to restrict access when desired.

Manual bootstrap no longer requires `ADMIN_CIDR`. Without an explicit or persisted admin CIDR, it allows detected SSH ports through UFW from anywhere; **restrict SSH sources in your AWS Security Group or other provider firewall**. A PEM key authenticates SSH users; it does not replace firewall access controls. SSH authentication and keys are never changed. Terraform still requires a restricted `admin_cidr` for its Security Group and passes it to cloud-init.

## Prerequisites

* Terraform >=1.5,<2 and AWS credentials with permission to create EC2, SG rules, tags and optionally an Elastic IP.
* Existing VPC and public subnet with Internet Gateway route, suitable NACL, and an EC2 key pair in the chosen region.
* A pinned Canonical Ubuntu 26.04 ARM64 AMI for `t4g.small`, or an Ubuntu AMI and instance type with matching architecture. Obtain the current regional AMI from Canonical/AWS; verify its publisher. No AMI ID is invented here.
* Terraform requires your trusted SSH source IPv4 CIDR. Replace the sample admin address. DNS defaults to all IPv4 clients; restricted DNS CIDRs are optional.
* Ubuntu/Debian manual hosts need Bash, Python 3, systemd, OpenSSH, sudo/root, and apt repositories. Ubuntu cloud images include these.

Package versions follow the selected image's repositories; exact BIND 9.20.24 is recorded, not pinned to a package that may disappear. Pin an AMI/repository snapshot separately if binary-identical reproduction is required.

## Quick start

```bash
git clone <repo-url>
cd dns-forwarder/terraform
cp terraform.tfvars.example terraform.tfvars
vim terraform.tfvars
terraform init
terraform fmt -recursive
terraform validate
terraform plan -out=deploy.tfplan
terraform apply deploy.tfplan
PUBLIC_IP=$(terraform output -raw public_ip)
ssh -i /path/to/key.pem ubuntu@"$PUBLIC_IP" 'sudo cloud-init status --wait'
ssh -i /path/to/key.pem ubuntu@"$PUBLIC_IP" 'sudo /opt/dns-forwarder/scripts/health-check.sh'
dig @"$PUBLIC_IP" darkside.cloud
dig @"$PUBLIC_IP" darkside.cloud +tcp
```

`../scripts/health-check.sh` checks the machine where it runs; run it as root on the created instance, not your laptop. Terraform has no SSH provisioner. Cloud-init completion is separate from `terraform apply` success. Commit the generated `.terraform.lock.hcl` after reviewing provider selection; do not commit state, credentials, plans, or real tfvars.

## Terraform and cloud-init

Terraform creates one EC2 instance, one SG, one SSH rule, two DNS rules per client CIDR, one outbound IPv4 rule, and optionally one EIP associated with the instance. It uses the existing subnet/VPC/key pair. IMDSv2 is required and the root volume is encrypted. Public IPv4 is allocated initially even with EIP enabled so package installation can begin before association. Review AWS address charges.

`cloud-init/dns-forwarder.yaml` is a Terraform template, not standalone raw user-data. Terraform embeds repository files as base64, renders settings JSON, then gzip/base64 encodes the user-data. Cloud-init installs the files under `/opt/dns-forwarder` and runs bootstrap. Bootstrap updates apt, installs the seven required packages, backs up BIND, validates/restarts the detected service, preserves SSH, configures UFW, and checks health. It leaves `systemd-resolved` untouched. Logs: `/var/log/dns-forwarder-setup.log` and `/var/log/cloud-init-output.log`.

Changing embedded files or client settings changes user-data and **replaces the instance** on the next apply. Review the plan for downtime/IP changes. An optional EIP stays managed across replacement. SSH port 22 is the fresh-image Terraform assumption; manual bootstrap also detects configured/listening SSH ports.

## Manual bootstrap

On a fresh Ubuntu VPS, with provider firewall rules allowing DNS UDP/TCP 53 from `0.0.0.0/0` and SSH only from your trusted admin IP:

```bash
sudo apt-get update
sudo apt-get install -y git
git clone https://github.com/Marma-Security-Inc/dns-forwarder.git
cd dns-forwarder
sudo ./scripts/bootstrap.sh
sudo ./scripts/health-check.sh
sudo env TEST_DOMAIN=example.com ./scripts/health-check.sh
```

A private GitHub repository requires authentication when cloning. Test externally with `dig @VPS_PUBLIC_IP darkside.cloud` and `dig @VPS_PUBLIC_IP darkside.cloud +tcp`.

For optional host-level restrictions, replace these documentation addresses:

```bash
sudo env ADMIN_CIDR=203.0.113.10/32 \
  DNS_CLIENT_CIDRS='203.0.113.10/32 172.31.0.0/16' \
  ./scripts/bootstrap.sh
```

Bootstrap validates SSH configuration, discovers active sshd listeners (including systemd SSH socket activation), accounts for configured ports and `SSH_CONNECTION` when available, and adds allowances before enabling/reloading UFW. If active SSH listeners cannot be identified reliably, it fails before firewall changes. It does not blindly assume port 22. Existing SSH rules and authentication settings are preserved.

Settings persist in `/etc/dns-forwarder/settings.json`. Rerunning `sudo ./scripts/bootstrap.sh` uses them. Rules are additive and duplicates are skipped. Existing allowances (including broad ones) are preserved: shrinking the configured CIDR list does **not** revoke old UFW rules. Inspect `ufw status numbered` and remove obsolete rules intentionally. Cloud-init replacement gives new deployments a clean rule set. Bootstrap owns the options file but preserves other BIND files and makes backups; inspect custom host settings before adoption. Incoming default becomes deny; outgoing becomes allow. Other application ports must be explicitly permitted before enabling UFW on a multipurpose host.

No `ALLOW_PUBLIC_DNS` flag is required. Setting precedence is explicit nonempty environment variables, then saved settings, then defaults (public DNS, no admin CIDR). Saved restricted CIDRs are not replaced by the new defaults. To deliberately change saved DNS settings, pass `DNS_CLIENT_CIDRS=0.0.0.0/0`; to remove a saved admin CIDR, edit settings.json explicitly. Neither action removes existing UFW rules. Health checks use the same settings/defaults and never modify the firewall.

## Configuration and forwarder updates

Edit only `config/named.conf.options`, retaining the three required upstreams in their current order. If deliberately changing the upstream set in the future, also update bootstrap outbound rules and health-check endpoints. Apply via Terraform replacement, or copy the repo to an existing instance and run bootstrap. Configuration is validated before service restart; startup/configuration failure restores the pre-change options. A later health failure reports failure without automatically undoing firewall rules or successful service configuration.

No hard-coded private/public instance IP appears in deployment logic. The health check discovers the private source IP; `PRIVATE_IP` and `TEST_DOMAIN` can override it and the default domain.

## Health and rollback

```bash
sudo ./scripts/health-check.sh
sudo ./scripts/diagnose.sh
```

A host without settings JSON is checked against the public DNS default. Check it without writing anything:

```bash
sudo ./scripts/health-check.sh
```

Backups are retained under `/var/backups/dns-forwarder.*`. `preinstall-bind` records existing configuration before apt; `installed-bind` is the post-install, pre-replacement BIND tree (also available on fresh hosts). Restore the options file from a chosen backup:

```bash
sudo cp -a /var/backups/dns-forwarder.REPLACE/installed-bind/named.conf.options /etc/bind/named.conf.options
sudo named-checkconf
sudo systemctl restart named.service  # use bind9.service if that is the detected service
```

Firewall/settings snapshots are in the same backup when they existed. Review firewall differences and preserve SSH before restoring rules; there is no blind reset. To revert infrastructure, revert the Git configuration and review `terraform plan`; `terraform destroy` deliberately removes the managed instance/SG/EIP and is not a data rollback. Bootstrap backups on an instance disappear when it is destroyed; copy needed backups elsewhere first.

## Documentation

* [Architecture and live differences](docs/architecture.md)
* [AWS setup](docs/aws.md)
* [Troubleshooting and actual debugging history](docs/troubleshooting.md)
* [Validation report](docs/validation.md)

Implementation references: [AWS provider EC2 resource](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/instance) and [cloud-init module reference](https://cloudinit.readthedocs.io/en/latest/topics/modules.html).

## Publish to GitHub

After installing GitHub CLI on your workstation/server and authenticating, replace `YOUR_OWNER`:

```bash
gh auth login
gh repo create YOUR_OWNER/dns-forwarder --private --source=. --remote=origin --push
```

Or create an empty GitHub repository in the browser, then:

```bash
git remote add origin git@github.com:YOUR_OWNER/dns-forwarder.git
git push -u origin main
```

Inspect the baseline before publishing: it intentionally records the source server's IPs, hostname and firewall rules. No SSH private keys, AWS credentials or Terraform state belong in Git.
