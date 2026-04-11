>  [English](firewall-ufw.en.md) |  **Italiano**

# Firewall con UFW e Deep Dive netfilter/iptables

**UFW (Uncomplicated Firewall)** è un frontend per `iptables` (o `nftables` su Debian 12+) che semplifica la gestione delle regole di filtraggio del traffico di rete.

---

## Come funziona a basso livello: netfilter e iptables

UFW è un'interfaccia semplificata per **iptables**, che a sua volta è il frontend userspace di **netfilter** - il framework di packet filtering integrato nel kernel Linux. Per capire perchè l'ordine delle regole UFW conta (e debuggare quando qualcosa non funziona), serve capire l'architettura sottostante.

### I 5 hook points di netfilter

Ogni pacchetto di rete che attraversa il kernel Linux passa attraverso una sequenza di **hook points** (punti di aggancio) dove le regole possono intercettarlo:

```
                                    Processo locale
                                    (SSH, Wazuh, Pi-hole)
                                         ^    |
                                         |    |
                                      INPUT  OUTPUT
                                         |    |
Pacchetto --> PREROUTING --> Routing -->--+    +---> Routing --> POSTROUTING --> Uscita
in ingresso                  decision                decision                  rete
                                |                        ^
                                |                        |
                                +------ FORWARD ---------+
                                   (pacchetti in transito,
                                    non destinati a questo host)
```

| Hook | Quando si attiva | Uso tipico |
|---|---|---|
| `PREROUTING` | Appena il pacchetto arriva, prima di qualsiasi decisione di routing | DNAT (port forwarding), modifica IP destinazione |
| `INPUT` | Dopo il routing, se il pacchetto è destinato a un processo locale | **Firewall in ingresso** - dove UFW opera principalmente |
| `FORWARD` | Se il pacchetto deve essere inoltrato a un'altra interfaccia (il host fa da router) | Firewall per traffico in transito (es. container Docker) |
| `OUTPUT` | Generato da un processo locale, prima del routing in uscita | Firewall in uscita (raramente usato) |
| `POSTROUTING` | Dopo il routing, appena prima di uscire dall'interfaccia | SNAT/MASQUERADE (usato da WireGuard per il NAT dei client VPN) |

### Le 4 tabelle di iptables

Le regole non sono tutte nello stesso "contenitore". iptables le organizza in **tabelle**, ognuna con uno scopo:

| Tabella | Scopo | Hook disponibili | Usata nel nostro progetto |
|---|---|---|---|
| `filter` | Accettare o scartare pacchetti (firewall) | INPUT, FORWARD, OUTPUT | **Si** - UFW, Fail2ban |
| `nat` | Modificare IP/porta sorgente o destinazione | PREROUTING, OUTPUT, POSTROUTING | **Si** - Docker bridge (NAT container), WireGuard (MASQUERADE) |
| `mangle` | Modificare header del pacchetto (TTL, TOS, marking) | Tutti e 5 | No (uso avanzato, QoS) |
| `raw` | Marcare pacchetti per bypassare connection tracking | PREROUTING, OUTPUT | No (uso avanzato) |

### Connection Tracking (conntrack): firewall stateful

iptables (e quindi UFW) è un **firewall stateful** - non valuta ogni pacchetto in isolamento, ma tiene traccia delle **connessioni**.

Verifica pratica - mostra le connessioni tracciate dal kernel:

```bash
sudo conntrack -L 2>/dev/null | head -5
# oppure
sudo cat /proc/net/nf_conntrack | head -5
```

Output esempio:

```
tcp  6 431999 ESTABLISHED src=192.168.0.50 dst=192.168.0.102 sport=54321 dport=22
     src=192.168.0.102 dst=192.168.0.50 sport=22 dport=54321 [ASSURED] use=1
```

Il kernel traccia lo **stato** di ogni connessione:

| Stato | Significato | Esempio |
|---|---|---|
| `NEW` | Primo pacchetto di una connessione mai vista | SYN TCP, prima query DNS UDP |
| `ESTABLISHED` | Pacchetto parte di una connessione già aperta | Pacchetti successivi al SYN-ACK |
| `RELATED` | Nuova connessione correlata a una esistente | Messaggio ICMP "port unreachable" in risposta a una connessione |
| `INVALID` | Pacchetto che non appartiene a nessuna connessione nota | Pacchetti malformati, scan TCP anomali |

