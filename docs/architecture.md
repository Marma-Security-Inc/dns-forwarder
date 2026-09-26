# Architecture

```text
Client
  | UDP/TCP 53
AWS Security Group
  |
EC2 private interface (public IPv4 is NAT-mapped by AWS)
  |
UFW
  |
BIND (named.service; bind9 alias on the baseline)
  +--> 103.247.36.36
  +--> 103.247.37.37
  +--> 8.8.8.8
```

AWS maps public IPv4 to the instance's private interface; `ss -lntup` therefore shows the private address, not necessarily the public one. No public-IP `listen-on` directive or host NAT rule is needed. BIND listens on localhost/private addresses over both transports.

The live snapshot is Ubuntu 26.04 ARM64, BIND 9.20.24, host `ip-172-31-23-149`, private `172.31.23.149`, public address used in client tests `13.56.157.159`. `named.service` is active/enabled; `bind9` resolves to the same unit. `systemd-resolved` also runs successfully on its stub addresses; it is not disabled. The generated options file is byte-identical to the live file and adds no extra directives.

The live server has broad public DNS and SSH rules, private-network allowances, and an obsolete outbound Google `8.8.4.4` rule. Fresh deployments deliberately restrict incoming DNS/SSH using configured CIDRs and add outbound rules only for the three current forwarders. Outbound defaults remain allow, matching the live host. This difference is required by the repository's safe access defaults, not a change to BIND behavior.

The three recursive upstreams do not agree on the test domain. Their listed order is preserved but is not a strict failover contract. Cache contents and upstream selection affect results; accepting a NOERROR A answer avoids incorrectly flagging one upstream's answer as broken. `dnssec-validation no` is retained from the requested/live setup; validation is not performed locally.
