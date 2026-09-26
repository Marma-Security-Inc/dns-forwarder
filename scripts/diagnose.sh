#!/usr/bin/env bash
set -uo pipefail
[[ $EUID == 0 ]] || { echo 'Run with sudo'; exit 1; }
date -u
named-checkconf || true
cat /etc/bind/named.conf.options
for service in named bind9; do
    systemctl status "$service" --no-pager || true
    journalctl -u "$service" -n 100 --no-pager || true
done
ss -lntup | grep ':53' || true
ufw status verbose
ufw status numbered
ip addr
ip route
hostname -I
dig @127.0.0.1 "${TEST_DOMAIN:-darkside.cloud}" +time=4 +tries=1 || true
cat <<'HELP'
Capture during a client query: sudo tcpdump -ni any port 53
Localhost works: BIND can resolve.
Private-IP works: BIND is reachable on the instance interface.
External public-IP failure: check UFW, SG, NACL, routes and client filtering.
No incoming packet during a confirmed query: investigate AWS/client path.
Request but no reply: investigate host firewall, BIND ACLs and upstream access.
Request and reply: investigate return path/client; TCP needs a completed handshake.
HELP
