>  [Italiano](fail2ban.md) |  **English**

# Fail2ban - Brute Force Protection

**Fail2ban** monitors system logs (e.g., `/var/log/auth.log`) looking for attack patterns (failed login attempts) and automatically bans offending IPs through firewall rules.

---

## How It Works Internally

1. **Filter**: a regex that identifies a failed attempt in the logs (e.g., `Failed password for .* from <HOST>`)
2. **Jail**: the policy - how many attempts (`maxretry`), within what time window (`findtime`), how long to ban (`bantime`)
3. **Action**: what to do when the threshold is exceeded - by default, adds a rule `iptables -A INPUT -s <IP> -j REJECT`

---

## Installation and Enabling

```bash
sudo apt install fail2ban -y
sudo systemctl enable --now fail2ban
```

---

## Checking the SSH Jail Status

```bash
sudo fail2ban-client status sshd
```

Expected output:

```
Status for the jail: sshd
|- Filter
|  |- Currently failed:	2
|  |- Total failed:	15
|  `- File list:	/var/log/auth.log
`- Actions
   |- Currently banned:	1
   |- Total banned:	3
   `- Banned IP list:	203.0.113.45
```

---

## Custom Configuration (optional)

To modify jail parameters without touching the default file (which gets overwritten by updates):

```bash
sudo nano /etc/fail2ban/jail.local
```

```ini
[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 5       # Ban after 5 failed attempts
findtime = 600     # 10-minute window
bantime = 3600     # Ban for 1 hour
```

> **Integration with Wazuh:** Fail2ban and Wazuh are not in conflict - they complement each other. Fail2ban acts (bans the IP), Wazuh observes and alerts (notifies you of the attack). Wazuh reads Fail2ban logs and generates alerts when an IP is banned, giving you centralized visibility.
