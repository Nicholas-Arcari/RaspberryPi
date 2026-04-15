>  [Italiano](rules-best-practices.md) |  **English**

# Wazuh Rules Best Practices: Configuration for Our Lab

The default Wazuh configuration detects the most common threats, but for a home lab exposed to the Internet, specific tuning is needed. These are the recommended configurations for protecting against bots, malware, worms, and targeted attacks.

---

## 1. Active Response: Automatic IP Blocking

Active Response is the feature that transforms Wazuh from a "passive observer" into an "active defender." When an alert reaches a certain threshold, Wazuh automatically executes an action (typically: blocking the IP with iptables/UFW).

Add to `/var/ossec/etc/ossec.conf` on the Manager:

```xml
<ossec_config>
  <active-response>
    <!-- Block IP for 30 minutes after 5 failed SSH attempts -->
    <command>firewall-drop</command>
    <location>local</location>
    <rules_id>5712</rules_id>          <!-- sshd: Multiple auth failures -->
    <timeout>1800</timeout>             <!-- 30 minutes (in seconds) -->
  </active-response>

  <active-response>
    <!-- Block IP immediately after honeypot intrusion -->
    <command>firewall-drop</command>
    <location>local</location>
    <rules_id>100012</rules_id>         <!-- Cowrie: Login success -->
    <timeout>86400</timeout>            <!-- 24 hours -->
  </active-response>

  <active-response>
    <!-- Block IP after detected port scan -->
    <command>firewall-drop</command>
    <location>local</location>
    <rules_id>5710</rules_id>           <!-- Port scan detected -->
    <timeout>3600</timeout>             <!-- 1 hour -->
  </active-response>
</ossec_config>
```

The `firewall-drop` command executes `/var/ossec/active-response/bin/firewall-drop` which adds an iptables `DROP` rule for the IP. When the `timeout` expires, the rule is automatically removed.

**Verifying Active Response in action:**

```bash
# Show IPs currently blocked by Active Response
sudo /var/ossec/bin/agent_control -L

# Log of executed actions
sudo tail -f /var/ossec/logs/active-responses.log
```

> **Warning:** Do not enable Active Response on rule 100011 (honeypot login failed) - you would block bots before they reveal their techniques. The honeypot must remain accessible. Only block after a successful login (100012), when you have already collected the credentials used.

---

## 2. Vulnerability Detection: CVE Scanning of Installed Packages

Wazuh can compare the packages installed on the system against known vulnerability databases (NVD, Debian Security Tracker) and alert if a package has open CVEs.

Add to `ossec.conf` on the **agent**:

```xml
<wodle name="syscollector">
  <disabled>no</disabled>
  <interval>1h</interval>              <!-- Scan every hour -->
  <scan_on_start>yes</scan_on_start>
  <packages>yes</packages>             <!-- Collects list of installed packages -->
  <ports all="no">yes</ports>          <!-- Collects listening ports -->
  <processes>yes</processes>            <!-- Collects active processes -->
</wodle>
```

On the **Manager**, enable the vulnerability detector module:

```xml
<vulnerability-detector>
  <enabled>yes</enabled>
  <interval>5m</interval>
  <run_on_start>yes</run_on_start>

  <!-- Debian feed (our OS) -->
  <provider name="debian">
    <enabled>yes</enabled>
    <os>bookworm</os>
    <update_interval>1h</update_interval>
  </provider>

  <!-- NVD feed (National Vulnerability Database) -->
  <provider name="nvd">
    <enabled>yes</enabled>
    <update_interval>1h</update_interval>
  </provider>
</vulnerability-detector>
```

On the Dashboard, the **Vulnerability Detection** section will show CVEs for each agent, with CVSS severity, affected package, and version to install.

---

## 3. CDB Lists: IP Reputation and IOC (Indicators of Compromise)

**CDB lists** (Constant DataBase) allow enriching rules with external lists. The most common use: a list of known malicious IPs to generate alerts when they appear in logs.

```bash
# Download a list of known attack IPs (Abuse.ch)
sudo wget -O /var/ossec/etc/lists/abusech-ipblocklist \
  "https://feodotracker.abuse.ch/downloads/ipblocklist_recommended.txt"

# Convert to CDB format (key:value)
sudo awk '{print $1":"}' /var/ossec/etc/lists/abusech-ipblocklist \
  > /var/ossec/etc/lists/abusech-ipblocklist.cdb

# Compile the list
sudo /var/ossec/bin/wazuh-makelists
```

Add the list in `ossec.conf`:

```xml
<ruleset>
  <list>etc/lists/abusech-ipblocklist</list>
</ruleset>
```

Create a rule that uses the list in `/var/ossec/etc/rules/local_rules.xml`:

```xml
<!-- Alert when an IP from the blacklist appears in logs -->
<rule id="100020" level="12">
  <if_sid>5710,5712,100012</if_sid>
  <list field="srcip" lookup="address_match_key">etc/lists/abusech-ipblocklist</list>
  <description>Connessione da IP in blacklist Abuse.ch ($(srcip))</description>
  <mitre>
    <id>T1071</id>  <!-- Application Layer Protocol -->
  </mitre>
</rule>
```

> **Automation:** Create a cron job to update the list daily:
> ```bash
> echo "0 6 * * * root wget -qO /var/ossec/etc/lists/abusech-ipblocklist https://feodotracker.abuse.ch/downloads/ipblocklist_recommended.txt && /var/ossec/bin/wazuh-makelists" | sudo tee /etc/cron.d/wazuh-ioc-update
> ```

---

## 4. CIS Benchmark: Automated Hardening Verification

Wazuh can automatically verify system compliance with **CIS Benchmarks** (Center for Internet Security) - an industry standard for hardening.

Add to `ossec.conf` on the agent:

```xml
<wodle name="sca">
  <enabled>yes</enabled>
  <scan_on_start>yes</scan_on_start>
  <interval>12h</interval>

  <!-- CIS policy for Debian 12 (Bookworm) -->
  <policies>
    <policy>cis_debian12.yml</policy>
  </policies>
</wodle>
```

On the Dashboard, the **Security Configuration Assessment (SCA)** section will show:
- How many checks pass and how many fail
- For each failed check: what to fix and why (with CIS reference)
- Overall score (e.g., 78/100)

Example of a check that might fail in our setup:

| CIS Check | Status | Reason |
|---|---|---|
| "Ensure SSH MaxAuthTries is set to 4 or less" | FAIL | Our `sshd_config` does not specify it (default: 6) |
| "Ensure permissions on /etc/shadow are configured" | PASS | Correct permissions (640) |
| "Ensure ip forwarding is disabled" | FAIL | **Expected**: WireGuard requires `ip_forward=1` |

> "Expected" FAILs (like ip forwarding for WireGuard) should be documented as exceptions, not blindly fixed. A good analyst distinguishes between a real FAIL and a FAIL due to an architectural requirement.
