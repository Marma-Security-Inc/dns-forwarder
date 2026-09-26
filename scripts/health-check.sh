#!/usr/bin/env bash
set -uo pipefail
export LC_ALL=C
[[ $EUID == 0 ]] || { echo 'FAIL: run with sudo (BIND keys and UFW require root)'; exit 1; }
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
fail=0
check() { if "$@"; then echo "PASS: $*"; else echo "FAIL: $*" >&2; fail=1; fi; }
service=''
for candidate in named.service bind9.service; do
    if systemctl cat "$candidate" >/dev/null 2>&1; then service=$candidate; break; fi
done
check named-checkconf
if [[ -n $service ]]; then
    check systemctl is-active --quiet "$service"
    check systemctl is-enabled --quiet "$service"
else echo 'FAIL: no BIND service'; fail=1; fi
for protocol in u t; do
    listeners=$(ss -H -lnp -"$protocol" 'sport = :53')
    if grep -q '"named"' <<< "$listeners"; then echo "PASS: BIND $protocol/53 listener";
    else echo "FAIL: BIND $protocol/53 listener"; fail=1; fi
done
private_ip=${PRIVATE_IP:-$(ip -4 route get 8.8.8.8 | awk '{for(i=1;i<=NF;i++)if($i=="src"){print $(i+1);exit}}')}
if [[ -z $private_ip ]]; then echo 'FAIL: no private IP'; fail=1; fi
for server in 127.0.0.1 ${private_ip:+"$private_ip"} 103.247.36.36 103.247.37.37; do
    for mode in +notcp +tcp; do
        if answer=$(dig @"$server" "${TEST_DOMAIN:-darkside.cloud}" A "$mode" +time=4 +tries=1 +noall +comments +answer) &&
           grep -q 'status: NOERROR' <<< "$answer" &&
           grep -Eq '[[:space:]]IN[[:space:]]+A[[:space:]]+[0-9.]+' <<< "$answer"; then
            echo "PASS: $server $mode $(awk '$4=="A"{print $5}' <<< "$answer" | paste -sd, -)"
        else echo "FAIL: $server $mode: $answer"; fail=1; fi
    done
done
check ufw status verbose
# Compare expected rules, not just whether ufw is installed or has a DNS listener.
check python3 - "$repo/scripts" <<'PYCHECK'
import os,subprocess,shlex,ipaddress,sys
sys.path.insert(0, sys.argv[1])
from forwarder_config import settings
status=subprocess.check_output(['ufw','status'],text=True)
assert 'Status: active' in status, 'UFW is inactive'
config = settings(os.environ.get('DNS_SETTINGS_FILE', '/etc/dns-forwarder/settings.json'), os.environ)
cidrs = config['dns_client_cidrs']
rules=[]
for line in subprocess.check_output(['ufw','show','added'],text=True).splitlines():
    words=shlex.split(line)
    if words[:2]==['ufw','allow']: rules.append(words)
def has_rule(cidr,proto,out=False):
    for w in rules:
        if ('out' in w)!=out: continue
        # ufw normalizes /0 into the shorthand "allow 53/udp".
        if not out and f'53/{proto}' in w and ipaddress.ip_network(cidr).prefixlen==0: return True
        if not all(x in w for x in ['to','port','proto']): continue
        source=w[w.index('from')+1] if 'from' in w else 'any'
        dest=w[w.index('to')+1]
        target=dest if out else source
        if w[w.index('port')+1]!='53' or w[w.index('proto')+1]!=proto: continue
        try:
            actual=ipaddress.ip_network('0.0.0.0/0' if target=='any' else target,strict=False)
            if actual==ipaddress.ip_network(cidr,strict=False): return True
        except ValueError: pass
    return False
for cidr in cidrs:
    for proto in ['udp','tcp']: assert has_rule(cidr,proto), f'Missing inbound {proto}/53 rule for {cidr}'
for ip in ['103.247.36.36','103.247.37.37']:
    for proto in ['udp','tcp']: assert has_rule(ip,proto,True), f'Missing outbound {proto}/53 rule for {ip}'
print('Expected DNS firewall rules present; rule precedence and AWS path require external testing.')
PYCHECK
if (( fail )); then echo 'FAIL: DNS forwarder health'; exit 1; fi
echo 'PASS: DNS forwarder host health (external reachability not tested)'
