>  [Italiano](troubleshooting.md) |  **English**

# Troubleshooting - Hardening: real problems and solutions

> Typical problems of the hardening measures (SSH, Fail2ban, UFW, sysctl, unattended-upgrades, Wazuh FIM): configurations that backfire, bans that do not trigger or that hit you, ineffective firewall rules, sysctls that do not persist. For the **emergency recovery** when hardening locks you out (console, lockout) see [Incident Recovery / lost access and boot](../../Incident%20Recovery%20%26%20Resilience/docs/accesso-perso-e-boot.en.md); to **prove** the defenses actually work see [Incident Recovery / verifying active defenses](../../Incident%20Recovery%20%26%20Resilience/docs/verifica-difese-attive.en.md).

---

## Problem 1: I locked myself out after SSH hardening

**Symptom:** after applying `sshd_config` (or changing port/keys), the new SSH connection is refused.

**Cause:** a syntax error in `sshd_config`, a wrong `AuthorizedKeysFile`, or password auth disabled before the key was loaded.

**Solution (prevention + fix):**

```bash
# BEFORE restarting sshd: validate the config and keep a SECOND SSH session open
sudo sshd -t            # no output = ok. Any line = an error with a line number
sudo systemctl restart ssh
```

If you are already locked out, get back in via the console (HDMI/keyboard) and fix it: the full procedure is in [Incident Recovery / lost access and boot, Part A/B](../../Incident%20Recovery%20%26%20Resilience/docs/accesso-perso-e-boot.en.md).

> **OMV trap:** OpenMediaVault **regenerates** `sshd_config` from its settings. If a manual edit disappears, apply it from **Services -> SSH** in the OMV web UI. See the detail in [hardening-ssh](hardening-ssh.en.md).

---

## Problem 2: Fail2ban does not ban IPs

**Symptom:** you see brute-force attempts in `auth.log`, but Fail2ban bans no one.

**Cause:** typically the `sshd` jail is not enabled, the `logpath` points to the wrong file, or the log-reading backend does not intercept the events (on systems with journald, `backend = systemd`).

**Solution:**

```bash
# Is the jail active and reading the right log?
sudo fail2ban-client status sshd
sudo fail2ban-client get sshd logpath

# Test the filter against the real log (how many lines does it match?)
sudo fail2ban-regex /var/log/auth.log /etc/fail2ban/filter.d/sshd.conf

# Config: make sure in /etc/fail2ban/jail.local that sshd is enabled and with the right backend
#   [sshd]
#   enabled = true
#   backend = systemd        # on Debian/Bookworm with journald
sudo systemctl restart fail2ban
```

---

## Problem 3: Fail2ban banned ME

**Symptom:** after a few mistyped keys/passwords, you can no longer connect from your IP.

**Cause:** your IP exceeded `maxretry` and Fail2ban banned it.

**Solution:**

```bash
# From the console or another IP: unblock your IP
sudo fail2ban-client set sshd unbanip 192.168.0.50
```

**Prevention:** add your LAN IP/subnet to `ignoreip` in `jail.local` (`ignoreip = 127.0.0.1/8 192.168.0.0/24`) so you can never auto-ban yourself from the home network.

---

## Problem 4: A UFW "deny" rule seems to have no effect

**Symptom:** you added a rule to block a port/IP, but the traffic still passes.

**Cause:** two frequent causes. (1) **Rule order:** UFW evaluates in order and the **first** match wins; an `allow` inserted before a more specific `deny` cancels it. (2) **Docker bypasses UFW:** the ports published by containers are not governed by UFW.

**Solution:**

```bash
# See the NUMBERED rules in evaluation order
sudo ufw status numbered
# Insert a rule in the right position (before the one that cancels it)
sudo ufw insert 1 deny from 203.0.113.10
# Delete by number if you need to reorder
sudo ufw delete <number>
```

> If the exposed port belongs to a Docker container, UFW is not enough: see [Docker / troubleshooting, Problem 6](../../Docker%20%26%20Portainer/docs/troubleshooting.en.md). The UFW -> iptables/netfilter mapping is explained in [firewall-ufw](firewall-ufw.en.md).

