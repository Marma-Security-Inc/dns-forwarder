"""Settings validation and read-only SSH discovery."""
import ipaddress
import json
import os
from pathlib import Path
import re
import subprocess
import sys


def settings(path, env):
    p = Path(path)
    result = json.loads(p.read_text()) if p.exists() else {}
    if not isinstance(result, dict):
        raise ValueError("settings must be a JSON object")
    if env.get("ADMIN_CIDR"):
        result["admin_cidr"] = env["ADMIN_CIDR"]
    if env.get("DNS_CLIENT_CIDRS"):
        result["dns_client_cidrs"] = env["DNS_CLIENT_CIDRS"].split()
    if "dns_client_cidrs" not in result:
        result["dns_client_cidrs"] = ["0.0.0.0/0"]
    admin = result.get("admin_cidr")
    if admin is not None:
        net = ipaddress.ip_network(admin, strict=True)
        if net.version != 4 or net.prefixlen == 0:
            raise ValueError("admin_cidr must be a restricted IPv4 CIDR")
    clients = result["dns_client_cidrs"]
    if not isinstance(clients, list) or not clients:
        raise ValueError("dns_client_cidrs must be a nonempty list")
    for cidr in clients:
        if not isinstance(cidr, str) or ipaddress.ip_network(cidr, strict=True).version != 4:
            raise ValueError("DNS clients must be IPv4 CIDRs")
    return result


def port(value):
    number = int(value)
    if not 1 <= number <= 65535:
        raise ValueError("invalid SSH port")
    return number


def ssh_plan(config, listeners, socket_listeners="", connection=""):
    configured = {port(line.split()[1]) for line in config.splitlines()
                  if line.startswith("port ")}
    sockets = {port(p) for p in re.findall(r":(\d+)\s+\(Stream\)", socket_listeners)}
    active = set()
    for line in listeners.splitlines():
        fields = line.split()
        if len(fields) < 4:
            continue
        try:
            candidate = port(fields[3].rsplit(":", 1)[1])
        except (ValueError, IndexError):
            continue
        if '"sshd"' in line or ('"systemd"' in line and candidate in sockets):
            active.add(candidate)
    if not active:
        raise ValueError("cannot identify an active SSH listener; firewall unchanged")
    result = {"ports": sorted(active | configured)}
    if connection:
        peer, peer_port, local, local_port = connection.split()
        ipaddress.ip_address(peer)
        ipaddress.ip_address(local)
        port(peer_port)
        result.update(peer=peer, session_port=port(local_port))
        result["ports"] = sorted(set(result["ports"]) | {result["session_port"]})
    return result


def discover_ssh():
    config = subprocess.check_output(["sshd", "-T"], text=True)
    listeners = subprocess.check_output(["ss", "-H", "-lntp"], text=True)
    sockets = ""
    for unit in ("ssh.socket", "sshd.socket"):
        active = subprocess.run(["systemctl", "is-active", "--quiet", unit], check=False)
        if active.returncode == 0:
            sockets += subprocess.check_output(
                ["systemctl", "show", unit, "-p", "Listen", "--value"], text=True) + "\n"
    return ssh_plan(config, listeners, sockets, os.environ.get("SSH_CONNECTION", ""))


if __name__ == "__main__":
    try:
        if sys.argv[1] == "settings":
            Path(sys.argv[3]).write_text(json.dumps(settings(sys.argv[2], os.environ), indent=2) + "\n")
        elif sys.argv[1] == "ssh":
            print(json.dumps(discover_ssh()))
        else:
            raise ValueError("unknown command")
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        sys.exit(f"FAIL: {error}")
