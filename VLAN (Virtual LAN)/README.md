# VLAN e IPVLAN - Segmentazione di Rete Avanzata con Docker

Questa guida documenta la configurazione di container Docker su un Raspberry Pi utilizzando il driver di rete **IPVLAN** in modalita' L2 su una **VLAN dedicata (802.1Q)**. Include la teoria necessaria per capire cosa si sta facendo e i problemi che ho incontrato nella pratica.

---

## Teoria: Perche' segmentare la rete

In un home lab di sicurezza, tutti i servizi (NAS, Honeypot, Pi-hole, SIEM) girano sullo stesso dispositivo fisico. Senza segmentazione di rete, un attaccante che compromette il container Honeypot potrebbe potenzialmente raggiungere il NAS e i dati personali.

La segmentazione di rete crea **confini logici** tra i servizi, anche se fisicamente condividono lo stesso Raspberry Pi e lo stesso cavo Ethernet.

---

## Modalita' di rete Docker a confronto

Docker offre diversi driver di rete. La scelta del driver ha impatto diretto su isolamento, visibilita' e prestazioni.

### Bridge (default)

```
[Container] ──── [Docker Bridge (172.17.0.1)] ──── NAT ──── [Rete fisica]
```

- Ogni container riceve un IP privato nella subnet interna di Docker (172.17.0.0/16)
- Il traffico verso l'esterno passa attraverso NAT (Network Address Translation)
- **Problema:** Tutti i pacchetti in uscita hanno come IP sorgente l'indirizzo del Raspberry Pi. Pi-hole non puo' distinguere quale client ha fatto la query DNS - vede solo l'IP del gateway Docker
- **Problema:** Per esporre porte, serve `-p 80:80` (port mapping) - conflitto se l'host usa gia' quella porta

### MacVLAN

```
[Container (MAC: aa:bb:cc:dd:ee:01, IP: 192.168.0.250)] ──── [Rete fisica]
[Host (MAC: 2c:cf:67:b2:47:ea, IP: 192.168.0.102)]      ──── [Rete fisica]
```

- Il container ottiene un **MAC address virtuale** e un IP sulla rete fisica
- Appare come un dispositivo fisico separato sulla LAN
- **Vantaggio:** IP dedicato, nessun NAT, nessun port mapping
- **Limitazione critica:** Per design del kernel Linux, l'host **non puo' comunicare** con i container MacVLAN sulla stessa interfaccia. Il traffico tra host e container viene droppato a livello kernel (misura anti-spoofing)

### IPVLAN (L2 mode)

```
[Container (MAC: 2c:cf:67:b2:47:ea, IP: 192.168.150.69)] ──── [Rete fisica / VLAN]
[Host (MAC: 2c:cf:67:b2:47:ea, IP: 192.168.0.102)]       ──── [Rete fisica]
```

- Il container **condivide il MAC address** dell'host ma ha un IP diverso
- Opera a Layer 2 - i frame Ethernet vengono inviati direttamente sulla rete fisica
- **Vantaggio:** Compatibile con ambienti dove le policy di sicurezza limitano il numero di MAC per porta (802.1X, port security su switch managed)
- **Stessa limitazione** di MacVLAN: host e container non comunicano direttamente

| Caratteristica | Bridge | MacVLAN | IPVLAN L2 |
|---|---|---|---|
| NAT | Si | No | No |
| IP reale su LAN | No | Si | Si |
| MAC address dedicato | No | Si (virtuale) | No (condiviso con host) |
| Host ↔ Container | Si | **No** | **No** |
| Port mapping necessario | Si | No | No |
| Visibilita' IP client | Solo IP gateway | IP reale del client | IP reale del client |
| Compatibilita' port-security | N/A | Puo' causare problemi | Compatibile |

### Deep Dive: flusso di un pacchetto in IPVLAN L2 a livello kernel

Per capire cosa succede realmente quando un container su IPVLAN L2 invia o riceve un pacchetto, bisogna scendere al livello del kernel Linux.

#### Pacchetto in uscita (container → rete fisica)

```
[Processo nel container]
    │
    ▼ write() sulla socket
[Network namespace del container]
    │
    ▼ Il kernel costruisce il frame Ethernet
[eth0@if9 - interfaccia IPVLAN slave]
    │ IP sorgente: 192.168.150.69
    │ MAC sorgente: 2c:cf:67:b2:47:ea  ← MAC dell'HOST (condiviso)
    │
    ▼ Il driver IPVLAN L2 bypassa il routing del container
[end0.150 - interfaccia VLAN parent]
    │
    ▼ Il kernel aggiunge il tag 802.1Q (VLAN ID 150)
[end0 - interfaccia fisica]
    │
    ▼ Frame Ethernet esce sul cavo
[Switch → Rete]
```

