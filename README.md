# Raspberry Pi Server – NAS, VPN, Ad-Blocker, Honeypot, ecc...

Questo repository documenta i setup da applicare su di un Raspberry Pi utilizzato come server multifunzione, basato su **OpenMediaVault (OMV)** come sistema NAS e **Docker** per l’esecuzione di servizi aggiuntivi come VPN, ad-blocker, honeypot, e molti altri giochini simpatici.

La guida è pensata per essere riproducibile passo-passo, anche da chi parte da zero.

---

## Architettura del progetto
```bash
Raspberry Pi
│
├── OpenMediaVault (NAS principale)
│
└── Docker / Portainer
    ├── VPN (WireGuard / OpenVPN)
    ├── Ad-Blocker (Pi-hole / AdGuard Home)
    ├── Honeypot (Cowrie, Dionaea, ecc...)
    └── Altri servizi futuri
```

**Regola fondamentale:**  
OpenMediaVault rimane il sistema principale.  
Tutti i servizi aggiuntivi devono essere eseguiti tramite Docker per evitare conflitti.

---

## Requisiti hardware

- Raspberry Pi 5
- MicroSD (minimo 16 GB) con Raspberry Pi OS Lite
- NVMe SSD con adattatore compatibile USB-C / PCIe (Patriot P320 256GB SSD interno - NVMe PCle Gen 3x4 - M.2 2280)
- Alimentazione adeguata per Pi e NVMe
- Accesso via SSH da PC o terminale locale
- Cavo di rete (Ethernet) consigliato per stabilità