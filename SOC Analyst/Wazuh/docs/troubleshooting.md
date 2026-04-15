>  [English](troubleshooting.en.md) |  **Italiano**

# Troubleshooting e Manutenzione Wazuh

## Problemi riscontrati e soluzioni

### 1. Script automatico "Uncompatible system"

**Problema:** Lo script `wazuh-install.sh` bloccava l'installazione con errore "Uncompatible system" su Raspberry Pi OS.

**Causa:** Lo script controlla `/etc/os-release` e la lista di sistemi supportati non include Raspberry Pi OS (anche se è Debian-based).

**Soluzione:** Abbandonato lo script a favore dell'installazione manuale tramite `apt` con repository forzato `arch=arm64`.

### 2. Permessi GPG "Permission denied"

**Problema:** Il comando `curl ... | gpg ...` dava "Permission denied".

**Causa:** La pipe `|` esegue il secondo comando con i permessi dell'utente corrente (non root). `gpg` tentava di scrivere in `/usr/share/keyrings/` che richiede privilegi root.

**Soluzione:** `curl ... | sudo gpg ...` - il `sudo` va sul secondo comando della pipe, non sul primo.

### 3. Dashboard "No template found"

**Problema:** La Dashboard era raggiungibile ma mostrava un errore rosso persistente e nessun dato.

**Causa:** Due possibilità:
- Filebeat non installato o non avviato
- ILM abilitato che creava indici con naming pattern sbagliato (`filebeat-7.x` invece di `wazuh-alerts-*`)

**Soluzione:** Installato Filebeat, disabilitato ILM (`setup.ilm.enabled: false`) e forzato il caricamento del template corretto con `filebeat setup --index-management`.

### 4. Servizi non partono - "Permission denied" sui certificati

**Problema:** `systemctl start wazuh-indexer` falliva. I log mostravano "Permission denied" sui file `.pem`.

**Causa:** I certificati erano stati copiati con i permessi dell'utente corrente. Il servizio `wazuh-indexer` gira come utente `wazuh-indexer` e non poteva leggere file di proprietà `root`.

**Soluzione:** `chown` corretto per ogni componente e permessi restrittivi (`chmod 400` sui file, `chmod 500` sulle directory).

---

## Comandi utili per manutenzione

```bash
# Stato di tutti i servizi Wazuh
sudo systemctl status wazuh-indexer wazuh-manager wazuh-dashboard filebeat

# Test connessione Filebeat -> Indexer
sudo filebeat test output

# Log del Manager (per debug regole e decoder)
sudo tail -f /var/ossec/logs/ossec.log

# Log dell'Indexer (per problemi di indicizzazione)
sudo journalctl -u wazuh-indexer -f

# Test regole in tempo reale
sudo /var/ossec/bin/wazuh-logtest

# Reset password admin (se necessario)
sudo /usr/share/wazuh-indexer/bin/indexer-security-init.sh
```