**Punto chiave**: in modalita' L2, il driver IPVLAN opera come un **bridge software**. Non passa per le tabelle di routing del container - il frame viene consegnato direttamente all'interfaccia parent. Questo e' il motivo per cui IPVLAN L2 e' piu' veloce di bridge: salta netfilter, NAT e routing.

In modalita' **L3** (non usata nel nostro setup), il driver opera come un router: il pacchetto attraversa le tabelle di routing e netfilter del container, permettendo policy piu' granulari ma con overhead maggiore.

#### Pacchetto in ingresso (rete fisica → container)

```
[Switch → Cavo Ethernet]
    │
    ▼ Frame Ethernet con tag 802.1Q VLAN 150
[end0 - interfaccia fisica]
    │
    ▼ Il kernel legge il tag: VLAN ID = 150
[end0.150 - interfaccia VLAN]
    │
    ▼ Il driver IPVLAN controlla l'IP destinazione
    │ Decisione: 192.168.150.69 appartiene a un container IPVLAN?
    │
    ├── SI → consegna al network namespace del container
    │         [eth0@if9 → processo nel container]
    │
    └── NO → consegna allo stack di rete dell'host
              (ma l'host non ha IP su end0.150, quindi il pacchetto viene scartato)
```

**Il meccanismo di dispatch**: quando un frame arriva su `end0.150`, il driver IPVLAN confronta l'IP destinazione con una tabella interna che mappa `IP → network namespace`. Se trova un match, consegna il pacchetto al namespace del container corrispondente. Se non lo trova, il pacchetto sale allo stack dell'host. Poiche' l'host non ha un indirizzo IP configurato su `end0.150`, il pacchetto viene scartato - questa e' la ragione tecnica per cui **l'host non puo' comunicare con i container IPVLAN**.

### ARP in IPVLAN vs MacVLAN: la differenza fondamentale

Il protocollo ARP (Address Resolution Protocol) risolve `IP → MAC address` sulla LAN. Il modo in cui ARP funziona e' la **differenza architetturale chiave** tra MacVLAN e IPVLAN:

**MacVLAN:**
```
Router ARP request: "Chi ha 192.168.150.69?"
    │
    ▼
Container risponde con MAC VIRTUALE: "192.168.150.69 e' aa:bb:cc:dd:ee:01"
    │
    ▼
ARP table del router: 192.168.150.69 → aa:bb:cc:dd:ee:01
ARP table del router: 192.168.0.102  → 2c:cf:67:b2:47:ea
                      (2 MAC diversi sulla stessa porta fisica)
```

**IPVLAN:**
```
Router ARP request: "Chi ha 192.168.150.69?"
    │
    ▼
Container risponde con MAC dell'HOST: "192.168.150.69 e' 2c:cf:67:b2:47:ea"
    │
    ▼
ARP table del router: 192.168.150.69 → 2c:cf:67:b2:47:ea
ARP table del router: 192.168.0.102  → 2c:cf:67:b2:47:ea
                      (stesso MAC, 2 IP diversi)
```

**Perche' conta:**

| Scenario | MacVLAN | IPVLAN |
|---|---|---|
| Switch con port security (max 1 MAC per porta) | **Bloccato** - lo switch vede 2 MAC e disabilita la porta | **Funziona** - un solo MAC visibile |
| 802.1X (autenticazione per porta) | **Bloccato** - solo il MAC autenticato passa | **Funziona** - stesso MAC autenticato |
| Wi-Fi (molti AP rifiutano MAC multipli) | **Non funziona** | **Funziona** |
| Cloud/VPS (provider filtra MAC sconosciuti) | **Non funziona** | **Funziona** |

> **Nel nostro lab**: ho scelto IPVLAN specificamente perche' alcuni switch consumer implementano una forma base di port security che limita i MAC per porta. Con IPVLAN, lo switch non nota differenze - vede sempre lo stesso MAC del Raspberry Pi, indipendentemente da quanti container girano.

---

## Teoria: VLAN Tagging (IEEE 802.1Q)

Una **VLAN (Virtual LAN)** e' una rete logica separata che condivide la stessa infrastruttura fisica. Il protocollo **IEEE 802.1Q** aggiunge un **tag** di 4 byte nell'header del frame Ethernet che identifica la VLAN di appartenenza:

