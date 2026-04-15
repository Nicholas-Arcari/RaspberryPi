>  [Italiano](checklist-post-installazione.md) |  **English**

# Post-installation Checklist

After completing the setup of all components, run this verification to confirm everything is working correctly. Each check has a command and the expected result.

---

## Base Infrastructure

```bash
# [ ] System up to date
sudo apt update && apt list --upgradable
# Expected result: no packages to upgrade (or only a few non-security)

# [ ] Boot from NVMe (if configured)
lsblk | grep -E "nvme|mmcblk"
# Expected result: root partition (/) is on nvme0n1p2, not on mmcblk0

# [ ] EEPROM up to date
sudo rpi-eeprom-update
# Expected result: "BOOTLOADER: up to date"
```

---

## Security

```bash
# [ ] SSH accepts only public keys
ssh -o PasswordAuthentication=yes pi@localhost 2>&1 | grep -i "permission denied"
# Expected result: "Permission denied" (password rejected)

# [ ] UFW active with correct policies
sudo ufw status verbose | head -5
# Expected result: "Status: active", "Default: deny (incoming), allow (outgoing)"

# [ ] Fail2ban active on SSH jail
sudo fail2ban-client status sshd
# Expected result: "Filter" and "Actions" present, no errors

# [ ] Sysctl hardening applied
sysctl net.ipv4.tcp_syncookies kernel.randomize_va_space
# Expected result: tcp_syncookies = 1, randomize_va_space = 2
```

---

## Containers

```bash
# [ ] Docker active
docker version --format '{{.Server.Version}}'
# Expected result: Docker version (e.g., 20.10.x)

# [ ] All containers running
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
# Expected result: portainer, pihole, wireguard, cowrie all "Up"

# [ ] Portainer reachable
curl -sk https://localhost:9443 | head -1
# Expected result: Portainer page HTML (not "connection refused")

# [ ] Pi-hole responds to DNS queries
dig @192.168.0.250 google.com +short
# Expected result: an IP address (e.g., 142.250.x.x)

# [ ] Pi-hole blocks trackers
dig @192.168.0.250 ads.doubleclick.net +short
# Expected result: 0.0.0.0 (blocked)
```

---

## SIEM and Monitoring

```bash
# [ ] Wazuh Manager active
sudo systemctl is-active wazuh-manager
# Expected result: "active"

# [ ] Wazuh Indexer active and reachable
curl -sk https://localhost:9200 -u admin:admin | python3 -m json.tool | head -5
# Expected result: JSON with cluster name and OpenSearch version

# [ ] Wazuh Dashboard reachable
curl -sk https://localhost:443 | head -1
# Expected result: login page HTML

# [ ] Filebeat sending data to Indexer
sudo filebeat test output
# Expected result: "elasticsearch: https://127.0.0.1:9200... OK"

# [ ] Local agent connected
sudo /var/ossec/bin/agent_control -l
# Expected result: agent ID 000 or 001 with "Active" status
```

---

## Honeypot

```bash
# [ ] Cowrie accepts connections
ssh -o StrictHostKeyChecking=no root@localhost -p 2222
# Expected result: login prompt (accepts common passwords like "12345")
# Type "exit" to quit

# [ ] Cowrie logs are being generated
docker exec cowrie tail -1 /home/cowrie/cowrie-git/var/log/cowrie/cowrie.json
# Expected result: JSON line with the latest event
```

---

## VPN

```bash
# [ ] WireGuard listening
ss -ulnp | grep 51820
# Expected result: line with 0.0.0.0:51820 (LISTEN)

# [ ] Web UI reachable
curl -s http://localhost:51821 | head -1
# Expected result: wg-easy page HTML

# [ ] Tunnel working (from a connected client)
# On the VPN client: ping 192.168.0.102
# Expected result: response from the Pi
```

---

## VLAN (if configured)

```bash
# [ ] VLAN interface active
ip link show end0.150
# Expected result: UP state

# [ ] Docker IPVLAN network present
docker network inspect ipvlan_150 --format '{{.IPAM.Config}}'
# Expected result: [{192.168.150.0/24 192.168.150.1 map[]}]
```

> **Recommended frequency:** Run this checklist after every significant change (OS update, container addition, UFW rule modification) and at minimum once a month. You can automate it with the `scripts/setup.sh verify` script.
