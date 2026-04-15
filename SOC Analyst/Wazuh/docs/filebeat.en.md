>  [Italiano](filebeat.md) |  **English**

# Filebeat: The Log "Courier"

## Why Filebeat is Needed

A common mistake is seeing the Dashboard functional but empty, with the **"No template found"** error. This happens because the component that transports alerts from the Manager to the Indexer is missing.

The Manager writes alerts to `/var/ossec/logs/alerts/alerts.json`. The Indexer expects to receive data via HTTPS on port 9200. Filebeat bridges the gap.

---

## Installation

```bash
sudo apt install filebeat -y
```

---

## Configuration (`/etc/filebeat/filebeat.yml`)

Replace the entire content with:

```yaml
output.elasticsearch:
  hosts: ["127.0.0.1:9200"]
  protocol: https
  username: "admin"
  password: "admin"
  ssl.certificate_authorities: ["/etc/filebeat/certs/root-ca.pem"]
  ssl.certificate: "/etc/filebeat/certs/filebeat.pem"
  ssl.key: "/etc/filebeat/certs/filebeat-key.pem"
  ssl.verification_mode: none

setup.template.json.enabled: true
setup.template.json.path: '/etc/filebeat/wazuh-template.json'
setup.template.json.name: 'wazuh'
setup.ilm.overwrite: true
setup.ilm.enabled: false

filebeat.modules:
  - module: wazuh
    alerts:
      enabled: true
    archives:
      enabled: false
```

**Critical parameters:**

- `output.elasticsearch`: despite the name, it points to the Indexer (which is an Elasticsearch/OpenSearch fork)
- `setup.ilm.enabled: false`: **essential**. ILM (Index Lifecycle Management) is an Elasticsearch feature that creates indices with a naming pattern different from what Wazuh expects. If enabled, Filebeat creates `filebeat-7.x-*` indices instead of `wazuh-alerts-*` and the Dashboard cannot find them
- `ssl.verification_mode: none`: required with self-signed certificates

---

## Template Download and Setup

```bash
# Download the JSON template that defines the structure of Wazuh indices
sudo curl -so /etc/filebeat/wazuh-template.json https://raw.githubusercontent.com/wazuh/wazuh/v4.9.2/extensions/elasticsearch/7.x/wazuh-template.json
sudo chmod 444 /etc/filebeat/wazuh-template.json

# Load the template into the Indexer
sudo filebeat setup --index-management

# Start Filebeat
sudo systemctl enable filebeat
sudo systemctl restart filebeat
```

---

## Connection Verification

```bash
sudo filebeat test output
```

Expected output:

```
elasticsearch: https://127.0.0.1:9200...
  parse url... OK
  connection... OK
  TLS... OK
  talk to server... OK
  version: 7.10.2
```

If it shows `ERROR`, check the certificates, password, and Indexer status.
