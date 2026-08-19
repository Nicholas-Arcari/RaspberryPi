>  [English](wazuh-dashboard-recovery.en.md) |  **Italiano**

# Runbook 03 - Wazuh dashboard inaccessibile

> **Quando usare questo runbook:** apri `https://192.168.0.102` (Wazuh Dashboard) e ottieni un timeout, un errore SSL, una pagina che gira a vuoto, "Wazuh dashboard server is not ready yet", o un login che non accetta le credenziali. Questo runbook ti porta dalla schermata bianca alla causa esatta.

Punto chiave da capire subito: nel lab, Wazuh gira **bare-metal** (non in Docker), come tre servizi systemd distinti piu' Filebeat. La dashboard e' solo la punta:

```
   Browser --HTTPS:443--> wazuh-dashboard --HTTPS:9200--> wazuh-indexer (OpenSearch)
                                                                ^
                              wazuh-manager --> Filebeat -------+  (spedisce gli alert)
```

**La dashboard non funziona quasi mai per colpa sua:** nel 90% dei casi il guasto e' sotto (indexer giu', certificati scaduti, disco pieno). Si diagnostica dal basso.

---

## Passo 0 - Fotografia dello stack

```bash
# Stato dei quattro componenti in un colpo solo
sudo systemctl status wazuh-indexer wazuh-manager wazuh-dashboard filebeat --no-pager | grep -E "●|Active:"

# Versione sintetica
sudo systemctl is-active wazuh-indexer wazuh-manager wazuh-dashboard filebeat
# Atteso: active active active active
```

Interpretazione immediata:

