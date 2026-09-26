# Troubleshooting

Start on the instance:

```bash
sudo /opt/dns-forwarder/scripts/diagnose.sh
sudo /opt/dns-forwarder/scripts/health-check.sh
sudo cloud-init status --long
sudo tail -n 100 /var/log/dns-forwarder-setup.log
sudo tail -n 100 /var/log/cloud-init-output.log
```

1. `dig @127.0.0.1 darkside.cloud` and the same command with `+tcp`: success proves local recursive resolution works.
2. `dig @<PRIVATE_IP> darkside.cloud` and `+tcp`: success proves BIND is reachable at the instance interface address. A test originating on the same host is not proof of external firewall reachability.
3. From an external device: `dig @<PUBLIC_IP> darkside.cloud +time=3 +tries=1`, then add `+tcp`.
4. During the external query, capture on the instance: `sudo tcpdump -ni any port 53` (or `-ni ens5`; Ctrl-C ends capture). Restrict with `host <CLIENT_PUBLIC_IP> and port 53` to avoid confusing upstream traffic with client traffic.

If no incoming packet appears during a confirmed attempt, investigate SG, NACL, Internet Gateway/subnet routes, public IP mapping, and external-network filtering. Absence of traffic without a confirmed client test proves nothing. If requests arrive but replies do not, inspect UFW, BIND query/recursion ACLs, service logs and upstream reachability. If requests and replies appear, investigate return routing/NACL/client filtering; for TCP inspect the handshake and DNS payload, not only SYN packets.

Direct upstream checks (repeat with `+tcp`):

```bash
dig @103.247.36.36 darkside.cloud +time=4 +tries=1
dig @103.247.37.37 darkside.cloud +time=4 +tries=1
dig @8.8.8.8 darkside.cloud +time=4 +tries=1
```

## Actual debugging history

On this machine, localhost/private-IP queries worked while the Mac's public-IP query timed out. `named.service` was already active/enabled; `bind9` was its alias. UFW initially allowed only RFC1918 DNS clients, so it would block a public Mac source regardless of AWS rules. SSH listened on port 22 and was preserved. The original two upstreams returned `45.54.28.15` for `darkside.cloud`.

Google forwarders were then requested. They responded on UDP/TCP but returned `198.49.23.145`. After adding Mac public address `202.141.32.157/32` to UFW, the user supplied successful UDP and TCP results through `13.56.157.159`, both NOERROR with recursion available. There was no evidence requiring an AWS change for that client. An earlier capture with no confirmed query was not treated as proof of an AWS block.

The user subsequently explicitly opened AWS and UFW DNS to all IPv4 clients. Finally the upstream list became `103.247.36.36`, `103.247.37.37`, `8.8.8.8`. This repository records that current working BIND configuration, but intentionally uses restricted deployment client CIDRs. The latest baseline and health check show all three upstreams respond; BIND's current cached answer can be Google's address. Do not force a specific A record or assume the upstream list is strict ordered failover.

## Common failures

* Apt failures: check outbound rules, image repository availability, and subnet Internet route.
* `named-checkconf` failure: restore the options backup and inspect included files; do not disable `systemd-resolved` without a demonstrated port conflict.
* UFW rule check failure: verify settings JSON/client CIDRs and `ufw show added`. Existing broad rules are not removed on bootstrap reruns.
* Host checks pass but external tests fail: investigate the full network path above; health-check does not claim public reachability.
* Terraform completes but setup fails: inspect cloud-init logs. User-data changes recreate the instance; applying Terraform is not a health check.
