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
python3 "$repo/scripts/forwarder_config.py" settings "$settings" "$staged"
admin=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("admin_cidr") or "")' "$staged")
clients=()
while IFS= read -r client; do clients+=("$client"); done < <(python3 -c 'import json,sys; print("\n".join(json.load(open(sys.argv[1]))["dns_client_cidrs"]))' "$staged")
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
# A direct assignment propagates discovery failures before any firewall mutation.
ssh_info=$(python3 "$repo/scripts/forwarder_config.py" ssh)
ports=()
while IFS= read -r port; do ports+=("$port"); done < <(python3 -c 'import json,sys; print("\n".join(map(str,json.loads(sys.argv[1])["ports"])))' "$ssh_info")
peer=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get("peer", ""))' "$ssh_info")
if [[ -n $peer ]]; then
    session_port=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["session_port"])' "$ssh_info")
    ufw allow from "$peer" to any port "$session_port" proto tcp
fi
for port in "${ports[@]}"; do
    if [[ -n $admin ]]; then
        ufw allow from "$admin" to any port "$port" proto tcp
    else
        # SSH source restrictions are delegated to the provider firewall.
        ufw allow "$port/tcp"
    fi
done
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