---

## Problem 5: The hardening sysctls do not survive a reboot

**Symptom:** after a reboot, `sysctl` shows values reverted to the defaults (e.g. `rp_filter=0`).

**Cause:** the file in `/etc/sysctl.d/` is not applied (file name, load order) or another file overrides it.

**Solution:**

```bash
# Check the effective value NOW
sudo sysctl net.ipv4.tcp_syncookies kernel.randomize_va_space net.ipv4.conf.all.rp_filter

# Reapply all the sysctl.d files and see which file sets what
sudo sysctl --system 2>&1 | grep -i "sysctl.d\|rp_filter"

# Make sure your file (e.g. /etc/sysctl.d/99-hardening.conf) exists and is loaded last
```

Detail of the parameters (SYN cookies, rp_filter, ASLR) in [kernel-hardening](kernel-hardening.en.md).

---

## Problem 6: Unattended-upgrades does not update (or breaks something)

**Symptom:** the automatic patches are not applied, or an automatic update caused a problem.

**Cause:** the service is not enabled, a package is on `hold`, or a reboot is needed to apply kernel updates.

**Solution:**

```bash
# Simulate a cycle to see what it would do
sudo unattended-upgrade --dry-run --debug | tail -30
# Log of the real runs
cat /var/log/unattended-upgrades/unattended-upgrades.log | tail -30
# A kernel update requires a reboot to take effect
[ -f /var/run/reboot-required ] && echo "REBOOT needed"
```

On a system with OMV, avoid automatic major-release upgrades that could misalign the OMV-managed packages (see [NAS / troubleshooting, Problem 8](../../NAS%20(Network%20Attached%20Storage)/docs/troubleshooting.en.md)).

---

## Problem 7: Wazuh FIM does not generate alerts on changes

**Symptom:** you modify a monitored file but no alert appears.

**Cause:** the directory is not in `<syscheck>`, FIM is in scheduled mode (not realtime) and the cycle has not passed yet, or the agent is disconnected.

**Solution:**

```bash
# Is the agent connected to the manager?
sudo /var/ossec/bin/agent_control -l

# Quick test on a monitored dir (e.g. /etc) and search for the syscheck alert
sudo touch /etc/test-fim-$(date +%s).conf
sudo tail -n 50 /var/ossec/logs/alerts/alerts.json | grep -i syscheck
sudo rm /etc/test-fim-*.conf
```

Verify in `ossec.conf` that the directory is monitored and, if realtime is needed, with `realtime="yes"`. The full procedure and the rule.ids are in [integrazione-wazuh](integrazione-wazuh.en.md) and in the active test [Incident Recovery / verifying defenses, sec.5](../../Incident%20Recovery%20%26%20Resilience/docs/verifica-difese-attive.en.md).

---

## Useful verification commands

```bash
# EFFECTIVE SSH config (not what you think you wrote)
sudo sshd -T | grep -Ei "permitrootlogin|passwordauthentication|pubkeyauthentication"

# Defense status in one shot
sudo ufw status verbose
sudo fail2ban-client status
sudo sysctl net.ipv4.tcp_syncookies kernel.randomize_va_space

# Wazuh alerts expected from this module:
#   SSH failed 5710/5712, Fail2ban ban 87101-87105, FIM 550-554, sudo 5401-5405
sudo tail -f /var/ossec/logs/alerts/alerts.json
```

---

## Links

- Emergency recovery from lockout (console, UFW, Fail2ban) -> [Incident Recovery / lost access and boot](../../Incident%20Recovery%20%26%20Resilience/docs/accesso-perso-e-boot.en.md)
- Actively proving the defenses work -> [Incident Recovery / verifying active defenses](../../Incident%20Recovery%20%26%20Resilience/docs/verifica-difese-attive.en.md)
- Docker bypasses UFW -> [Docker / troubleshooting](../../Docker%20%26%20Portainer/docs/troubleshooting.en.md)
- UFW/netfilter deep dive -> [firewall-ufw](firewall-ufw.en.md); kernel -> [kernel-hardening](kernel-hardening.en.md); SSH -> [hardening-ssh](hardening-ssh.en.md)
