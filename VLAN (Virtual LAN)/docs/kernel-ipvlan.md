>  [English](kernel-ipvlan.en.md) |  **Italiano**

# Deep Dive: flusso di un pacchetto in IPVLAN L2 a livello kernel

Per capire cosa succede realmente quando un container su IPVLAN L2 invia o riceve un pacchetto, bisogna scendere al livello del kernel Linux.

## Pacchetto in uscita (container → rete fisica)

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

**Punto chiave**: in modalità L2, il driver IPVLAN opera come un **bridge software**. Non passa per le tabelle di routing del container - il frame viene consegnato direttamente all'interfaccia parent. Questo è il motivo per cui IPVLAN L2 è più veloce di bridge: salta netfilter, NAT e routing.

In modalità **L3** (non usata nel nostro setup), il driver opera come un router: il pacchetto attraversa le tabelle di routing e netfilter del container, permettendo policy più granulari ma con overhead maggiore.

## Pacchetto in ingresso (rete fisica → container)

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

**Il meccanismo di dispatch**: quando un frame arriva su `end0.150`, il driver IPVLAN confronta l'IP destinazione con una tabella interna che mappa `IP → network namespace`. Se trova un match, consegna il pacchetto al namespace del container corrispondente. Se non lo trova, il pacchetto sale allo stack dell'host. Poichè l'host non ha un indirizzo IP configurato su `end0.150`, il pacchetto viene scartato - questa è la ragione tecnica per cui **l'host non può comunicare con i container IPVLAN**.

## ARP in IPVLAN vs MacVLAN: la differenza fondamentale

Il protocollo ARP (Address Resolution Protocol) risolve `IP → MAC address` sulla LAN. Il modo in cui ARP funziona è la **differenza architetturale chiave** tra MacVLAN e IPVLAN:

**MacVLAN:**
```
Router ARP request: "Chi ha 192.168.150.69?"
    │
    ▼
Container risponde con MAC VIRTUALE: "192.168.150.69 è aa:bb:cc:dd:ee:01"
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
Container risponde con MAC dell'HOST: "192.168.150.69 è 2c:cf:67:b2:47:ea"
    │
    ▼
ARP table del router: 192.168.150.69 → 2c:cf:67:b2:47:ea
ARP table del router: 192.168.0.102  → 2c:cf:67:b2:47:ea
                      (stesso MAC, 2 IP diversi)
```

**Perchè conta:**

| Scenario | MacVLAN | IPVLAN |
|---|---|---|
| Switch con port security (max 1 MAC per porta) | **Bloccato** - lo switch vede 2 MAC e disabilita la porta | **Funziona** - un solo MAC visibile |
| 802.1X (autenticazione per porta) | **Bloccato** - solo il MAC autenticato passa | **Funziona** - stesso MAC autenticato |
| Wi-Fi (molti AP rifiutano MAC multipli) | **Non funziona** | **Funziona** |
| Cloud/VPS (provider filtra MAC sconosciuti) | **Non funziona** | **Funziona** |

> **Nel nostro lab**: ho scelto IPVLAN specificamente perchè alcuni switch consumer implementano una forma base di port security che limita i MAC per porta. Con IPVLAN, lo switch non nota differenze - vede sempre lo stesso MAC del Raspberry Pi, indipendentemente da quanti container girano.
