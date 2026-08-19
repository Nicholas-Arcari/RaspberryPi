>  [Italiano](wazuh-dashboard-recovery.md) |  **English**

# Runbook 03 - Wazuh dashboard inaccessible

> **When to use this runbook:** you open `https://192.168.0.102` (Wazuh Dashboard) and get a timeout, an SSL error, a page spinning forever, "Wazuh dashboard server is not ready yet", or a login that does not accept the credentials. This runbook takes you from the blank screen to the exact cause.

Key point to grasp immediately: in the lab, Wazuh runs **bare-metal** (not in Docker), as three distinct systemd services plus Filebeat. The dashboard is only the tip:

```
   Browser --HTTPS:443--> wazuh-dashboard --HTTPS:9200--> wazuh-indexer (OpenSearch)
                                                                ^
                              wazuh-manager --> Filebeat -------+  (ships the alerts)
```

**The dashboard almost never fails on its own:** in 90% of cases the fault is below it (indexer down, expired certificates, full disk). You diagnose from the bottom up.

---

## Step 0 - Snapshot of the stack

```bash
# Status of the four components in one shot
sudo systemctl status wazuh-indexer wazuh-manager wazuh-dashboard filebeat --no-pager | grep -E "●|Active:"

# Compact version
sudo systemctl is-active wazuh-indexer wazuh-manager wazuh-dashboard filebeat
# Expected: active active active active
```

Immediate interpretation:

| What is `inactive`/`failed` | Go to |
|---|---|
| Only `wazuh-dashboard` | Step 1 |
| `wazuh-indexer` (with or without the dashboard) | Step 2 (the most frequent cause) |
| All active but the page won't load / SSL error | Step 3 (certificates) or Step 4 (resources) |
| All active, page ok, but no data | Step 5 (Filebeat) |
| Login refused | Step 6 (credentials) |

---

## Step 1 - Only the dashboard is down

```bash
sudo journalctl -u wazuh-dashboard -b --no-pager | tail -40
sudo systemctl restart wazuh-dashboard

# Does the dashboard respond locally?
curl -sk -o /dev/null -w "%{http_code}\n" https://localhost:443
# Expected: 200 or 302. "000" = not responding -> read the logs above
```

Typical causes in the logs: `opensearch_dashboards.yml` with the wrong indexer host/port, or the dashboard starting **before** the indexer at boot (race condition). If it is a race, the manual restart fixes it; for the definitive cure see Prevention.

---

## Step 2 - The indexer won't start (the number one cause)

The dashboard without the indexer is a shop window without a warehouse. The indexer (OpenSearch on ARM64) is also the most fragile component on the Pi, for two reasons: **RAM** and **certificates**.

```bash
sudo systemctl status wazuh-indexer --no-pager
sudo journalctl -u wazuh-indexer -b --no-pager | tail -60
```

Read the logs looking for these patterns:

| Line in the log | Cause | Fix -> |
|---|---|---|
| `Native controller ... memory` / `OutOfMemoryError` / heap | Insufficient RAM / badly tuned heap | Step 4 |
| `failed to load ... certificate` / `PKIX path` / `certificate expired` | Expired TLS certificates or wrong permissions | Step 3 |
| `no space left on device` | Full disk | Step 4 + [Runbook 09](risorse-e-credenziali.en.md) |
| `bootstrap check failure` / `max virtual memory areas vm.max_map_count` | `vm.max_map_count` too low | Fix below |

```bash
# Classic bootstrap check fix (OpenSearch requires a high vm.max_map_count)
sudo sysctl -w vm.max_map_count=262144
echo 'vm.max_map_count=262144' | sudo tee /etc/sysctl.d/99-wazuh.conf
sudo systemctl restart wazuh-indexer

# Verify the indexer responds on its API
curl -sk -u admin:admin https://localhost:9200 | head
# Expected: JSON with "cluster_name" and version. Error -> still down
```

---

## Step 3 - Expired TLS certificates (the "time-based" fault)

Wazuh uses an internal PKI (certificates generated at install time) to encrypt indexer, manager, filebeat and dashboard. These certificates **have an expiry**: after months/years they can expire and then all the components refuse to talk to each other, with SSL errors. It is an insidious fault because it arrives "out of nowhere" without you having touched anything.

```bash
# Check the expiry of the indexer certificates
sudo openssl x509 -enddate -noout -in /etc/wazuh-indexer/certs/indexer.pem
sudo openssl x509 -enddate -noout -in /etc/wazuh-indexer/certs/root-ca.pem
# If "notAfter" is in the past -> expired certificates

# Typical dashboard/filebeat-side error when the certificates are expired:
#   "x509: certificate has expired or is not yet valid"
```

Regenerating the certificates (Wazuh procedure; adapt the paths to your own installation):

