>  [English](troubleshooting.en.md) |  **Italiano**

# Troubleshooting - Security Assessment: problemi reali e soluzioni

> Problemi che sorgono quando il **test stesso** non funziona o produce risultati fuorvianti: scan che mostrano porte sbagliate, il honeypot che falsa il brute force, Fail2ban che banna il tuo IP di test, l'attacco che non genera l'alert atteso, il CGNAT che impedisce il test esterno. E' il troubleshooting del red teaming del proprio lab.

> **Nota etica e di autorizzazione:** tutte le tecniche qui descritte vanno usate **solo** contro il proprio lab, dispositivi di tua proprieta'. E' un self-assessment autorizzato. Mai contro sistemi o reti di terzi.

---

## Problema 1: Nmap mostra risultati fuorvianti (host "down" o porte "filtered")

**Sintomo:** Nmap segnala l'host come down, o tutte le porte come `filtered`, anche se sai che i servizi sono attivi.

**Causa:** tre cause tipiche. (1) Lo scan SYN (`-sS`) richiede privilegi **root**. (2) Il firewall droppa i probe ICMP e Nmap conclude che l'host e' down. (3) Il rate-limiting/deny di UFW fa apparire porte aperte come `filtered`.

**Soluzione:**

```bash
# SYN scan + version detection, saltando il ping discovery (-Pn), con privilegi
sudo nmap -sS -sV -Pn 192.168.0.102
#   -sS  : SYN scan (serve root)
#   -sV  : version detection sui servizi
#   -Pn  : NON fare host discovery ICMP (l'host e' considerato up a prescindere)

# Se una porta risulta "filtered" e' un buon segno: il firewall la sta droppando come deve.
# Confronta con la superficie attesa (solo le porte inoltrate viste da FUORI).
```

Il razionale dello scan e l'analisi riga per riga sono in [reconnaissance](reconnaissance.md).

---

## Problema 2: Il brute force "riesce" contro qualsiasi password (falso positivo)

**Sintomo:** lanci Hydra sulla porta 2222 e sembra che TUTTE le credenziali funzionino: brute force apparentemente riuscito.

**Causa:** **non stai colpendo l'SSH reale, ma il honeypot Cowrie** (porta 2222/2223). Cowrie accetta di proposito credenziali comuni per registrare l'attaccante. Un "successo" li' non e' una falla: e' la trappola che funziona.

**Soluzione:** distingui sempre il bersaglio.

```bash
# 22  = SSH REALE (hardened: solo chiave, no password, no root)  -> deve RESISTERE
# 2222= Cowrie honeypot (finge di cedere)                        -> "successo" atteso e voluto

# Verifica che l'SSH reale (22) resista al brute force di password:
hydra -l pi -P lista-password.txt ssh://192.168.0.102 -t 4
#   Atteso: NESSUN successo (password auth disabilitata). Un successo qui = falla vera.
```

Il razionale (Hydra, honeypot vs servizio reale, rischio pivot) e' in [exploitation](exploitation.md).

---

## Problema 3: Fail2ban banna il MIO IP durante il test di brute force

**Sintomo:** dopo pochi tentativi, Hydra si blocca e non raggiungi piu' l'host: ti sei auto-bannato.

**Causa:** il brute force di test ha superato `maxretry` e Fail2ban ha bannato il tuo IP - esattamente cio' che deve fare con un attaccante. Ma durante un test autorizzato e' un self-DoS.

**Soluzione:**

```bash
# Durante il test, esenta temporaneamente il tuo IP (poi RIMUOVI l'esenzione)
sudo fail2ban-client set sshd unbanip 192.168.0.50
# oppure aggiungi il tuo IP a ignoreip in jail.local solo per la durata del test

# A test finito, ripristina la protezione piena e verifica che il ban scatti DAVVERO
# contro un IP non esente (e' il test positivo del Runbook 05).
```

> Questo e' anche un risultato dell'assessment: aver confermato che Fail2ban banna sotto brute force e' una difesa validata, non un intoppo. Vedi [Incident Recovery / verifica difese, sez.2](../../Incident%20Recovery%20%26%20Resilience/docs/verifica-difese-attive.md).

---

## Problema 4: L'attacco di test NON ha generato l'alert Wazuh atteso

**Sintomo:** hai eseguito un attacco (scan, brute force, intrusione honeypot) ma nella dashboard Wazuh non compare l'alert corrispondente. E' il risultato piu' importante da non ignorare: un **detection gap**.

**Causa:** il log dell'evento non arriva al manager, nessun decoder/regola lo interpreta, o l'agent e' disconnesso.

**Soluzione:**

