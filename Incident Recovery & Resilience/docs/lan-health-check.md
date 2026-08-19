>  [English](lan-health-check.en.md) |  **Italiano**

# Runbook 07 - LAN health check

> **Quando usare questo runbook:** vuoi un controllo di salute completo della rete di casa - connettivita', integrita', sicurezza - da eseguire periodicamente o quando "la rete fa cose strane". Il runbook e' strutturato per adattarsi a quattro scenari fisici: **con o senza switch gestito** e **con o senza modem/router con difesa hardware integrata**.

Si procede per livelli ISO/OSI, dal cavo all'applicazione, perche' un problema di salute basso si maschera da problema alto (vedi [Runbook 00](triage-diagnostica.md)).

---

## Matrice degli scenari

Le verifiche cambiano a seconda del tuo hardware. Individua la tua colonna:

| | **Senza switch gestito** | **Con switch gestito** |
|---|---|---|
| **Modem/router semplice** | Rete piatta, un solo dominio di broadcast. Segmentazione solo software (IPVLAN sul Pi). Difesa perimetrale minima. | VLAN 802.1Q reali possibili. Difesa perimetrale ancora software. |
| **Modem/router con difesa HW** | Firewall/IPS al gateway, ma rete interna piatta. Il gateway filtra il traffico N/S ma non quello E/W interno. | Setup piu' robusto: VLAN reali + filtraggio perimetrale hardware. Il target del progetto. |

Concetti chiave che tornano sotto:
- **Traffico Nord-Sud (N/S):** tra la LAN e Internet. Lo filtra il gateway/modem.
- **Traffico Est-Ovest (E/W):** tra dispositivi della stessa LAN. Lo filtra (se lo filtra) lo switch gestito / le VLAN, **non** il modem.

---

## Livello 1 - Fisico: link e cavo

```bash
# Sul Pi: l'interfaccia ha portante e a che velocita' negozia?
sudo ethtool end0 | grep -E "Speed|Duplex|Link detected"
# Atteso: Speed: 1000Mb/s, Duplex: Full, Link detected: yes
# Speed 100Mb/s su un link gigabit <-- cavo scadente/danneggiato o porta degradata
# Link detected: no <-- cavo staccato, porta switch morta, o problema fisico

# Errori sull'interfaccia (un cavo marginale accumula errori CRC)
ip -s link show end0 | grep -A2 RX
# Atteso: errors 0, dropped 0. Numeri che crescono <-- problema fisico L1/L2
```

> **Con PoE:** se il Pi o lo switch sono alimentati PoE, un budget PoE insufficiente causa link che cadono sotto carico. Verifica il budget dello switch.

---

## Livello 2 - Data link: switch e VLAN

### 2a. Senza switch gestito (rete piatta)

La segmentazione, se c'e', e' quella software del Pi (IPVLAN su `end0.150`). Non c'e' isolamento hardware tra le porte: tutti i dispositivi si vedono a livello L2.

```bash
# La VLAN software sul Pi e' su?
ip -br link show end0.150     # atteso: UP
# Chi c'e' nel dominio di broadcast (tutta la LAN e' un unico segmento)
ip neigh show | grep -v FAILED
```

Implicazione di sicurezza: senza switch gestito, un dispositivo compromesso sulla LAN puo' parlare con tutti gli altri (traffico E/W non filtrato). La sola difesa E/W e' l'host firewall di ciascun dispositivo. E' il motivo per cui l'hardening del singolo host conta di piu' in una rete piatta.

### 2b. Con switch gestito (VLAN 802.1Q reali)

```bash
# I tag VLAN passano davvero? Cattura frame taggati sulla trunk
sudo tcpdump -i end0 -e -n vlan 2>/dev/null | head -5
# Atteso: frame con "vlan 150" nell'header 802.1Q -> il tagging funziona end-to-end

# La sottointerfaccia taggata riceve traffico?
ip -s link show end0.150 | grep -A2 RX
```

