#!/usr/bin/env bash
set -Eeuo pipefail
export LC_ALL=C
[[ $EUID == 0 ]] || { echo 'FAIL: run as root'; exit 1; }
source /etc/os-release
[[ $ID == ubuntu || $ID == debian ]] || { echo 'FAIL: Ubuntu/Debian required'; exit 1; }
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
exec > >(tee -a /var/log/dns-forwarder-setup.log) 2>&1
exec 9>/run/dns-forwarder-bootstrap.lock
flock -n 9 || { echo 'FAIL: bootstrap already running'; exit 1; }
backup=''; service=''; changed=0
failure() {
    rc=$?; trap - ERR
    echo "FAIL: line $1, exit $rc; backup=$backup"
    if (( changed )); then
        cp -a "$backup/installed-bind/named.conf.options" /etc/bind/named.conf.options
        named-checkconf && systemctl restart "$service" || true
    fi
    [[ -z $service ]] || journalctl -u "$service" -n 50 --no-pager || true
    exit "$rc"
}
trap 'failure "$LINENO"' ERR
# The configuration file is JSON data, never sourced as shell commands.
settings=${DNS_SETTINGS_FILE:-/etc/dns-forwarder/settings.json}
staged=$(mktemp /run/dns-forwarder-settings.XXXXXXXX)
trap 'rm -f "$staged"' EXIT
python3 - "$settings" "$staged" <<'PYSET'
import sys,os,json,pathlib,ipaddress
p=pathlib.Path(sys.argv[1]); s=json.loads(p.read_text()) if p.exists() else {}
for key,env in [('admin_cidr','ADMIN_CIDR'),('dns_client_cidrs','DNS_CLIENT_CIDRS')]:
    if os.environ.get(env): s[key]=os.environ[env].split() if key=='dns_client_cidrs' else os.environ[env]
assert s.get('admin_cidr') and s.get('dns_client_cidrs'), 'Set ADMIN_CIDR and DNS_CLIENT_CIDRS, or supply settings.json'
for cidr in [s['admin_cidr']]+s['dns_client_cidrs']:
    n=ipaddress.ip_network(cidr,strict=True)
    assert n.version==4, 'IPv4 CIDRs required'
    assert n.prefixlen>0 or (cidr in s['dns_client_cidrs'] and os.environ.get('ALLOW_PUBLIC_DNS')=='1'), 'Public DNS requires explicit ALLOW_PUBLIC_DNS=1; SSH must remain restricted'
assert ipaddress.ip_network(s['admin_cidr']).prefixlen>0, 'Restrict admin_cidr'
pathlib.Path(sys.argv[2]).write_text(json.dumps(s,indent=2)+'\n')
PYSET
admin=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["admin_cidr"])' "$staged")
mapfile -t clients < <(python3 -c 'import json,sys; print("\n".join(json.load(open(sys.argv[1]))["dns_client_cidrs"]))' "$staged")
backup=$(mktemp -d /var/backups/dns-forwarder.XXXXXXXX)
[[ ! -d /etc/bind ]] || cp -a /etc/bind "$backup/preinstall-bind"
[[ ! -d /etc/ufw ]] || cp -a /etc/ufw "$backup/ufw"
[[ ! -d /etc/dns-forwarder ]] || cp -a /etc/dns-forwarder "$backup/settings"
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y bind9 bind9-utils bind9-dnsutils dnsutils ufw tcpdump iproute2
cp -a /etc/bind "$backup/installed-bind"
named-checkconf
ufw status verbose
ufw status numbered
sshd -t
mapfile -t ports < <({ sshd -T | awk '$1=="port"{print $2}'; ss -H -lntp | awk '/"sshd"/{n=split($4,a,":"); print a[n]}'; } | sort -nu)
[[ ${#ports[@]} -gt 0 ]] || { echo 'FAIL: cannot determine SSH ports'; exit 1; }
# Preserve the active SSH session even if it uses a port different from sshd_config.
if [[ -n ${SSH_CONNECTION:-} ]]; then
    read -r peer _ _ session_port <<< "$SSH_CONNECTION"
    ufw allow from "$peer" to any port "$session_port" proto tcp
fi
for port in "${ports[@]}"; do ufw allow from "$admin" to any port "$port" proto tcp; done
for cidr in "${clients[@]}"; do
    for proto in udp tcp; do ufw allow from "$cidr" to any port 53 proto "$proto"; done
done
for server in 103.247.36.36 103.247.37.37 8.8.8.8; do
    for proto in udp tcp; do ufw allow out to "$server" port 53 proto "$proto"; done
done
# No reset/deletion: existing application and SSH allowances survive reruns.
ufw default deny incoming
ufw default allow outgoing
if ufw status | grep -q '^Status: active'; then ufw reload; else ufw --force enable; fi
for candidate in named.service bind9.service; do
    if systemctl cat "$candidate" >/dev/null 2>&1; then service=$(systemctl show "$candidate" -p Id --value); break; fi
done
[[ -n $service ]]
named-checkconf "$repo/config/named.conf.options"
changed=1
# Write through the existing file to preserve package ownership/mode.
cat "$repo/config/named.conf.options" > /etc/bind/named.conf.options
named-checkconf
systemctl enable "$service"
systemctl restart "$service"
systemctl is-active --quiet "$service"
changed=0
install -d -m 755 /etc/dns-forwarder
install -m 600 "$staged" /etc/dns-forwarder/settings.json
DNS_CLIENT_CIDRS="${clients[*]}" bash "$repo/scripts/health-check.sh"
printf 'PASS: bootstrap complete; backup=%s\n' "$backup"
