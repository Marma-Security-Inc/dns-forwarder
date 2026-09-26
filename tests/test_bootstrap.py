"""Isolated settings and SSH/firewall tests; never invoke host administration tools."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
from forwarder_config import settings, ssh_plan


def listener(number, process='sshd'):
    return f'LISTEN 0 128 0.0.0.0:{number} 0.0.0.0:* users:(("{process}",pid=42,fd=3))\n'


class SettingsTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.path = Path(self.tmp.name) / 'settings.json'

    def test_fresh_public_without_admin(self):
        self.assertEqual(settings(self.path, {}), {'dns_client_cidrs': ['0.0.0.0/0']})

    def test_explicit_restrictions(self):
        result = settings(self.path, {'ADMIN_CIDR': '203.0.113.1/32', 'DNS_CLIENT_CIDRS': '192.0.2.0/24 198.51.100.1/32'})
        self.assertEqual(result['admin_cidr'], '203.0.113.1/32')
        self.assertEqual(len(result['dns_client_cidrs']), 2)

    def test_persisted_restrictions_and_override(self):
        saved = {'admin_cidr': '203.0.113.1/32', 'dns_client_cidrs': ['192.0.2.0/24']}
        self.path.write_text(json.dumps(saved))
        self.assertEqual(settings(self.path, {}), saved)
        result = settings(self.path, {'DNS_CLIENT_CIDRS': '0.0.0.0/0'})
        self.assertEqual(result['admin_cidr'], saved['admin_cidr'])
        self.assertEqual(result['dns_client_cidrs'], ['0.0.0.0/0'])

    def test_invalid_settings(self):
        for item in ({'admin_cidr': '0.0.0.0/0'}, {'admin_cidr': ''}, {'dns_client_cidrs': []}, {'dns_client_cidrs': ['::/0']}, {'dns_client_cidrs': '0.0.0.0/0'}):
            with self.subTest(item=item):
                self.path.write_text(json.dumps(item))
                with self.assertRaises(ValueError):
                    settings(self.path, {})


class DiscoveryTests(unittest.TestCase):
    def test_custom_listener_and_connection(self):
        plan = ssh_plan('port 2222\n', listener(2222), connection='203.0.113.1 55555 172.31.1.1 2222')
        self.assertEqual(plan['ports'], [2222])
        self.assertEqual(plan['peer'], '203.0.113.1')

    def test_socket_activation_and_configured_port(self):
        plan = ssh_plan('port 22\n', listener(2222, 'systemd'), '[::]:2222 (Stream)')
        self.assertEqual(plan['ports'], [22, 2222])

    def test_no_listener_or_unrelated_listener_fails(self):
        for sockets in ('', listener(22, 'nginx'), listener(22, 'systemd')):
            with self.assertRaises(ValueError):
                ssh_plan('port 22\n', sockets)

    def test_malformed_connection_fails(self):
        with self.assertRaises(ValueError):
            ssh_plan('port 2222\n', listener(2222), connection='bad session')


class FirewallOrderingTests(unittest.TestCase):
    def run_fragment(self, active=True, admin='', config_ok=True):
        with tempfile.TemporaryDirectory() as tmp:
            d = Path(tmp)
            (d/'sshd').write_text('#!/bin/sh\n' + ('exit 1\n' if not config_ok else '[ "$1" != -T ] || echo "port 2222"\nexit 0\n'))
            (d/'ss').write_text('#!/bin/sh\ncat "$FIXTURE"\n')
            (d/'systemctl').write_text('#!/bin/sh\nexit 1\n')
            (d/'ufw').write_text('#!/bin/sh\nprintf "%s\\n" "$*" >> "$CALLS"\n')
            for name in ('sshd', 'ss', 'systemctl', 'ufw'):
                (d/name).chmod(0o755)
            (d/'listeners').write_text(listener(2222) if active else '')
            script = (ROOT/'scripts/bootstrap.sh').read_text()
            fragment = script[script.index('sshd -t'):script.index('for cidr in')]
            env = dict(os.environ, PATH=f'{d}:'+os.environ['PATH'], repo=str(ROOT), admin=admin, FIXTURE=str(d/'listeners'), CALLS=str(d/'calls'), SSH_CONNECTION='')
            result = subprocess.run(['bash', '-euc', fragment], env=env, capture_output=True, text=True)
            calls = (d/'calls').read_text() if (d/'calls').exists() else ''
            return result, calls

    def test_optional_admin_opens_detected_port_only(self):
        result, calls = self.run_fragment()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(calls, 'allow 2222/tcp\n')

    def test_explicit_admin_remains_restricted(self):
        result, calls = self.run_fragment(admin='203.0.113.1/32')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(calls, 'allow from 203.0.113.1/32 to any port 2222 proto tcp\n')

    def test_no_listener_never_changes_firewall(self):
        result, calls = self.run_fragment(active=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(calls, '')

    def test_invalid_sshd_never_changes_firewall(self):
        result, calls = self.run_fragment(config_ok=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(calls, '')


if __name__ == '__main__':
    unittest.main()