| Cosa e' `inactive`/`failed` | Vai a |
|---|---|
| Solo `wazuh-dashboard` | Passo 1 |
| `wazuh-indexer` (con o senza dashboard) | Passo 2 (la causa piu' frequente) |
| Tutto attivo ma la pagina non carica / SSL error | Passo 3 (certificati) o Passo 4 (risorse) |
| Tutto attivo, pagina ok, ma nessun dato | Passo 5 (Filebeat) |
| Login rifiutato | Passo 6 (credenziali) |

---

## Passo 1 - Solo la dashboard e' giu'

```bash
sudo journalctl -u wazuh-dashboard -b --no-pager | tail -40
sudo systemctl restart wazuh-dashboard

# La dashboard risponde in locale?
curl -sk -o /dev/null -w "%{http_code}\n" https://localhost:443
# Atteso: 200 o 302. "000" = non risponde -> leggi i log sopra
```

Cause tipiche nei log: `opensearch_dashboards.yml` con host/porta dell'indexer sbagliati, oppure la dashboard parte **prima** dell'indexer al boot (race condition). Se e' una race, il restart manuale risolve; per la cura definitiva vedi Prevenzione.

---

## Passo 2 - L'indexer non parte (la causa numero uno)

La dashboard senza indexer e' una vetrina senza magazzino. L'indexer (OpenSearch su ARM64) e' anche il componente piu' fragile sul Pi, per due motivi: **RAM** e **certificati**.

```bash
sudo systemctl status wazuh-indexer --no-pager
sudo journalctl -u wazuh-indexer -b --no-pager | tail -60
```

Leggi i log cercando questi pattern:

| Riga nel log | Causa | Fix -> |
|---|---|---|
| `Native controller ... memory` / `OutOfMemoryError` / heap | RAM insufficiente / heap mal tarata | Passo 4 |
| `failed to load ... certificate` / `PKIX path` / `certificate expired` | Certificati TLS scaduti o permessi errati | Passo 3 |
| `no space left on device` | Disco pieno | Passo 4 + [Runbook 09](risorse-e-credenziali.md) |
| `bootstrap check failure` / `max virtual memory areas vm.max_map_count` | `vm.max_map_count` troppo basso | Fix sotto |

```bash
# Fix classico del bootstrap check (OpenSearch richiede vm.max_map_count alto)
sudo sysctl -w vm.max_map_count=262144
echo 'vm.max_map_count=262144' | sudo tee /etc/sysctl.d/99-wazuh.conf
sudo systemctl restart wazuh-indexer

# Verifica che l'indexer risponda alla sua API
curl -sk -u admin:admin https://localhost:9200 | head
# Atteso: JSON con "cluster_name" e versione. Errore -> ancora giu'
```

---

## Passo 3 - Certificati TLS scaduti (il guasto "a tempo")

Wazuh usa una PKI interna (certificati generati all'installazione) per cifrare indexer, manager, filebeat e dashboard. Questi certificati **hanno una scadenza**: dopo mesi/anni possono scadere e allora tutti i componenti si rifiutano di parlarsi, con errori SSL. E' un guasto insidioso perche' arriva "dal nulla" senza che tu abbia toccato niente.

```bash
# Controlla la scadenza dei certificati dell'indexer
sudo openssl x509 -enddate -noout -in /etc/wazuh-indexer/certs/indexer.pem
sudo openssl x509 -enddate -noout -in /etc/wazuh-indexer/certs/root-ca.pem
# Se "notAfter" e' nel passato -> certificati scaduti

# Errore tipico lato dashboard/filebeat quando i certificati sono scaduti:
#   "x509: certificate has expired or is not yet valid"
```

Rigenerazione dei certificati (procedura Wazuh; adattare i percorsi alla propria installazione):

```bash
# Usa il tool ufficiale di generazione certificati con il file di config del cluster
sudo /path/wazuh-certs-tool.sh -A            # rigenera l'intera PKI
# Ridistribuisci i .pem nelle cartelle certs/ di indexer, manager, dashboard, filebeat
# Correggi proprietario e permessi (causa frequente di "Permission denied"):
sudo chown wazuh-indexer:wazuh-indexer /etc/wazuh-indexer/certs/*
sudo chmod 400 /etc/wazuh-indexer/certs/*.pem
sudo systemctl restart wazuh-indexer wazuh-manager filebeat wazuh-dashboard
```

> **Nota permessi (dal troubleshooting Wazuh esistente):** ogni componente gira come un utente dedicato (`wazuh-indexer`, `wazuh-dashboard`...). Se copi i certificati come root, il servizio non li legge e fallisce con "Permission denied". Dopo ogni rigenerazione, sistemare `chown`/`chmod` e' obbligatorio.

---

## Passo 4 - Risorse esaurite: RAM, heap, disco

Sul Pi 5 (8GB) l'indexer + dashboard + manager competono per la RAM. E' il motivo per cui il progetto richiede 8GB e non 4. Due sintomi: l'indexer viene ucciso dall'OOM killer, oppure il disco pieno blocca l'indicizzazione.

```bash
# RAM e swap: l'indexer da solo vuole ~1-2GB di heap
free -h
# Chi e' stato ucciso dall'OOM killer di recente?
sudo dmesg -T | grep -i "killed process"
# Atteso vuoto. "Killed process ... java" -> l'indexer e' stato oomkillato

# Spazio disco: OpenSearch entra in read-only se il disco supera il 95%
df -h /
# La heap dell'indexer (default meta' RAM; su un Pi condiviso va limitata)
grep -E "Xms|Xmx" /etc/wazuh-indexer/jvm.options
# Es. -Xms1g / -Xmx1g e' ragionevole su un Pi con altri servizi
```

Se l'indexer va read-only per disco pieno, dopo aver liberato spazio ([Runbook 09](risorse-e-credenziali.md)) sblocca gli indici:

```bash
curl -sk -u admin:admin -X PUT "https://localhost:9200/_all/_settings" \
  -H 'Content-Type: application/json' \
  -d '{"index.blocks.read_only_allow_delete": null}'
```

---

## Passo 5 - Tutto su, ma nessun dato (Filebeat)

La dashboard carica ma i pannelli sono vuoti: gli alert non arrivano dal manager all'indexer. E' esattamente il caso "No template found" del troubleshooting Wazuh.

```bash
# Filebeat riesce a parlare con l'indexer?
sudo filebeat test output
# Atteso: "elasticsearch: https://127.0.0.1:9200 ... OK"

# Il template e gli indici sono a posto?
curl -sk -u admin:admin "https://localhost:9200/_cat/indices/wazuh-alerts-*?v"
# Atteso: righe di indici wazuh-alerts-*. Vuoto -> template/ILM sbagliati:
sudo filebeat setup --index-management
```

---

## Passo 6 - Login rifiutato (credenziali)

Ci arrivi, la pagina di login carica, ma `admin`/password non entra. Reset con il tool ufficiale:

```bash
# Reset della password admin dell'indexer/dashboard
sudo /usr/share/wazuh-indexer/bin/indexer-security-init.sh
# oppure (versioni recenti) il password tool di Wazuh:
sudo /var/ossec/bin/wazuh-passwords-tool.sh -u admin -p 'NuovaPasswordForte'
```

> **Prerequisito di recovery:** la password admin e le chiavi di sicurezza dell'indexer vanno nel tuo password manager offline **prima** di averne bisogno. Se sono solo nella tua testa o solo sul Pi, un reset a freddo e' molto piu' doloroso.

---

## Verifica di ripristino

```bash
sudo systemctl is-active wazuh-indexer wazuh-manager wazuh-dashboard filebeat   # 4x active
curl -sk -o /dev/null -w "dashboard=%{http_code}\n" https://localhost:443       # 200/302
curl -sk -u admin:admin https://localhost:9200/_cluster/health | grep -o '"status":"[a-z]*"'
# Atteso: "status":"green" (o almeno "yellow" su nodo singolo)
```

Poi apri la dashboard dal browser e conferma che arrivino alert recenti.

---

## Prevenzione

- **Ordine di avvio:** rendi `wazuh-dashboard` dipendente dall'indexer (`After=wazuh-indexer.service` via drop-in) per uccidere la race condition al boot.
- **Certificati:** annota la data di scadenza della PKI e mettiti un promemoria a -1 mese. Un certificato scaduto e' il guasto piu' facile da prevenire e piu' frustrante da subire alla cieca.
- **Risorse:** limita la heap dell'indexer in `jvm.options`, metti un tetto ai log ([Runbook 09](risorse-e-credenziali.md)), e fai monitorare a Wazuh stesso lo spazio disco (si', puo' allertare sul proprio disco pieno finche' e' vivo).
- **Backup:** includi `/etc/wazuh-*`, `/var/ossec/etc/` e le regole custom nel [Runbook 08](backup-e-disaster-recovery.md). Ricreare le regole a mano e' un RPO che non vuoi.

---

## Collegamenti

- Disco pieno / OOM come causa radice -> [Runbook 09: risorse e credenziali](risorse-e-credenziali.md)
- Troubleshooting Wazuh d'installazione (errori originali documentati) -> [SOC Analyst / Wazuh / troubleshooting](../../SOC%20Analyst/Wazuh/docs/troubleshooting.md)
- PKI e TLS di Wazuh in dettaglio -> [SOC Analyst / Wazuh / tls-pki](../../SOC%20Analyst/Wazuh/docs/tls-pki.md)
- Filebeat e pipeline dei log -> [SOC Analyst / Wazuh / filebeat](../../SOC%20Analyst/Wazuh/docs/filebeat.md)
