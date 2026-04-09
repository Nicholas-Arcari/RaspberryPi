# Verifica integrazione Wazuh - File Integrity Monitoring

Se Wazuh e' installato (vedi sezione [SOC Analyst/Wazuh](../../SOC%20Analyst/Wazuh/README.md)), possiamo verificare che il modulo **Syscheck (File Integrity Monitoring)** stia monitorando il sistema.

---

## Cos'e' il File Integrity Monitoring (FIM)

FIM calcola l'hash crittografico (SHA-256) di ogni file nelle directory monitorate (es. `/etc`, `/usr/bin`). Periodicamente, ricalcola gli hash e confronta. Se un file e' stato modificato, creato o eliminato, Wazuh genera un alert.

**Perche' e' critico:** Se un attaccante modifica `/etc/passwd`, `/etc/shadow`, `/etc/ssh/sshd_config` o un binario di sistema, Wazuh lo rileva. Questo e' fondamentale per individuare compromissioni post-exploitation.

---

## Verifica che Syscheck sia attivo

```bash
sudo /var/ossec/bin/wazuh-control status
```

Cercare: `wazuh-syscheckd is running`

---

## Controllare i log di Syscheck

```bash
sudo tail -f /var/ossec/logs/ossec.log
```

Cercare righe come:

```
wazuh-syscheckd: INFO: Monitoring directory: '/etc'
wazuh-syscheckd: INFO: Monitoring directory: '/usr/bin'
```

---

## Test pratico - generare un alert FIM

```bash
# Crea un file in una directory monitorata
sudo touch /etc/test-wazuh

# Osserva i log
sudo tail -f /var/ossec/logs/ossec.log
```

Entro pochi minuti (dipende dall'intervallo di scan configurato), vedrai un evento FIM nei log. L'alert comparira' anche nella Dashboard Wazuh sotto **Security Events**.

```bash
# Pulizia dopo il test
sudo rm /etc/test-wazuh
```

---

## Forzare un rescan immediato

```bash
sudo /var/ossec/bin/wazuh-control restart
```

Questo forza:

- Nuovo scan completo del filesystem
- Ricalcolo di tutti gli hash
- Invio degli eventi al Manager
