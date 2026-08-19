>  [Italiano](troubleshooting.md) |  **English**

# Troubleshooting - SOC operations: real problems and solutions

> Problems from the **analyst's** point of view, not the administrator's: a log source that goes silent, too many false positives, a real attack that produced no alert, events that do not correlate. It is the troubleshooting of the *detection capability*, complementary to the technical install troubleshooting in [Wazuh / troubleshooting](../Wazuh/docs/troubleshooting.en.md).

Compass: in the SOC, "no alert" has two opposite readings and must always be disambiguated. It can mean **all quiet** or **I am blind**. An analyst does not trust silence: they verify it.

---

## Problem 1: A source has stopped generating events

**Symptom:** no more alerts arrive from a source that used to work (e.g. no Cowrie events, or no UFW events for days).

**Cause:** a break at some point in the 6-phase pipeline (collection -> decoding -> rules -> enrichment -> indexing -> visualization). The fault is almost always in **collection**: the log is no longer written, or the agent no longer reads it.

**Solution (follow the pipeline from the source up):**

```bash
# 1. Is the source still writing its log?
tail -3 /var/log/auth.log                                   # SSH
docker exec cowrie tail -3 /home/cowrie/cowrie-git/var/log/cowrie/cowrie.json   # Cowrie
tail -3 /var/log/ufw.log                                    # UFW

# 2. Is the Wazuh agent reading that file? (there must be a <localfile> in ossec.conf)
sudo grep -A2 "<localfile>" /var/ossec/etc/ossec.conf | grep -i "auth.log\|cowrie\|ufw"

# 3. Is the agent connected and active?
sudo /var/ossec/bin/agent_control -l

# 4. Does an event from that source still produce an alert? (test decoder+rule)
echo '<sample log line>' | sudo /var/ossec/bin/wazuh-logtest
```

If the log is empty, the problem is in the source service (see the relevant module's troubleshooting). If the log populates but the alert does not arrive, the problem is decoder/rules (Problem 3).

---

## Problem 2: Too many false positives (alert fatigue)

**Symptom:** the dashboard is flooded with low-priority alerts and the important events get lost in the noise.

**Cause:** rules too noisy or not tuned to the lab's context (e.g. your own weekly scan triggering network alerts).

**Solution:** apply tuning instead of ignoring the alerts. The main levers:
- **Filter by level**: work on alerts of level >= 7-10 and relegate the minor ones to reports.
- **Targeted syscheck exclusions** for the paths that change legitimately and often.
- **Composite rules** to aggregate N repeated events into a single alert.

The full method (severity levels, exclusions, composite rules with XML examples) is in [alert-fatigue](alert-fatigue.en.md).

> Golden rule: **do not silence an alert without understanding it.** Every exclusion must be justified; a rule disabled "because it's noisy" is a blind spot created on purpose.

---

## Problem 3: A real attack did NOT produce an alert (blind spot)

**Symptom:** you ran a test (or suffered a real event) that should have generated an alert, but there is nothing in the dashboard.

**Cause:** the log arrives but no **decoder** interprets it, or no **rule** matches, or the rule has a level below the alerting threshold.

**Solution:**

```bash
# Replay the event against the rule engine and see what happens
sudo /var/ossec/bin/wazuh-logtest
# Paste a real log line of the event and observe:
#   "Phase 2: decoder" -> which decoder interpreted it (if none -> a decoder is needed)
#   "Phase 3: rule"    -> which rule matched and at what level (if none -> a rule is needed)
```

This is exactly the workflow to close a **detection gap**: if the test in [Security Assessment / correlazione-eventi](../../Security%20Assessment%20%26%20Hardening/docs/correlazione-eventi.en.md) does not generate the expected alert, the cause is found here.

---

## Problem 4: The dashboard does not show recent data

**Symptom:** the UI loads but the panels show only old data or are empty.

**Cause:** it is a technical fault of the downstream pipeline (Filebeat -> Indexer -> template/ILM), not a detection problem.

**Solution:** this case is covered in detail by the technical troubleshooting:
- Filebeat not shipping / missing template -> [Wazuh / troubleshooting](../Wazuh/docs/troubleshooting.en.md)
- Indexer down / certificates / full disk -> [Incident Recovery / Wazuh dashboard](../../Incident%20Recovery%20%26%20Resilience/docs/wazuh-dashboard-recovery.en.md)

```bash
# Quick check: are recent alert indices arriving?
curl -sk -u admin:admin "https://localhost:9200/_cat/indices/wazuh-alerts-*?v&s=index" | tail -3
```

---

## Problem 5: Events do not correlate with each other

**Symptom:** the same attacking IP appears in multiple separate alerts (SSH, UFW, Cowrie) but there is no unified view of the attack.

**Cause:** there is no correlation/composite rule tying together events from the same source-IP into a chain.

**Solution:** from the analyst's point of view, correlate manually and then automate:

```
Correlation workflow (from the module README):
  Alert -> Triage (known IP? internal/external?) -> Investigation (filter by IP)
        -> Correlation (same IP on SSH+UFW+Cowrie?) -> Response (ufw deny / verify ban)
```

In the dashboard, filter Threat Hunting by `data.srcip: <IP>` to see all the correlated events. To automate, use composite rules (`<if_matched_sid>` / `frequency`) as in [alert-fatigue](alert-fatigue.en.md).

---

## Problem 6: Missing visibility over a source (not monitored)

**Symptom:** an important service never appears in the alerts because its logs are not collected at all.

**Cause:** the source is not configured as a `<localfile>` (for file logs) or `<command>` (for command output) in the agent.

**Solution:**

```xml
<!-- In /var/ossec/etc/ossec.conf, add the missing source -->
<localfile>
  <log_format>json</log_format>
  <location>/path/to/log.json</location>
</localfile>
```

```bash
sudo systemctl restart wazuh-agent    # or wazuh-manager if it's the local agent 000
```

The complete map of the sources the lab should monitor is in the "What we monitor" table of the [module README](../README.en.md).

---

## Useful verification commands

```bash
# Connected agents and their state
sudo /var/ossec/bin/agent_control -l

# Manual test of the decoder+rule pipeline
sudo /var/ossec/bin/wazuh-logtest

# Latest alerts in realtime
sudo tail -f /var/ossec/logs/alerts/alerts.json

# Statistics: which rules fire the most (tuning candidates)
sudo grep -o '"rule":{"level":[0-9]*,"description":"[^"]*"' /var/ossec/logs/alerts/alerts.json | sort | uniq -c | sort -rn | head
```

---

## Links

- Technical Wazuh troubleshooting (install, services, certificates) -> [Wazuh / troubleshooting](../Wazuh/docs/troubleshooting.en.md)
- Inaccessible dashboard (operational recovery) -> [Incident Recovery / Wazuh dashboard](../../Incident%20Recovery%20%26%20Resilience/docs/wazuh-dashboard-recovery.en.md)
- Tuning and false-positive reduction -> [alert-fatigue](alert-fatigue.en.md)
- Log pipeline (6 phases) -> [log-pipeline](log-pipeline.en.md)
- Incident response playbooks -> [incident-response](incident-response.en.md)