```bash
# 1. L'agent che avrebbe dovuto vedere l'evento e' connesso?
sudo /var/ossec/bin/agent_control -l

# 2. L'evento produce un alert se lo si dà in pasto al motore di regole?
sudo /var/ossec/bin/wazuh-logtest      # incolla una riga di log reale dell'attacco
```

Un detection gap scoperto durante l'assessment e' un finding prezioso: significa che quell'attacco, se reale, passerebbe inosservato. La diagnosi decoder/regola completa e' in [SOC Analyst / troubleshooting, Problema 3](../../SOC%20Analyst/docs/troubleshooting.md); la correlazione end-to-end attesa e' in [correlazione-eventi](correlazione-eventi.md).

---

## Problema 5: L'agent Wazuh si e' disconnesso durante il test

**Sintomo:** durante l'assessment, gli eventi smettono di arrivare al SIEM; l'agent risulta `Disconnected`.

**Causa:** il tuo stesso test (o una regola firewall applicata durante la remediation) ha interrotto la connessione agent-manager (porte 1514/1515), oppure l'agent e' andato in errore.

**Soluzione:**

```bash
sudo /var/ossec/bin/agent_control -l           # stato di tutti gli agent
# Sull'agent: verifica connettivita' verso il manager
sudo /var/ossec/bin/agent_control -i <id>
# Assicurati che UFW consenta 1514/1515 tra agent e manager
sudo ufw status | grep -E "1514|1515"
sudo systemctl restart wazuh-agent
```

> Attenzione all'ordine delle regole UFW durante la remediation: una `deny` troppo ampia puo' tagliare fuori l'agent dal manager. E' un caso documentato di "agent disconnesso" in [remediation](remediation.md).

---

## Problema 6: Non riesco a testare dall'esterno (CGNAT)

**Sintomo:** vuoi simulare un attaccante da Internet, ma dall'esterno non raggiungi nessun servizio, nemmeno quelli inoltrati.

**Causa:** l'uplink FWA e' dietro **CGNAT**: non hai un IP pubblico instradabile, quindi un test "da fuori" verso il tuo IP non arriva. Non e' un problema del lab, e' l'architettura del provider.

**Soluzione:** per un test esterno realistico serve un canale in uscita:

```bash
# Esporre temporaneamente il servizio da testare via un tunnel in uscita (es. Ngrok),
# lanciare il test contro l'endpoint del tunnel, poi CHIUDERE il tunnel.
# In alternativa, test dall'interno della LAN accettando che non replica la vista esterna.
```

Il contesto CGNAT + Ngrok per l'esposizione controllata e' in [remediation](remediation.md) e nel runbook [Incident Recovery / VPN e container, A.3](../../Incident%20Recovery%20%26%20Resilience/docs/vpn-e-container-recovery.md).

---

## Problema 7: Una regola di remediation UFW non ha l'effetto voluto

**Sintomo:** dopo aver corretto una vulnerabilita' con una regola UFW, il servizio resta raggiungibile o, peggio, si e' rotto qualcos'altro.

**Causa:** l'**ordine** delle regole UFW e' critico: la prima che matcha vince. Una `allow` generica prima di una `deny` specifica annulla la seconda.

**Soluzione:**

```bash
sudo ufw status numbered           # ordine di valutazione reale
sudo ufw insert 1 deny from <IP>   # inserisci nella posizione corretta
```

Dettaglio dell'ordine critico delle regole e tabella delle vulnerabilita' corrette in [remediation](remediation.md); il mapping UFW/netfilter in [Secure your RaspberryPi / firewall-ufw](../../Secure%20your%20RaspberryPi/docs/firewall-ufw.md).

---

## Comandi utili di verifica

```bash
# Superficie di attacco reale (esegui da un SECONDO host della LAN)
sudo nmap -sS -sV -Pn 192.168.0.102

# L'SSH reale resiste al brute force di password?
hydra -l pi -P /usr/share/wordlists/rockyou.txt ssh://192.168.0.102 -t 4   # atteso: 0 successi

# L'attacco genera l'alert atteso?
sudo /var/ossec/bin/wazuh-logtest
sudo tail -f /var/ossec/logs/alerts/alerts.json
```

---

## Collegamenti

- Diagnosi del detection gap (decoder/regole) -> [SOC Analyst / troubleshooting](../../SOC%20Analyst/docs/troubleshooting.md)
- Validare attivamente le difese (firewall, Fail2ban, FIM) -> [Incident Recovery / verifica difese attive](../../Incident%20Recovery%20%26%20Resilience/docs/verifica-difese-attive.md)
- Scan e reconnaissance -> [reconnaissance](reconnaissance.md); exploitation -> [exploitation](exploitation.md); remediation -> [remediation](remediation.md)
- Correlazione eventi e test end-to-end -> [correlazione-eventi](correlazione-eventi.md); modello STRIDE -> [threat-model](threat-model.md)
