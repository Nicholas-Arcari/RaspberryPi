# VLAN e IPVLAN - Segmentazione di Rete Avanzata con Docker

Questa guida documenta la configurazione di container Docker su un Raspberry Pi utilizzando il driver di rete **IPVLAN** in modalita' L2 su una **VLAN dedicata (802.1Q)**. Include la teoria necessaria per capire cosa si sta facendo e i problemi che ho incontrato nella pratica.

---

## Indice

| Sezione | Contenuto |
|---|---|
| [Teoria VLAN](docs/teoria-vlan.md) | Perche' segmentare la rete, VLAN tagging (IEEE 802.1Q), porte Access vs Trunk |
| [Driver di rete Docker](docs/driver-docker.md) | Confronto tra Bridge, MacVLAN e IPVLAN (L2 mode) con tabella comparativa |
| [Kernel IPVLAN](docs/kernel-ipvlan.md) | Deep dive: flusso dei pacchetti a livello kernel (uscita e ingresso), ARP in IPVLAN vs MacVLAN |
| [Installazione](docs/installazione.md) | Guida passo-passo: interfaccia VLAN, rete Docker IPVLAN, test di connettivita', tcpdump, deploy Pi-hole, migrazione da bridge |
| [Troubleshooting](docs/troubleshooting.md) | Limitazioni note: comunicazione host-container, container non raggiungibile, switch unmanaged |

---

Prossimo step: [VPN (Virtual Private Network)](../VPN%20(Virtual%20Private%20Network)/) - accesso remoto sicuro alla LAN.