```
[MAC dst] [MAC src] [802.1Q Tag: VLAN ID 150] [EtherType] [Payload] [FCS]
                     └── 4 byte inseriti ──┘
```

Il tag contiene:

- **TPID** (Tag Protocol Identifier): `0x8100` - identifica il frame come taggato
- **PCP** (Priority Code Point): 3 bit per QoS (priorita' del traffico)
- **DEI** (Drop Eligible Indicator): 1 bit
- **VID** (VLAN Identifier): 12 bit → supporta fino a 4094 VLAN (0 e 4095 riservati)

### Porte dello switch: Access vs Trunk

| Tipo porta | Comportamento | Uso tipico |
|---|---|---|
| **Access** | Trasporta traffico di una sola VLAN, senza tag | PC, stampanti, dispositivi finali |
| **Trunk** | Trasporta traffico di piu' VLAN, con tag 802.1Q | Connessioni tra switch, server multi-VLAN |

**Per il nostro setup:** La porta dello switch a cui e' collegato il Raspberry Pi deve essere configurata come **Trunk** (o con la VLAN 150 come "tagged"). Se lo switch e' **unmanaged** (non gestito), questa configurazione **non funzionera'** perche' lo switch droppera' i frame taggati.

---

## Configurazione Passo-Passo

### Step 1: Identificare l'interfaccia di rete

```bash
ip a
```

Sul Raspberry Pi 5 con Bookworm, l'interfaccia Ethernet si chiama tipicamente `end0` (non `eth0` come nei modelli precedenti):

```
2: end0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc fq_codel state UP group default qlen 1000
    link/ether 2c:cf:67:b2:47:ea brd ff:ff:ff:ff:ff:ff
    altname enx2ccf67b247ea
    inet 192.168.0.102/24 metric 100 brd 192.168.0.255 scope global end0
        valid_lft forever preferred_lft forever
```

### Step 2: Creare la sotto-interfaccia VLAN

Prima che Docker possa usare la VLAN, il kernel Linux deve sapere che esiste. Creiamo una sotto-interfaccia virtuale che "tagga" i pacchetti con VLAN ID 150:

```bash
# Crea l'interfaccia virtuale per VLAN 150
sudo ip link add link end0 name end0.150 type vlan id 150

# Attiva l'interfaccia
sudo ip link set end0.150 up
```

**Cosa succede a livello kernel:**

- `ip link add`: crea un device di rete virtuale di tipo `vlan`
- `link end0`: la sotto-interfaccia e' "figlia" dell'interfaccia fisica `end0`
- `type vlan id 150`: ogni frame in uscita da `end0.150` viene automaticamente taggato con VLAN ID 150. Ogni frame in ingresso su `end0` con tag 150 viene consegnato a `end0.150`

### Verifica

```bash
ip a
```

```
9: end0.150@end0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default qlen 1000
    link/ether 2c:cf:67:b2:47:ea brd ff:ff:ff:ff:ff:ff
    inet6 fe80::2ecf:67ff:feb2:47ea/64 scope link proto kernel_ll
        valid_lft forever preferred_lft forever
```

L'interfaccia `end0.150@end0` e' attiva. Nota che non ha un indirizzo IPv4 - non ne ha bisogno, sara' Docker a gestire gli IP dei container.

> **Persistenza:** Questa configurazione si perde al reboot. Per renderla permanente, aggiungere al file `/etc/network/interfaces.d/vlan150`:
> ```
> auto end0.150
> iface end0.150 inet manual
>     vlan-raw-device end0
> ```

### Step 3: Creare la rete Docker IPVLAN

```bash
docker network create -d ipvlan \
    --subnet=192.168.150.0/24 \
    --gateway=192.168.150.1 \
    -o parent=end0.150 \
    -o ipvlan_mode=l2 \
    ipvlan_150
```

Spiegazione di ogni parametro:

| Parametro | Significato |
|---|---|
| `-d ipvlan` | Driver di rete: IPVLAN |
| `--subnet=192.168.150.0/24` | La sottorete della VLAN 150 |
| `--gateway=192.168.150.1` | Il gateway della VLAN (deve esistere sullo switch/router) |
| `-o parent=end0.150` | **Punto critico:** collega la rete Docker alla sotto-interfaccia VLAN, NON all'interfaccia fisica |
| `-o ipvlan_mode=l2` | Modalita' Layer 2: condivide il MAC dell'host, opera come bridge diretto |

![Portainer - Lista delle reti Docker mostra la rete ipvlan_150 con subnet 192.168.150.0/24](img/portainer-network-list.jpg)

### Step 4: Test di connettivita'

Avviamo un container temporaneo per verificare che l'IP venga assegnato correttamente:

```bash
docker run -it --rm \
    --net ipvlan_150 \
    --ip 192.168.150.69 \
    --name test-vlan \
    alpine /bin/sh
```

Dentro il container:

```bash
# Verifica IP assegnato
ip a
```

```
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
        valid_lft forever preferred_lft forever

10: eth0@if9: <BROADCAST,MULTICAST,UP,LOWER_UP,M-DOWN> mtu 1500 qdisc noqueue state UNKNOWN
    link/ether 2c:cf:67:b2:47:ea brd ff:ff:ff:ff:ff:ff
    inet 192.168.150.69/24 brd 192.168.150.255 scope global eth0
        valid_lft forever preferred_lft forever
```

Il container ha l'IP `192.168.150.69` sulla VLAN 150 e condivide il MAC address dell'host (`2c:cf:67:b2:47:ea`).

```bash
# Test connettivita' verso il gateway
ping 192.168.150.1
```

![Test di connettivita' dal container Alpine sulla VLAN 150](img/ipvlan-ping-test.jpg)

Se il ping funziona, la VLAN e' configurata correttamente end-to-end (Raspberry Pi → switch → router).

#### Verifica con tcpdump: osservare i frame taggati

Per confermare che i frame escono effettivamente con il tag 802.1Q, catturare il traffico sull'interfaccia **fisica** (non sulla sotto-interfaccia VLAN):

```bash
sudo tcpdump -i end0 -e -n vlan 150
```

| Flag | Significato |
|---|---|
| `-i end0` | Cattura sull'interfaccia fisica (dove i frame sono ancora taggati) |
| `-e` | Mostra gli header Ethernet (MAC sorgente/destinazione) |
| `-n` | Non risolvere nomi DNS (piu' veloce e leggibile) |
| `vlan 150` | Filtra solo i frame con tag VLAN ID 150 |

Output durante un ping dal container:

```
14:23:01.234567 2c:cf:67:b2:47:ea > ff:ff:ff:ff:ff:ff, ethertype 802.1Q (0x8100),
    length 46: vlan 150, p 0, ethertype ARP (0x0806),
    Request who-has 192.168.150.1 tell 192.168.150.69, length 28

14:23:01.235012 aa:bb:cc:dd:ee:ff > 2c:cf:67:b2:47:ea, ethertype 802.1Q (0x8100),
    length 46: vlan 150, p 0, ethertype ARP (0x0806),
    Reply 192.168.150.1 is-at aa:bb:cc:dd:ee:ff, length 28

14:23:01.235234 2c:cf:67:b2:47:ea > aa:bb:cc:dd:ee:ff, ethertype 802.1Q (0x8100),
    length 102: vlan 150, p 0, ethertype IPv4 (0x0800),
    192.168.150.69 > 192.168.150.1: ICMP echo request, id 1, seq 1, length 64

14:23:01.236789 aa:bb:cc:dd:ee:ff > 2c:cf:67:b2:47:ea, ethertype 802.1Q (0x8100),
    length 102: vlan 150, p 0, ethertype IPv4 (0x0800),
    192.168.150.1 > 192.168.150.69: ICMP echo reply, id 1, seq 1, length 64
```

**Lettura dell'output:**

1. **Frame 1 (ARP Request)**: il container (MAC `2c:cf:67:b2:47:ea` - MAC dell'host, perche' IPVLAN) invia un broadcast ARP per risolvere il MAC del gateway `192.168.150.1`. Il campo `ethertype 802.1Q (0x8100)` conferma che il frame e' taggato, e `vlan 150` mostra il VLAN ID corretto
2. **Frame 2 (ARP Reply)**: il gateway risponde con il suo MAC (`aa:bb:cc:dd:ee:ff`)
3. **Frame 3-4 (ICMP)**: il ping vero e proprio, incapsulato in frame 802.1Q con VLAN 150

Se catturi sulla sotto-interfaccia VLAN (`-i end0.150`), i frame appaiono **senza** tag 802.1Q - il kernel li ha gia' rimossi (de-taggati) prima di consegnarli alla sotto-interfaccia. Questo e' il comportamento atteso: il tagging/de-tagging avviene tra `end0` e `end0.150`.

> **Diagnostica**: se `tcpdump -i end0 vlan 150` non mostra nulla durante il ping dal container, i frame non escono taggati. Verificare che la sotto-interfaccia `end0.150` sia UP e che la rete Docker usi `parent=end0.150` (non `parent=end0`).

### Step 5: Deploy di un container sulla VLAN (Esempio: Pi-hole)

```bash
docker run -d \
    --name pihole \
    --restart=always \
    --net ipvlan_150 \
    --ip 192.168.150.69 \
    -v /etc/pihole:/etc/pihole \
    -v /etc/dnsmasq.d:/etc/dnsmasq.d \
    --cap-add=NET_ADMIN \
    -e TZ="Europe/Rome" \
    pihole/pihole:latest
```

Oppure tramite Docker Compose (da Portainer → Stacks → Add Stack):

```yaml
services:
  pihole:
    container_name: pihole
    image: pihole/pihole:latest
    hostname: pihole
    networks:
      ipvlan_150:
        ipv4_address: 192.168.150.69
    environment:
      TZ: 'Europe/Rome'
      FTLCONF_dns_listeningMode: all
    volumes:
      - '/home/pi/pihole/etc-pihole:/etc/pihole'
      - '/home/pi/pihole/etc-dnsmasq:/etc/dnsmasq.d'
    cap_add:
      - NET_ADMIN
    restart: unless-stopped

networks:
  ipvlan_150:
    external: true
```

> **Nota:** La rete `ipvlan_150` e' dichiarata come `external: true` perche' l'abbiamo gia' creata manualmente con `docker network create`. Docker Compose non deve tentare di ricrearla.

---

## Migrazione di un container esistente dalla rete Bridge alla VLAN

Se hai gia' un container Pi-hole in esecuzione sulla rete bridge e vuoi spostarlo su IPVLAN, puoi farlo da Portainer:

1. Dalla lista container, clicca sul nome del container (`pihole`)
2. Clicca **Duplicate/Edit** nella barra in alto
3. Nella sezione **Network**:
   - Rimuovi `bridge`
   - Seleziona `ipvlan_150`
   - **Importante:** Cancella il campo **MAC Address** - Docker deve generarne uno nuovo per la nuova rete. Lasciare il vecchio MAC causa conflitti ARP
   - Nel campo **IPv4 Address**, inserisci l'IP statico (es. `192.168.150.69`)
4. Clicca **Deploy the container** e conferma con **Replace**

---

## Limitazioni e Troubleshooting

### 1. L'host non puo' comunicare con i container IPVLAN/MacVLAN

Questo e' **by design**. Il kernel Linux impedisce la comunicazione tra l'interfaccia padre e le sotto-interfacce IPVLAN/MacVLAN per motivi di sicurezza (prevenzione ARP spoofing interno).

**Conseguenza pratica:** Il Raspberry Pi (192.168.0.102) non potra' fare ping a Pi-hole (192.168.150.69). Tutti gli **altri** dispositivi sulla rete (PC, smartphone, router) potranno raggiungerlo normalmente.

**Workaround (se necessario):** Creare un'interfaccia MacVLAN sull'host collegata alla stessa rete:

```bash
sudo ip link add mvl0 link end0.150 type macvlan mode bridge
sudo ip addr add 192.168.150.100/24 dev mvl0
sudo ip link set mvl0 up
```

### 2. Il container non risponde al ping da altri dispositivi

Checklist di diagnostica:

| Verifica | Comando | Cosa cercare |
|---|---|---|
| L'interfaccia VLAN esiste? | `ip a \| grep end0.150` | Deve mostrare stato UP |
| La rete Docker esiste? | `docker network ls` | `ipvlan_150` deve essere presente |
| Il container e' sulla rete giusta? | `docker inspect pihole \| grep NetworkMode` | Deve mostrare `ipvlan_150` |
| Lo switch accetta il tag VLAN? | Verificare configurazione switch | La porta deve essere Trunk o Tagged VLAN 150 |

### 3. Switch unmanaged (non gestito)

Se il tuo switch e' un modello consumer senza interfaccia di gestione, **non supporta VLAN tagging**. I frame con tag 802.1Q verranno droppati silenziosamente o, in alcuni casi, passati ma ignorati dal dispositivo di destinazione.

**Soluzione:** Usare IPVLAN **senza** VLAN tagging (direttamente sull'interfaccia fisica `end0`):

```bash
docker network create -d ipvlan \
    --subnet=192.168.0.0/24 \
    --gateway=192.168.0.1 \
    -o parent=end0 \
    -o ipvlan_mode=l2 \
    ipvlan_flat
```

Perdi l'isolamento VLAN, ma mantieni i vantaggi di IPVLAN (IP dedicato, no NAT, visibilita' IP reale dei client).

---

Prossimo step: [VPN (Virtual Private Network)](../VPN%20(Virtual%20Private%20Network)/) - accesso remoto sicuro alla LAN.
