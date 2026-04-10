# Installazione Cowrie con integrazione Wazuh

## Architettura del progetto

```
Attaccante (Internet/LAN)
    │
    │ SSH porta 2222
    ▼
[Cowrie Container] ──log JSON──→ [Wazuh Agent] ──events──→ [Wazuh Manager]
                                                                │
                                                                ▼
                                                         [Wazuh Indexer]
                                                                │
                                                                ▼
                                                         [Wazuh Dashboard]
                                                         (Alert + Threat Hunting)
```

Il flusso completo:

1. **L'attaccante** si collega alla porta 2222 (esposta da Cowrie, non la vera porta SSH 22)
2. **Cowrie** registra tutto in `/var/log/cowrie/cowrie.json` (IP, password, comandi)
3. **L'agente Wazuh** monitora quel file in tempo reale (tail -f concettuale)
4. **Wazuh Manager** riceve gli eventi, li decodifica con il decoder JSON e li confronta con le regole
5. Se una regola fa match, genera un **alert** che appare sulla Dashboard

## Prerequisiti

- Raspberry Pi con Docker e Docker Compose installati
- Wazuh Manager e Agent installati (All-in-One sul Pi o Manager su server esterno)
- Porta 2222 libera (non occupata da altri servizi)

## Installazione Passo-Passo

### Step 1: Setup di Cowrie con Docker

#### Creazione delle directory

```bash
mkdir -p ~/cowrie/var/log/cowrie
mkdir -p ~/cowrie/etc
cd ~/cowrie
```

La struttura `var/log/cowrie` sara' montata come volume nel container - i log di Cowrie verranno scritti qui, dove Wazuh potra' leggerli.

#### Docker Compose

Creare il file `docker-compose.yml`:

```yaml
version: "3"
services:
  cowrie:
    image: cowrie/cowrie:latest
    container_name: cowrie
    restart: always
    ports:
      - "2222:2222"  # Porta SSH Honeypot
      - "2223:2223"  # Porta Telnet Honeypot
    volumes:
      # Monta SOLO i log - NON montare /etc (vedi Troubleshooting Errore 1)
      - ./var/log/cowrie:/cowrie/cowrie-git/var/log/cowrie
```

> **Perche' la porta 2222 e non la 22:** La porta 22 e' occupata dal vero server SSH del Raspberry Pi. Se usassimo la 22 per l'honeypot, perderemmo l'accesso SSH reale al sistema. In un deployment di produzione, si potrebbe fare NAT per esporre la porta 2222 come porta 22 verso Internet (dal punto di vista dell'attaccante, sembra un normale SSH).

#### Avvio

```bash
docker compose up -d
```

Verifica che il container sia in esecuzione:

```bash
docker ps | grep cowrie
# Stato atteso: Up X minutes (non "Restarting")
```

### Step 2: Configurazione Wazuh per ingestione log Cowrie

Dobbiamo istruire l'agente Wazuh a monitorare il file JSON prodotto da Cowrie.

#### Modifica di ossec.conf

Aprire il file di configurazione dell'agente Wazuh:

```bash
sudo nano /var/ossec/etc/ossec.conf
```

Aggiungere questo blocco **prima** del tag di chiusura `</ossec_config>`:

```xml
<localfile>
  <log_format>json</log_format>
  <location>/home/<tuo_utente>/cowrie/var/log/cowrie/cowrie.json</location>
</localfile>
```

**Cosa fa:** Istruisce l'agente Wazuh a:

1. Monitorare il file specificato in tempo reale (come `tail -f`)
2. Parsare ogni nuova riga come JSON (non come syslog tradizionale)
3. Inviare gli eventi parsati al Wazuh Manager per l'analisi

#### Fix dei permessi

Docker crea i file di log con l'utente interno del container. Wazuh (che gira come utente `wazuh` o `ossec`) potrebbe non riuscire a leggerli:

```bash
sudo chmod -R 755 /home/<tuo_utente>/cowrie/var/log/cowrie/
```

> **Nota:** In un ambiente di produzione, sarebbe meglio usare ACL o aggiungere l'utente `wazuh` al gruppo del container. Il `chmod 755` e' la soluzione rapida per un home lab.

#### Riavvio dell'agente

```bash
sudo systemctl restart wazuh-agent
# oppure, se e' all-in-one:
sudo /var/ossec/bin/wazuh-control restart
```
