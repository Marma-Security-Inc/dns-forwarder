# DNS Forwarding

This project provides public DNS forwarding through independently reachable servers.

## Language

**DNS forwarder**:
A DNS server that resolves client queries through configured upstream DNS servers.

**Redundant pair**:
Two independently reachable DNS forwarders that provide the same DNS behavior to the same clients. Clients can use the other forwarder when one is unavailable, subject to their retry behavior.
_Avoid_: Primary/secondary, active/passive

**Upstream DNS server**:
A resolver to which a forwarder sends its clients' DNS queries.
