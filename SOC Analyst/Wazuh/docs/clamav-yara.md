# ClamAV + YARA: antivirus e malware analysis integrati

## ClamAV: scansione antivirus periodica

**ClamAV** e' l'antivirus open-source piu' diffuso su Linux. Integrato con Wazuh, genera alert quando rileva malware.

```bash
# Installazione
sudo apt install clamav clamav-daemon -y

# Aggiorna le signature (prima esecuzione: puo' richiedere minuti)
sudo systemctl stop clamav-freshclam
sudo freshclam
sudo systemctl start clamav-freshclam

# Test: scarica il file di test EICAR (non e' un vero virus)
wget -O /tmp/eicar.com "https://secure.eicar.org/eicar.com"

# Scansione manuale
clamscan /tmp/eicar.com
# /tmp/eicar.com: Win.Test.EICAR_HDB-1 FOUND
```

---

## Integrazione ClamAV con Wazuh

Scansione automatica dei file scaricati dall'honeypot.

Aggiungere a `ossec.conf` sull'agent:

```xml
<!-- Esegui ClamAV quando syscheck rileva un nuovo file nella directory download Cowrie -->
<command>
  <name>clamscan</name>
  <executable>clamscan.sh</executable>
  <timeout_allowed>yes</timeout_allowed>
</command>

<active-response>
  <command>clamscan</command>
  <location>local</location>
  <rules_id>554</rules_id>  <!-- New file detected by syscheck -->
</active-response>
```

Creare lo script `/var/ossec/active-response/bin/clamscan.sh`:

```bash
#!/bin/bash
# Scansiona il file rilevato da syscheck con ClamAV
# Se positivo, Wazuh genera un alert dal log di ClamAV

LOCAL=$(dirname $0)
ALERT_FILE=$1
FILENAME=$(echo "$ALERT_FILE" | jq -r '.parameters.alert.syscheck.path')

if [[ -f "$FILENAME" ]]; then
    clamscan --no-summary "$FILENAME" >> /var/log/clamav/wazuh-scan.log 2>&1
fi
```

Aggiungere il log ClamAV come sorgente Wazuh:

```xml
<localfile>
  <log_format>syslog</log_format>
  <location>/var/log/clamav/wazuh-scan.log</location>
</localfile>
```

Wazuh ha regole built-in per ClamAV (rule group `clam`). Quando ClamAV trova malware, l'alert appare sulla Dashboard con il nome del malware e il path del file.

---

## YARA: analisi avanzata dei file dell'honeypot

**YARA** e' il tool standard per la classificazione del malware. A differenza di ClamAV (signature-based), YARA usa regole flessibili basate su pattern, stringhe e condizioni logiche.

```bash
# Installazione
sudo apt install yara -y
```

### Regole YARA per il nostro honeypot

```bash
sudo mkdir -p /var/ossec/ruleset/yara/rules
```

Creare `/var/ossec/ruleset/yara/rules/honeypot_malware.yar`:

```yara
rule CoinMiner_Generic {
    meta:
        description = "Rileva script di mining cryptocurrency"
        author = "Homelab SOC"
        severity = "high"
    strings:
        $s1 = "stratum+tcp://" ascii    // Pool URL di mining
        $s2 = "xmrig" ascii nocase      // XMRig miner
        $s3 = "minerd" ascii            // CPU miner
        $s4 = "--donate-level" ascii    // Flag XMRig
        $s5 = "cryptonight" ascii       // Algoritmo mining Monero
    condition:
        any of them
}

rule Reverse_Shell {
    meta:
        description = "Rileva tentativi di reverse shell"
        severity = "critical"
    strings:
        $s1 = "/dev/tcp/" ascii                    // Bash reverse shell
        $s2 = "bash -i >& /dev/tcp" ascii          // Classic bash reverse shell
        $s3 = "python -c 'import socket" ascii     // Python reverse shell
        $s4 = "nc -e /bin/" ascii                   // Netcat reverse shell
        $s5 = "exec 5<>/dev/tcp/" ascii            // File descriptor reverse shell
    condition:
        any of them
}

rule SSH_Key_Theft {
    meta:
        description = "Script che tenta di rubare chiavi SSH"
        severity = "critical"
    strings:
        $s1 = ".ssh/id_rsa" ascii
        $s2 = ".ssh/authorized_keys" ascii
        $s3 = "cat /etc/shadow" ascii
        $s4 = "/root/.ssh" ascii
    condition:
        2 of them
}
```

### Scansione automatica

```bash
# Scansiona tutti i file scaricati dall'honeypot con YARA
yara -r /var/ossec/ruleset/yara/rules/ /home/pi/cowrie/downloads/

# Output esempio:
# CoinMiner_Generic /home/pi/cowrie/downloads/a1b2c3d4...
# Reverse_Shell /home/pi/cowrie/downloads/e5f6g7h8...
```

L'integrazione con Wazuh segue lo stesso pattern di ClamAV: uno script di Active Response che esegue YARA quando un nuovo file appare nella directory downloads, e il risultato viene ingestito come log.

> **Il valore combinato:** ClamAV rileva malware noto (signature match esatto). YARA rileva pattern comportamentali (anche in malware mai visto prima). Usarli insieme offre copertura sia su minacce note che sconosciute.

---

## Riepilogo: stack di detection completo

```
LIVELLO RETE          LIVELLO HOST            LIVELLO FILE
-------------         --------------          --------------
Suricata              Wazuh Agent             ClamAV
|-- IDS signatures    |-- Log analysis        |-- Signature AV
|-- Protocol anomaly  |-- FIM (syscheck)      +-- Database aggiornato
|-- DNS logging       |-- Rootcheck
|-- TLS inspection    |-- Vulnerability det.  YARA
+-- File extraction   |-- CIS Benchmark       |-- Pattern matching
                      +-- Active Response     +-- Regole custom
        |                     |                       |
        +---------------------+-----------------------+
                              v
                     Wazuh Manager (correlazione)
                              |
                              v
                     Dashboard (visualizzazione + threat hunting)
```

Ogni layer copre una superficie diversa. Wazuh da solo e' cieco sulla rete e limitato sui file. Con Suricata, ClamAV e YARA, la copertura diventa completa.
