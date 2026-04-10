# Suricata IDS/IPS: la componente che manca a Wazuh

Wazuh e' eccellente nell'analisi dei log (host-based detection), ma e' cieco sul **traffico di rete**. Non vede pacchetti malformati, exploit di rete, comunicazioni C2 (Command & Control), o DNS tunneling - vede solo cio' che i log applicativi riportano.

**Suricata** e' un Network IDS/IPS open-source che analizza il traffico in tempo reale con regole signature-based. L'abbinamento Wazuh + Suricata e' lo standard de facto per un SOC completo:

```
Traffico di rete --> [Suricata] --> eve.json --> [Wazuh Agent] --> [Manager] --> Dashboard
                      |                           (log_format: json)
                      | Analizza:
                      |-- Signature matching (regole ET Open)
                      |-- Protocol anomaly detection
                      |-- TLS/SSL inspection
                      |-- DNS query logging
                      |-- HTTP request logging
                      +-- File extraction (MD5/SHA256)
```

---

## Cosa rileva Suricata che Wazuh da solo non vede

| Minaccia | Wazuh (senza Suricata) | Wazuh + Suricata |
|---|---|---|
| Nmap SYN scan | Vede solo i log UFW (post-firewall) | Rileva la scansione dal pattern dei pacchetti (SID:2100001) |
| Exploit di rete (EternalBlue, Log4Shell) | Non rileva (nessun log applicativo) | Rileva la signature nell'exploit payload |
| Comunicazione C2 (beacon, reverse shell) | Non rileva (il traffico esce su porte legittime) | Rileva pattern C2 noti (Cobalt Strike, Metasploit) |
| DNS tunneling (data exfiltration) | Non rileva (Pi-hole vede la query, non il payload) | Rileva query DNS anomale (lunghezza, entropia, frequenza) |
| Download malware (HTTP) | Non rileva (Cowrie cattura i file, ma sul traffico reale?) | Rileva hash/signature del file nel traffico |
| Brute force SSH | **Si** (da auth.log) | **Si** (anche dal traffico, come backup) |

---

## Installazione su Raspberry Pi

```bash
# Suricata e' nei repository Debian
sudo apt install suricata suricata-oinkmaster -y

# Verifica versione
suricata --build-info | head -5
```

---

## Configurazione base (`/etc/suricata/suricata.yaml`)

```yaml
# Interfaccia da monitorare (la stessa del Pi)
af-packet:
  - interface: end0
    cluster-id: 99
    cluster-type: cluster_flow    # Bilanciamento per flusso (non per pacchetto)
    defrag: yes

# Rete da proteggere (HOME_NET)
vars:
  address-groups:
    HOME_NET: "[192.168.0.0/24, 192.168.150.0/24, 10.8.0.0/24]"
    EXTERNAL_NET: "!$HOME_NET"

# Output in formato JSON (compatibile con Wazuh)
outputs:
  - eve-log:
      enabled: yes
      filetype: regular
      filename: /var/log/suricata/eve.json
      types:
        - alert                    # Alert quando una regola matcha
        - dns                      # Tutte le query DNS (utile per threat hunting)
        - http                     # Tutte le request HTTP (URL, user-agent, referer)
        - tls                      # Handshake TLS (SNI, certificato, JA3 fingerprint)
        - files                    # File estratti dal traffico (con hash)
```

---

## Regole: Emerging Threats Open (ET Open)

```bash
# Aggiorna le regole ET Open (gratuite, aggiornate quotidianamente)
sudo suricata-update

# Le regole vengono scaricate in /var/lib/suricata/rules/suricata.rules
# Contengono ~40.000+ signature per:
# - Malware noti (trojan, ransomware, coinminer)
# - Exploit (CVE specifiche)
# - C2 communication (Cobalt Strike, Metasploit, etc.)
# - Policy violations (torrent, VPN non autorizzate)
# - Scan e reconnaissance

# Avvia Suricata
sudo systemctl enable --now suricata
```

---

## Integrazione con Wazuh

Sul **Manager**, aggiungere Suricata come sorgente di log in `/var/ossec/etc/ossec.conf`:

```xml
<!-- Log Suricata (formato JSON come Cowrie) -->
<localfile>
  <log_format>json</log_format>
  <location>/var/log/suricata/eve.json</location>
</localfile>
```

Wazuh ha gia' **regole built-in per Suricata** (rule group `suricata`). Dopo il restart del Manager, gli alert Suricata appariranno automaticamente sulla Dashboard con il mapping MITRE ATT&CK.

Esempio di alert correlato sulla Dashboard:

```
[Suricata] ET MALWARE Win32/Emotet CnC Activity (rule 2025636, severity 1)
    src_ip: 192.168.0.50  dst_ip: 185.X.X.X  dst_port: 443
    + [Wazuh FIM] File modified: /usr/bin/curl (hash changed)
    + [Wazuh] Anomalous outbound connection from 192.168.0.50
    = Possibile compromissione del PC Windows con Emotet
```

> **Nota sulle risorse:** Suricata su Raspberry Pi 5 funziona, ma con limitazioni. Su una LAN gigabit saturata, Suricata potrebbe droppare pacchetti. Per il nostro uso (traffico domestico, ~10-50 Mbps), e' piu' che sufficiente. Monitorare con `suricata -c /etc/suricata/suricata.yaml --dump-config | grep "detect.profile"` e `sudo suricatasc -c "dump-counters"`.
