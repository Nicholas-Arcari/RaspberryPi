>  [English](threat-model.en.md) |  **Italiano**

# Threat Model: analisi STRIDE del lab

Un threat model formalizzato identifica **cosa proteggere**, **da chi**, e **come può essere attaccato** - prima che succeda. Uso il framework **STRIDE** (Microsoft), che classifica le minacce in 6 categorie.

---

## Asset da proteggere

| Asset | Valore | Impatto se compromesso |
|---|---|---|
| **Dati NAS** (foto, documenti, backup) | Alto | Perdita dati personali, violazione privacy |
| **Credenziali SSH / chiavi private** | Critico | Accesso completo all'host e a tutti i servizi |
| **Database alert Wazuh** (OpenSearch) | Medio | L'attaccante cancella le prove della sua intrusione |
| **Configurazione rete** (UFW, iptables) | Alto | L'attaccante apre porte o disabilita il firewall |
| **Container Docker** | Medio | Lateral movement se il container viene usato come pivot |
| **Rete domestica** (altri dispositivi) | Alto | L'attaccante raggiunge PC, telefoni, smart TV |

---

## Superficie d'attacco

```
                        INTERNET
                           |
           +---------------+---------------+
           v               v               v
      :2222/TCP       :51820/UDP      Ngrok tunnel
      (Honeypot)      (WireGuard)     (fallback)
      ESPOSTA         ESPOSTA         ESPOSTA
           |               |               |
           +-------+-------+               |
                   v                       |
              Raspberry Pi                 |
           +-------------------------------+
           |
    +------+------------------------------+
    |      v                              |
    |  :22 (SSH)     SOLO LAN             |
    |  :80 (OMV)     SOLO LAN             |
    |  :443 (Wazuh)  SOLO LAN             |
    |  :9200 (Index) SOLO LAN             |
    |  :9443 (Port.) SOLO LAN             |
    +-----------    ----------------------+
```

Porte esposte a Internet: **solo 2** (Honeypot e WireGuard). Tutto il resto è accessibile solo dalla LAN.

---

## Attaccanti probabili

| Tipo | Motivazione | Capacità | Probabilità |
|---|---|---|---|
| **Bot automatici** (Mirai, scanner SSH) | Aggiungere il Pi a una botnet | Bassa (credenziali comuni, exploit noti) | **Altissima** (24/7, migliaia al giorno) |
| **Script kiddie** | Curiosità, vandalismo | Bassa-Media (tool preconfigurati) | Media |
| **Attaccante mirato** | Accesso ai dati del NAS | Media-Alta (exploit custom, persistence) | Bassa (home lab, non high-value target) |
| **Insider** (chiunque sulla LAN) | Accesso non autorizzato | Alta (già dentro la rete) | Bassa (ambiente domestico) |

---

## Analisi STRIDE per componente

**STRIDE** classifica le minacce in:
- **S**poofing (impersonare un'identità)
- **T**ampering (modificare dati o codice)
- **R**epudiation (negare di aver compiuto un'azione)
- **I**nformation Disclosure (esporre informazioni riservate)
- **D**enial of Service (rendere il servizio indisponibile)
- **E**levation of Privilege (ottenere permessi non autorizzati)

### Cowrie Honeypot (esposto a Internet)

| Minaccia | Categoria | Scenario concreto | Mitigazione |
|---|---|---|---|
| Container escape | **E** | L'attaccante sfrutta una CVE di runc (es. CVE-2019-5736) per uscire dal container e ottenere root sull'host | Docker aggiornato, container non privilegiato, no Docker socket montato, seccomp + AppArmor attivi |
| Pivot verso LAN | **E** | Dopo il container escape, l'attaccante scansiona la rete locale | UFW: deny outbound verso 192.168.0.0/24 (tranne gateway), VLAN segmentation |
| DoS via flood | **D** | Migliaia di connessioni simultanee esauriscono le risorse del container | Cgroup memory/pids limits, rate limiting su UFW |
| Fingerprinting | **I** | L'attaccante identifica Cowrie dal banner SSH (versione OpenSSH troppo vecchia) e lo evita | Configurare `ssh_version_string` in `cowrie.cfg` con versione plausibile |

### WireGuard VPN (esposto a Internet)

| Minaccia | Categoria | Scenario concreto | Mitigazione |
|---|---|---|---|
| Chiave privata compromessa | **S** | Se qualcuno ruba la chiave privata di un client, può impersonare quel client VPN | Chiavi salvate solo sul dispositivo, revoca immediata dalla Web UI wg-easy |
| Brute force chiave | **S** | Tentare di indovinare la chiave Curve25519 | Impossibile: 2^128 combinazioni, non c'è negoziazione (il server ignora pacchetti con chiave sbagliata silenziosamente) |
| Credential stuffing Web UI | **E** | Brute force sulla porta 51821 (Web UI di gestione) | Web UI accessibile solo dalla LAN (UFW), password robusta |
| Replay attack | **T** | Catturare e riprodurre pacchetti VPN | WireGuard usa nonce counter monotonicamente crescente: replay vengono scartati |

### Wazuh SIEM (solo LAN)

| Minaccia | Categoria | Scenario concreto | Mitigazione |
|---|---|---|---|
| Alert tampering | **T** | L'attaccante modifica o cancella gli alert per nascondere la sua attività | Accesso Dashboard solo dalla LAN, credenziali robuste, FIM su `/var/ossec/logs/` |
| API abuse | **E** | Accesso non autorizzato all'API Wazuh (porta 55000) per registrare agent fasulli | UFW: porta 55000 solo dalla LAN, autenticazione API con token |
| Information disclosure | **I** | Gli alert contengono password honeypot, IP interni, configurazioni - se leggibili dall'esterno | Porta 9200 (OpenSearch) non esposta a Internet, TLS per tutte le comunicazioni |
| Log injection | **T** | Un agent compromesso invia log falsi al Manager per generare falsi positivi | mTLS: solo agent con certificato firmato dalla stessa CA possono comunicare |

### NAS / OpenMediaVault (solo LAN)

| Minaccia | Categoria | Scenario concreto | Mitigazione |
|---|---|---|---|
| Data exfiltration | **I** | Dopo un container escape, l'attaccante monta le share SMB e ruba i dati | Container senza accesso ai volumi NAS, SMB con autenticazione, ACL restrittivi |
| Ransomware | **T** | Un malware cifra i file sulle condivisioni di rete | Backup offline periodici (non accessibili via rete), permessi di sola lettura dove possibile |
| Default credentials | **S** | Le credenziali OMV default (`admin/openmediavault`) non sono state cambiate | Cambiare al primo accesso (documentato nella sezione NAS) |

---

## Rischi residui accettati

Nessun sistema è sicuro al 100%. Questi sono i rischi che ho consapevolmente accettato:

| Rischio residuo | Perchè lo accetto | Mitigazione parziale |
|---|---|---|
| Kernel exploit = container escape | Impossibile da eliminare senza VM (overhead eccessivo per RPi) | Kernel aggiornato, seccomp, AppArmor |
| Ngrok tunnel = terza parte | Il traffico dell'honeypot transita per i server Ngrok | Nessun dato sensibile transita (solo sessioni honeypot) |
| Self-signed certificates | Non validati da una CA esterna | Accettabile in ambiente domestico, tutti i componenti sullo stesso host |
| Single point of failure | Un solo Pi per tutti i servizi | Backup periodici, MicroSD come recovery boot |