```bash
# Use the official certificate generation tool with the cluster config file
sudo /path/wazuh-certs-tool.sh -A            # regenerate the entire PKI
# Redistribute the .pem into the certs/ folders of indexer, manager, dashboard, filebeat
# Fix owner and permissions (frequent cause of "Permission denied"):
sudo chown wazuh-indexer:wazuh-indexer /etc/wazuh-indexer/certs/*
sudo chmod 400 /etc/wazuh-indexer/certs/*.pem
sudo systemctl restart wazuh-indexer wazuh-manager filebeat wazuh-dashboard
```

> **Permissions note (from the existing Wazuh troubleshooting):** each component runs as a dedicated user (`wazuh-indexer`, `wazuh-dashboard`...). If you copy the certificates as root, the service cannot read them and fails with "Permission denied". After every regeneration, fixing `chown`/`chmod` is mandatory.

---

## Step 4 - Exhausted resources: RAM, heap, disk

On the Pi 5 (8GB) the indexer + dashboard + manager compete for RAM. It is the reason the project requires 8GB and not 4. Two symptoms: the indexer is killed by the OOM killer, or the full disk stops indexing.

```bash
# RAM and swap: the indexer alone wants ~1-2GB of heap
free -h
# Who was killed by the OOM killer recently?
sudo dmesg -T | grep -i "killed process"
# Expected empty. "Killed process ... java" -> the indexer was oom-killed

# Disk space: OpenSearch goes read-only if the disk exceeds 95%
df -h /
# The indexer heap (default half the RAM; on a shared Pi it must be capped)
grep -E "Xms|Xmx" /etc/wazuh-indexer/jvm.options
# E.g. -Xms1g / -Xmx1g is reasonable on a Pi with other services
```

If the indexer went read-only because of a full disk, after freeing space ([Runbook 09](risorse-e-credenziali.en.md)) unblock the indices:

```bash
curl -sk -u admin:admin -X PUT "https://localhost:9200/_all/_settings" \
  -H 'Content-Type: application/json' \
  -d '{"index.blocks.read_only_allow_delete": null}'
```

---

## Step 5 - Everything up, but no data (Filebeat)

The dashboard loads but the panels are empty: the alerts do not arrive from the manager to the indexer. It is exactly the "No template found" case from the Wazuh troubleshooting.

```bash
# Can Filebeat talk to the indexer?
sudo filebeat test output
# Expected: "elasticsearch: https://127.0.0.1:9200 ... OK"

# Are the template and indices in place?
curl -sk -u admin:admin "https://localhost:9200/_cat/indices/wazuh-alerts-*?v"
# Expected: rows of wazuh-alerts-* indices. Empty -> wrong template/ILM:
sudo filebeat setup --index-management
```

---

## Step 6 - Login refused (credentials)

You get there, the login page loads, but `admin`/password won't get in. Reset with the official tool:

```bash
# Reset the indexer/dashboard admin password
sudo /usr/share/wazuh-indexer/bin/indexer-security-init.sh
# or (recent versions) the Wazuh password tool:
sudo /var/ossec/bin/wazuh-passwords-tool.sh -u admin -p 'NewStrongPassword'
```

> **Recovery prerequisite:** the admin password and the indexer security keys must go into your offline password manager **before** you need them. If they are only in your head or only on the Pi, a cold reset is much more painful.

---

## Recovery verification

```bash
sudo systemctl is-active wazuh-indexer wazuh-manager wazuh-dashboard filebeat   # 4x active
curl -sk -o /dev/null -w "dashboard=%{http_code}\n" https://localhost:443       # 200/302
curl -sk -u admin:admin https://localhost:9200/_cluster/health | grep -o '"status":"[a-z]*"'
# Expected: "status":"green" (or at least "yellow" on a single node)
```

Then open the dashboard from the browser and confirm recent alerts are arriving.

---

## Prevention

- **Start order:** make `wazuh-dashboard` depend on the indexer (`After=wazuh-indexer.service` via a drop-in) to kill the boot race condition.
- **Certificates:** note the PKI expiry date and set a reminder at -1 month. An expired certificate is the easiest fault to prevent and the most frustrating to suffer blind.
- **Resources:** cap the indexer heap in `jvm.options`, put a ceiling on the logs ([Runbook 09](risorse-e-credenziali.en.md)), and have Wazuh itself monitor the disk space (yes, it can alert on its own full disk while it is still alive).
- **Backup:** include `/etc/wazuh-*`, `/var/ossec/etc/` and the custom rules in [Runbook 08](backup-e-disaster-recovery.en.md). Recreating the rules by hand is an RPO you do not want.

---

## Links

- Full disk / OOM as the root cause -> [Runbook 09: resources and credentials](risorse-e-credenziali.en.md)
- Install-time Wazuh troubleshooting (original documented errors) -> [SOC Analyst / Wazuh / troubleshooting](../../SOC%20Analyst/Wazuh/docs/troubleshooting.en.md)
- Wazuh PKI and TLS in detail -> [SOC Analyst / Wazuh / tls-pki](../../SOC%20Analyst/Wazuh/docs/tls-pki.en.md)
- Filebeat and the log pipeline -> [SOC Analyst / Wazuh / filebeat](../../SOC%20Analyst/Wazuh/docs/filebeat.en.md)