**Perchè conta:** Quando UFW fa `default deny incoming`, in realtà blocca solo i pacchetti `NEW` in ingresso (nuove connessioni dall'esterno). I pacchetti `ESTABLISHED` e `RELATED` passano - altrimenti non potresti ricevere le risposte alle tue richieste (es. navigare web, fare apt update). Questo è implementato dalla regola automatica:

```
-A ufw-before-input -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
```

Puoi verificarlo:

```bash
sudo iptables -L ufw-before-input -n --line-numbers | head -10
```

### Come UFW mappa su iptables: verifica pratica

Quando scrivi `sudo ufw allow ssh`, UFW genera:

```
-A ufw-user-input -p tcp --dport 22 -j ACCEPT
```

Per vedere **tutte** le regole iptables generate da UFW:

```bash
# Mostra la chain INPUT completa (incluse le chain di UFW)
sudo iptables -L INPUT -n --line-numbers

# Mostra le regole utente di UFW
sudo iptables -L ufw-user-input -n --line-numbers
```

L'ordine delle chain nella tabella `filter`:

```
Chain INPUT:
  1. ufw-before-logging-input   <-- Log pre-regole
  2. ufw-before-input           <-- Regole automatiche (conntrack ESTABLISHED, loopback)
  3. ufw-after-input             <-- Regole automatiche post-utente
  4. ufw-after-logging-input     <-- Log post-regole
  5. ufw-reject-input            <-- Reject finale
  6. ufw-track-input             <-- Tracking

Chain ufw-before-input (regole automatiche, NON modificabili da ufw):
  1. ACCEPT conntrack RELATED,ESTABLISHED  <-- Risposte a connessioni già aperte
  2. ACCEPT loopback (127.0.0.1)           <-- Traffico locale
  3. DROP conntrack INVALID                <-- Pacchetti malformati
  4. -> ufw-user-input                     <-- Le TUE regole (ufw allow/deny)
```

Questo spiega perchè l'ordine delle regole UFW è critico e perchè `ESTABLISHED` passa sempre: la regola conntrack è **prima** delle regole utente nella chain.

---

## Configurazione base

```bash
sudo apt install ufw -y

# Policy di default: blocca tutto in ingresso, permetti tutto in uscita
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Permetti SSH (altrimenti ti chiudi fuori!)
sudo ufw allow ssh

# Attiva il firewall
sudo ufw enable
```

> **ATTENZIONE:** Esegui `sudo ufw allow ssh` PRIMA di `sudo ufw enable`. Se attivi il firewall senza permettere SSH, perderai l'accesso al Pi. L'unico modo per recuperare sarà collegare monitor e tastiera fisici, o riflashare la SD.

---

## Verifica

```bash
sudo ufw status verbose
```

Output atteso:

```
Status: active
Logging: on (low)
Default: deny (incoming), allow (outgoing), disabled (routed)

To                         Action      From
--                         ------      ----
22/tcp                     ALLOW IN    Anywhere
```

---

## Regole aggiuntive per il progetto

Man mano che aggiungi servizi, dovrai aprire porte specifiche:

```bash
# Dashboard Wazuh (HTTPS)
sudo ufw allow from 192.168.0.0/24 to any port 443

# Portainer (HTTPS)
sudo ufw allow from 192.168.0.0/24 to any port 9443

# Wazuh Agent communication
sudo ufw allow from 192.168.0.0/24 to any port 1514 proto tcp
sudo ufw allow from 192.168.0.0/24 to any port 1515 proto tcp

# Honeypot (aperto a tutti - deve essere raggiungibile dagli attaccanti)
sudo ufw allow 2222/tcp
```

> **Principio del minimo privilegio:** Apri solo le porte che servono, solo dagli IP che devono accedervi. Le porte di gestione (SSH, Portainer, Wazuh Dashboard) vanno limitate alla rete locale (`192.168.0.0/24`). Solo i servizi che devono essere esposti a Internet (Honeypot, VPN) vanno aperti a tutti.
