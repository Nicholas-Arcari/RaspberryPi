# Fase 4-6: Remediation - Blindare la rete

## Fase 4: Firewall con UFW

### Abbandonare la DMZ

Ho disabilitato la DMZ sul router e configurato un firewall interno (UFW) per creare una "gabbia" di rete sul Raspberry Pi.

### L'errore dell'ordine delle regole (lezione dolorosa)

Nel primo tentativo di isolare il Raspberry, ho bloccato tutto il traffico verso la rete locale:

```bash
sudo ufw deny out from any to 192.168.0.0/24
```

**Risultato:** Ho tagliato fuori il Raspberry da Internet. Non poteva piu' raggiungere il router/gateway (`192.168.0.1`) per scaricare aggiornamenti o risolvere DNS.

**La spiegazione tecnica:** UFW (e iptables sotto il cofano) valuta le regole **nell'ordine in cui sono state inserite**. La prima regola che fa match decide il destino del pacchetto. Bloccando `192.168.0.0/24`, ho bloccato anche `192.168.0.1` (il gateway) perche' fa parte di quella subnet.

### L'ordine corretto (PRIMA il gateway, POI il blocco)

```bash
# 1. Policy di default: blocca tutto in ingresso
sudo ufw default deny incoming

# 2. ORDINE CRITICO per il traffico in uscita:
#    Prima PERMETTI il gateway (altrimenti non hai Internet)
sudo ufw allow out from any to 192.168.0.1

#    Poi BLOCCA il resto della LAN (impedisce lateral movement)
sudo ufw deny out from any to 192.168.0.0/24

# 3. Permessi in ingresso selettivi (solo dalla LAN locale)
sudo ufw allow from 192.168.0.0/24 to any port 22    # SSH amministrativo
sudo ufw allow from 192.168.0.0/24 to any port 443   # Wazuh Dashboard
```

**Come iptables interpreta queste regole:**

```
Chain OUTPUT:
  Rule 1: -d 192.168.0.1 -> ACCEPT    <-- Il gateway passa (e' la prima regola)
  Rule 2: -d 192.168.0.0/24 -> REJECT  <-- Tutto il resto della LAN viene bloccato
  Rule 3: (default policy: ACCEPT)     <-- Internet (fuori dalla LAN) funziona normalmente
```

Il pacchetto verso `192.168.0.1` fa match sulla Rule 1 e viene accettato. Un pacchetto verso `192.168.0.50` (un PC della LAN) non fa match sulla Rule 1, fa match sulla Rule 2 e viene bloccato.

---

## Fase 5: Il mistero dell'agente "Disconnected"

### Il problema

Dopo aver configurato UFW con `default deny incoming`, ho notato sulla Dashboard che l'agente Wazuh installato sulla mia macchina Kali risultava "Disconnected", anche se la macchina era accesa e sulla stessa rete.

### La causa

Nella foga di chiudere tutte le porte, avevo bloccato anche le porte di comunicazione Wazuh:

- **Porta 1514/TCP**: canale per gli eventi (gli agenti inviano i log al Manager)
- **Porta 1515/TCP**: canale per la registrazione (enrollment di nuovi agenti)

### La soluzione

```bash
sudo ufw allow from 192.168.0.0/24 to any port 1514 proto tcp  # Canale eventi
sudo ufw allow from 192.168.0.0/24 to any port 1515 proto tcp  # Canale registrazione
```

Limitando l'accesso alla rete locale (`192.168.0.0/24`), solo gli agenti sulla mia LAN possono comunicare con il Manager. Un attaccante da Internet non puo' registrare agenti fasulli o inviare eventi manipolati.

---

## Fase 6: Esposizione su Internet - CGNAT e Ngrok

### Il problema del Double NAT

Quando ho provato ad esporre l'Honeypot su Internet usando il Port Forwarding del router, non funzionava.

**Diagnosi:** Controllando l'IP WAN del router, ho scoperto che era un indirizzo privato (`192.168.x.x`). Il mio provider Internet (connessione FWA con antenna) mi collocava dietro un **CGNAT (Carrier-Grade NAT)**: un livello aggiuntivo di NAT gestito dal provider.

```
Internet -> [CGNAT Provider (IP privato)] -> [Router TP-Link (IP privato)] -> [Raspberry Pi]
            ^ Qui si blocca il port forwarding
```

In un CGNAT, il mio router non ha un IP pubblico - ha un IP privato assegnato dall'antenna. Anche configurando perfettamente il port forwarding sul TP-Link, il traffico da Internet non raggiunge mai il mio router perche' il NAT del provider lo blocca.

### La soluzione: Ngrok (tunneling)

**Ngrok** crea un tunnel inverso: il Raspberry Pi si connette a un server Ngrok (in uscita - quindi funziona anche dietro CGNAT), e Ngrok assegna un indirizzo pubblico temporaneo che inoltra il traffico al tunnel.

```
Internet -> [Server Ngrok (0.tcp.eu.ngrok.io:xxxxx)] <-- tunnel TCP <-- [Raspberry Pi porta 2222]
```

#### Installazione e utilizzo

```bash
# Installazione
sudo apt install screen -y

# Avviare una sessione persistente con screen
screen

# Avviare il tunnel Ngrok sulla porta dell'Honeypot
ngrok tcp 2222
```

**Perche' `screen`:** Ngrok e' un processo foreground - se chiudi il terminale SSH, Ngrok muore e il tunnel cade. `screen` crea una sessione terminale persistente che continua a girare anche dopo il logout.

- **Detach (uscire senza chiudere):** `CTRL+A` poi `D`
- **Riattaccarsi alla sessione:** `screen -r`

#### Limitazioni del free plan

- L'indirizzo pubblico (es. `0.tcp.eu.ngrok.io:12345`) e la porta **cambiano ad ogni riavvio** del tunnel
- Nessun dominio fisso (richiede piano a pagamento)
- Se il Raspberry si riavvia, bisogna rientrare in screen e riavviare Ngrok manualmente

---

## Riepilogo delle vulnerabilita' trovate e corrette

| # | Vulnerabilita' | Rischio | Soluzione |
|---|---|---|---|
| 1 | DMZ attiva - tutte le porte esposte su Internet | Critico | Rimossa DMZ, configurato port forwarding selettivo |
| 2 | SSH reale (porta 22) esposto su Internet | Critico | UFW: SSH permesso solo dalla LAN |
| 3 | Wazuh Dashboard/API esposti su Internet | Alto | UFW: porte 443/55000/9200 permesse solo dalla LAN |
| 4 | Nessun isolamento di rete del container Honeypot | Alto | UFW: bloccato traffico outbound verso la LAN (tranne gateway) |
| 5 | Porte Wazuh Agent bloccate | Medio | UFW: aperte porte 1514/1515 dalla LAN |
| 6 | CGNAT impedisce port forwarding | N/A (architettura) | Ngrok tunnel come soluzione alternativa |
