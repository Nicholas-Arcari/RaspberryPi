>  [English](rete-dmz.en.md) |  **Italiano**

# La sfida di rete: DMZ e Doppio NAT

## Il problema del Double NAT

Prima di configurare WireGuard, ho dovuto risolvere un problema di rete che bloccava completamente il port forwarding.

La mia connessione Internet arriva tramite un'**antenna FWA** (provider: Comeser) collegata al mio router personale (TP-Link Archer C50). Questo creava una catena:

```
Internet → [Antenna Provider (NAT #1)] → [Router TP-Link (NAT #2)] → [Raspberry Pi]
```

**Cos'è il CGNAT (Carrier-Grade NAT):** Il provider assegna alla mia antenna un IP **privato** (tipo `10.x.x.x` o `100.64.x.x`) invece di un IP pubblico. Questo significa che il mio router, pur avendo un "IP WAN", ha in realtà un IP che non è raggiungibile da Internet.

**Come l'ho scoperto:** Controllando l'IP WAN sul router, vedevo un indirizzo `192.168.x.x` - chiaramente un IP privato. Il port forwarding sul TP-Link non serviva a nulla perchè il traffico veniva bloccato a monte, sul NAT del provider.

## La soluzione: DMZ sul provider

Ho contattato l'assistenza tecnica del provider FWA e ho chiesto di mettere l'IP del mio router in **DMZ** (Demilitarized Zone), ovvero di configurare un **NAT 1:1** che inoltra tutto il traffico in ingresso direttamente al mio router, bypassando il firewall del provider.

```
Internet → [Antenna Provider (DMZ → tutto il traffico al mio router)] → [Router TP-Link] → [Raspberry Pi]
```

Dopo questa modifica, il mio router vede un IP WAN pubblico e il port forwarding funziona normalmente.

> **Nota sulla sicurezza:** Con la DMZ attiva, il router è esposto direttamente su Internet. Ho preso queste precauzioni:
> - Disabilitato la gestione remota del router (no accesso admin dall'esterno)
> - Cambiato la password admin del router con una robusta
> - Aperto solo le porte strettamente necessarie nel port forwarding
> - Monitoraggio attivo con Wazuh degli accessi al Raspberry

---

## Prerequisiti

| Requisito | Dettaglio |
|---|---|
| **Hardware** | Raspberry Pi con Raspberry Pi OS e Docker installato |
| **IP statico locale** | Assegnare un IP fisso al Pi (es. `192.168.0.102`) tramite DHCP reservation sul router |
| **DDNS** | Dominio dinamico (es. No-IP) che punta all'IP pubblico di casa |
| **Port forwarding** | Porta 51820 UDP inoltrata al Raspberry Pi |
| **IP pubblico** | O DMZ configurata sul provider (per CGNAT) |

---

## Configurazione Router

### 1. IP statico per il Raspberry Pi

Sul router (TP-Link → DHCP → Address Reservation):

- MAC Address del Raspberry Pi
- IP riservato: `192.168.0.102`

Questo garantisce che il port forwarding punti sempre all'IP corretto, anche dopo un reboot del Pi.

### 2. DDNS (Dynamic DNS)

L'IP pubblico assegnato dal provider può cambiare periodicamente (IP dinamico). Un servizio **DDNS** (Dynamic Domain Name System) associa un nome dominio fisso (es. `miodominio.ddns.net`) all'IP pubblico corrente.

Ho usato **No-IP** (https://www.noip.com):

1. Registrato un account gratuito
2. Creato un hostname (es. `miodominio.ddns.net`)
3. Configurato il client DDNS sul router (TP-Link → Dynamic DNS → No-IP)

Il router aggiorna automaticamente l'associazione dominio → IP ogni volta che l'IP pubblico cambia.

### 3. Port forwarding

Sul router (TP-Link → Forwarding → Virtual Servers):

| Campo | Valore |
|---|---|
| Service Port | 51820 |
| Internal Port | 51820 |
| IP Address | 192.168.0.102 |
| Protocol | **UDP** |

> **Perchè UDP e non TCP:** WireGuard usa esclusivamente UDP. A differenza di OpenVPN che può funzionare su TCP (port 443, per sembrare traffico HTTPS), WireGuard è progettato attorno a UDP per minimizzare la latenza. Il protocollo gestisce internamente la ritrasmissione dei pacchetti persi, senza l'overhead di TCP.