Verifica di isolamento inter-VLAN (deve essere stagno se cosi' progettato): vedi il test in [Runbook 05, sezione 8](verifica-difese-attive.md). Su uno switch gestito, abilita **DHCP snooping** e **Dynamic ARP Inspection** se disponibili: neutralizzano rogue DHCP e ARP spoofing a livello hardware.

---

## Livello 3 - Rete: IP, gateway, DHCP

```bash
# Indirizzo, gateway e rotta di default coerenti?
ip -br addr show
ip route | grep default          # atteso: default via 192.168.0.1
ping -c3 192.168.0.1             # il gateway risponde?

# Conflitti IP (due dispositivi con lo stesso IP fanno cadere la rete a intermittenza)
sudo apt install -y arp-scan >/dev/null 2>&1
sudo arp-scan --interface=end0 --localnet | sort | uniq -d -w 17
# Un MAC che risponde per due IP, o due MAC per un IP <-- conflitto/anomalia

# Scope DHCP: quale server assegna gli IP? (deve essere solo il router)
sudo nmap --script broadcast-dhcp-discover 2>/dev/null | grep "Server Identifier"
# Piu' di un Server Identifier <-- rogue DHCP (vedi Runbook 06)
```

---

## Livello 3.5 - Il modem/router: cosa filtra davvero?

Qui entra la distinzione "con o senza difesa hardware". Un modem/router con firewall/IPS integrato filtra il traffico N/S; uno semplice fa solo NAT. Va verificato **cosa** il tuo gateway blocca davvero, non cosa promette la scatola.

```bash
# Cosa e' ESPOSTO dall'esterno? (il vero test della difesa perimetrale N/S)
# Da fuori (VPS/4G) verso il tuo IP pubblico, o con un servizio di port-scan online:
#   - devono risultare aperte SOLO le porte che hai inoltrato di proposito
#     (51820/UDP WireGuard, 2222/TCP honeypot) e nient'altro.
# Dal Pi, controlla cosa il router inoltra/espone:
curl -s https://api.ipify.org ; echo        # il tuo IP pubblico

# Il modem fa doppio NAT? (tipico quando modem e router sono due dispositivi)
traceroute -n -m 3 8.8.8.8
# Due hop in RFC1918 (es. 192.168.1.1 poi 192.168.0.1) prima di uscire <-- doppio NAT
```

Cosa verificare sul gateway, secondo il tipo:

| Tipo modem/router | Cosa DEVE filtrare | Come verificarlo |
|---|---|---|
| **Semplice (solo NAT)** | Blocca inbound non richiesto (NAT implicito). Nessun IPS. | Port scan dall'esterno: solo le porte inoltrate devono aprirsi |
| **Con difesa HW (firewall/IPS)** | Inbound + pattern malevoli + a volte filtraggio DNS/reputation | Oltre al port scan, controlla i log/dashboard del router per eventi IPS |

Punti fissi indipendenti dal tipo:
- La **UI di amministrazione del router NON deve essere raggiungibile da Internet** (solo LAN). Verifica dall'esterno che la porta 80/443 del router sia chiusa.
- Le **credenziali del router devono essere cambiate** dal default: il gateway e' il master di DNS, DHCP e port forwarding di tutta la casa.
- Se il modem ha una **DMZ**, sappi cosa ci hai messo dentro: un host in DMZ e' esposto e va trattato come il honeypot, non come la LAN fidata.

---

## Livello 4-7 - DNS, uscita, inventario

```bash
# DNS: sto usando il resolver giusto e filtra?
resolvectl status | grep "DNS Servers"           # atteso: 192.168.0.250 (Pi-hole)
dig @192.168.0.250 ads.doubleclick.net +short    # atteso: 0.0.0.0

# DNS leak: qualche dispositivo sta scavalcando il Pi-hole verso un DNS esterno?
# Sul Pi/gateway, guarda se ci sono query DNS in uscita (53) verso IP != Pi-hole
sudo tcpdump -i end0 -n 'udp port 53 and not host 192.168.0.250' 2>/dev/null | head
# Traffico DNS verso 8.8.8.8/1.1.1.1 da un client <-- quel client bypassa il sinkhole

# Inventario: chi c'e' sulla mia LAN? (confronta con l'elenco atteso)
sudo arp-scan --interface=end0 --localnet
# Un MAC/dispositivo che non riconosci <-- indaga (ospite legittimo o intruso?)

# Salute uscita Internet
ping -c5 1.1.1.1 | tail -2      # perdita pacchetti e latenza verso Internet
```

---

## Scorecard LAN

```
DATA: __________  SCENARIO: [ ]senza switch [ ]con switch  [ ]modem semplice [ ]modem HW
[ ] L1  Link 1000/full, errori 0
[ ] L2  VLAN tag verificati (se switch gestito) / dominio broadcast noto
[ ] L3  Gateway raggiungibile, nessun conflitto IP, un solo DHCP
[ ] L3.5 Dall'esterno aperte solo le porte inoltrate; UI router non esposta; credenziali router cambiate
[ ] L4  DNS = Pi-hole, sinkhole attivo, nessun DNS leak
[ ] L7  Inventario dispositivi confrontato con l'atteso; nessun MAC ignoto
```

---

## Prevenzione

- Mantieni un **inventario dei dispositivi** (MAC -> nome -> IP) come baseline: rende immediato lo spot di un intruso.
- Con switch gestito: abilita **DHCP snooping** e **Dynamic ARP Inspection**; sono le difese L2 hardware contro MITM.
- Con modem semplice: compensa la difesa perimetrale con host firewall rigorosi su ogni dispositivo (rete piatta = fiducia zero tra host).
- Forza tutti i client a usare il Pi-hole (blocca in uscita la 53 verso l'esterno sul gateway, tranne dal Pi-hole) per eliminare i DNS leak.
- Automatizza l'inventario e i check L1-L4 e falli allertare da Wazuh.

---

## Collegamenti

- Sospetto MITM/ARP/rogue DHCP in dettaglio -> [Runbook 06: integrita' post-downtime](integrita-post-downtime.md)
- Provare l'isolamento inter-VLAN -> [Runbook 05: verifica difese attive](verifica-difese-attive.md)
- Topologia di rete completa del lab -> [docs/topologia-rete](../../docs/topologia-rete.md)
- Teoria VLAN e IPVLAN -> [VLAN / teoria-vlan](../../VLAN%20(Virtual%20LAN)/docs/teoria-vlan.md)
