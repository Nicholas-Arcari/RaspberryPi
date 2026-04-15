>  [Italiano](alert-fatigue.md) |  **English**

# Alert Fatigue and Tuning: the most underestimated problem

## What is alert fatigue

Alert fatigue occurs when an analyst receives **too many alerts** (the majority of which are false positives or low-priority events), to the point of systematically ignoring them. In an enterprise SOC, an L1 analyst can receive 500-1000+ alerts per day. If 95% are false positives, the probability of ignoring the 5% that are real incidents is high.

**In our lab** the problem manifests on a smaller but real scale: Cowrie generates dozens of alerts for every bot that scans port 2222. If every single failed login attempt generates a level 5 alert, the dashboard becomes unusable within a few hours.

## Tuning strategies

**1. Adjust severity levels:**

Wazuh rules have levels from 0 (no alert) to 15 (emergency). Tuning consists of raising the notification threshold and adjusting levels based on context:

```xml
<!-- Example: reduce noise from failed logins on the honeypot -->
<!-- Before (too noisy): every single failure generates a level 5 alert -->
<rule id="100011" level="5">
  <decoded_as>cowrie</decoded_as>
  <field name="eventid">cowrie.login.failed</field>
  <description>Cowrie: Failed login attempt</description>
</rule>

<!-- After (tuned): alert only after 10 failures in 120 seconds from the same IP -->
<rule id="100011" level="5" frequency="10" timeframe="120">
  <decoded_as>cowrie</decoded_as>
  <field name="eventid">cowrie.login.failed</field>
  <same_source_ip />
  <description>Cowrie: Brute force detected (10+ failures in 2 min)</description>
</rule>
```

**2. Targeted exclusions (syscheck rules):**

File Integrity Monitoring (syscheck) generates alerts every time a monitored file changes. Files that change legitimately (rotating logs, temporary files, cache) produce continuous false positives:

```xml
<!-- Exclude directories with frequent legitimate changes -->
<syscheck>
  <ignore>/var/log</ignore>
  <ignore>/tmp</ignore>
  <ignore>/var/cache</ignore>
  <ignore type="sregex">.swp$</ignore>  <!-- Vim temporary files -->
</syscheck>
```

**3. Aggregation and correlation:**

Instead of generating an alert for every single event, group correlated events together. Wazuh supports composite rules with `<if_matched_sid>`:

```xml
<!-- Child rule: triggers only if rule 100012 (login success)
     was triggered by the same IP that also triggered
     rule 100013 (command executed) within 300 seconds -->
<rule id="100015" level="12">
  <if_matched_sid>100012</if_matched_sid>
  <same_source_ip />
  <description>Cowrie: Attacker executed commands after login - possible interactive session</description>
  <mitre>
    <id>T1059</id>  <!-- Command and Scripting Interpreter -->
  </mitre>
</rule>
```

> **Golden rule of tuning**: an alert must require an action. If an analyst looks at an alert and the response is systematically "ignore", that rule needs tuning (lower the level, raise the threshold, or exclude it). Tuning is not a one-time activity - it is a continuous process that improves over time as you understand the patterns of your environment.
