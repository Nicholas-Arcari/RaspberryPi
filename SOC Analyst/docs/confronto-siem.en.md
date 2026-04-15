>  [Italiano](confronto-siem.md) |  **English**

# Why Wazuh and not Splunk (or other SIEMs)

Choosing a SIEM is a critical architectural decision. Wazuh was not chosen "because it's free" - it was chosen for technical reasons specific to our use case.

## Architectural comparison

| Aspect | Wazuh | Splunk Enterprise | Splunk Free | Elastic SIEM |
|---|---|---|---|---|
| **License** | Open source (GPLv2) | Commercial (~$2000/GB/year) | Free, 500MB/day | Open source (SSPL) |
| **Cost for our lab** | $0 | ~$15,000+/year (unfeasible) | $0 but very limited | $0 |
| **ARM64 (Raspberry Pi)** | ARM64 .deb packages available | **NOT available** on ARM | **NOT available** on ARM | ARM64 packages available |
| **Integrated agent** | Yes (FIM, rootcheck, vulnerability detection) | Universal Forwarder (log shipping only) | Universal Forwarder | Elastic Agent |
| **Integrated IDS/IPS** | Partial (log analysis rules) | No (requires add-on) | No | No |
| **Active Response** | Yes (automatic IP blocking) | No native (requires SOAR) | No | No native |
| **Compliance** | PCI DSS, GDPR, HIPAA, CIS | Yes (with paid add-ons) | No | Partial |
| **Storage backend** | OpenSearch (Elasticsearch fork) | Proprietary (Splunk indexes) | Proprietary | Elasticsearch |
| **Query language** | OpenSearch DSL (JSON) | SPL (Splunk Processing Language) | SPL | KQL / EQL |
| **Resources on RPi 5 (8GB)** | ~4-5GB total RAM | N/A (does not run on ARM) | N/A | ~3-4GB RAM |

## The real motivation

1. **ARM64**: Splunk simply does not run on Raspberry Pi. End of discussion for our hardware. If we had an x86_64 server with 32GB of RAM, Splunk Enterprise would be a valid choice

2. **All-in-one**: Wazuh is not just a SIEM - it is also an XDR. The agent performs FIM, vulnerability detection, rootcheck, log collection, and compliance in a single package. With Splunk, you would need to install separately: Universal Forwarder + OSSEC/Tripwire (FIM) + Nessus/OpenVAS (vulnerability) + compliance tools

3. **Active Response**: Wazuh can automatically block an IP when an alert reaches a certain threshold. Splunk requires a separate SOAR (Splunk SOAR, formerly Phantom) - another paid product

4. **Cost**: For an educational home lab, Splunk's cost is prohibitive. Wazuh offers 90% of the functionality at zero cost

## If you wanted to migrate to Splunk (on x86_64 hardware)

The required architectural changes:

```
CURRENT (Wazuh):
Agent → Manager :1514 → Filebeat → OpenSearch :9200 → Dashboard :443

SPLUNK:
Universal Forwarder → Splunk Indexer :9997 → Splunk Search Head :8000
                                       ↑
                              Splunk Heavy Forwarder
                              (parsing and filtering)
```

| Wazuh component | Replaced by | Configuration |
|---|---|---|
| Wazuh Agent | Splunk Universal Forwarder | `inputs.conf`: log monitoring, `outputs.conf`: pointing to the Indexer |
| Wazuh Manager (decoder + rules) | Splunk Heavy Forwarder + `props.conf`/`transforms.conf` | Parsing rules (regex for field extraction), lookup tables for enrichment |
| OpenSearch (Indexer) | Splunk Indexer | `indexes.conf`: index definition, retention policy, storage volume |
| Wazuh Dashboard | Splunk Search Head | Custom dashboards in Simple XML or Dashboard Studio |
| Filebeat | Not needed | The Forwarder sends directly to the Indexer |
| Custom rules (local_rules.xml) | Correlation searches + Notable events | Scheduled SPL queries in Enterprise Security |
| Active Response | Splunk SOAR (Phantom) | Automated playbooks (separate product, paid) |

**Key files to create/modify for Splunk:**

```ini
# inputs.conf (on the Forwarder - equivalent to <localfile> in ossec.conf)
[monitor:///var/log/auth.log]
sourcetype = linux_secure
index = security

[monitor:///var/log/cowrie/cowrie.json]
sourcetype = cowrie:json
index = honeypot

# props.conf (parsing - equivalent to Wazuh decoders)
[cowrie:json]
KV_MODE = json
TIME_FORMAT = %Y-%m-%dT%H:%M:%S.%6N%Z
TIME_PREFIX = "timestamp":"

# savedsearches.conf (correlation - equivalent to Wazuh rules)
[Honeypot Login Success]
search = index=honeypot sourcetype=cowrie:json eventid=cowrie.login.success
alert_threshold = 1
action.email = 1
cron_schedule = */5 * * * *
```

> **Note for those studying:** In an interview for a SOC analyst position, being able to explain the architectural differences between Wazuh and Splunk (and when to use one or the other) is a strong point. Wazuh for labs/SMBs with limited budget and the need for integrated agents. Splunk for enterprises with budget, high data volumes, and the need for SPL for complex queries.
