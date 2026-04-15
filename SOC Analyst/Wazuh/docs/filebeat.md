>  [English](filebeat.en.md) |  **Italiano**

# Filebeat: il "Postino" dei log

## Perchè serve Filebeat

Un errore comune è vedere la Dashboard funzionante ma vuota, con l'errore **"No template found"**. Questo accade perchè manca il componente che trasporta gli alert dal Manager all'Indexer.

Il Manager scrive gli alert in `/var/ossec/logs/alerts/alerts.json`. L'Indexer aspetta di ricevere dati via HTTPS sulla porta 9200. Filebeat fa da ponte.

---

## Installazione

```bash
sudo apt install filebeat -y
```

---

## Configurazione (`/etc/filebeat/filebeat.yml`)

Sostituire l'intero contenuto con:

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

**Parametri critici:**

- `output.elasticsearch`: nonostante il nome, punta all'Indexer (che è un fork di Elasticsearch/OpenSearch)
- `setup.ilm.enabled: false`: **fondamentale**. ILM (Index Lifecycle Management) è una feature di Elasticsearch che crea indici con naming pattern diverso da quello atteso da Wazuh. Se abilitato, Filebeat crea indici `filebeat-7.x-*` invece di `wazuh-alerts-*` e la Dashboard non li trova
- `ssl.verification_mode: none`: necessario con certificati self-signed

---

## Download del template e setup

```bash
# Scarica il template JSON che definisce la struttura degli indici Wazuh
sudo curl -so /etc/filebeat/wazuh-template.json https://raw.githubusercontent.com/wazuh/wazuh/v4.9.2/extensions/elasticsearch/7.x/wazuh-template.json
sudo chmod 444 /etc/filebeat/wazuh-template.json

# Carica il template nell'Indexer
sudo filebeat setup --index-management

# Avvia Filebeat
sudo systemctl enable filebeat
sudo systemctl restart filebeat
```

---

## Verifica connessione

```bash
sudo filebeat test output
```

Output atteso:

```
elasticsearch: https://127.0.0.1:9200...
  parse url... OK
  connection... OK
  TLS... OK
  talk to server... OK
  version: 7.10.2
```

Se mostra `ERROR`, verificare certificati, password e stato dell'Indexer.
