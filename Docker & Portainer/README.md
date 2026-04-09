# Docker & Portainer su Raspberry Pi 5 con OpenMediaVault

Questa guida documenta l'installazione di Docker e Portainer su un Raspberry Pi 5 con OpenMediaVault, includendo le insidie specifiche di questa combinazione (OMV + Debian + ARM64) e le best practice per un ambiente stabile.

---

## Perche' Docker su un NAS

OpenMediaVault gestisce il NAS. Se installassimo Wazuh, Pi-hole, Cowrie e WireGuard direttamente sull'host, i loro servizi (nginx, PHP, porte di rete) andrebbero in conflitto con quelli di OMV. Docker risolve il problema alla radice: ogni servizio vive nel suo container isolato, con il proprio stack di rete e filesystem, senza interferire con il sistema host.

I container sfruttano tre primitive del kernel Linux: **Namespaces** (isolano la visibilita' delle risorse), **Cgroups** (limitano il consumo di CPU, RAM, I/O) e **OverlayFS** (filesystem copy-on-write a layer). A differenza delle Virtual Machine, i container condividono il kernel dell'host senza emulare hardware, rendendoli leggeri e veloci.

---

## Indice

| Sezione | Contenuto |
|---|---|
| [Internals del Kernel](docs/kernel-internals.md) | Teoria: syscall `clone()`, flag dei namespace, PID namespace, cgroups v2, controller, verifiche pratiche |
| [Installazione Docker](docs/installazione.md) | Controllo iniziale, rimozione docker-ce, perche' `docker.io`, installazione, permessi utente |
| [Portainer](docs/portainer.md) | Volume persistente, avvio container, accesso web UI, aggiornamento, pinning della versione |
| [Sicurezza dei Container](docs/sicurezza-container.md) | overlay2, seccomp, AppArmor, Linux capabilities, riepilogo difesa in profondita' |
| [Alternative](docs/alternative.md) | Docker vs Podman vs LXC, Portainer vs Yacht vs Dockge, installazione Podman |
| [Manutenzione](docs/manutenzione.md) | Comandi utili, domande da analista (compromissione, persistenza dati, reboot, spazio disco), cosa evitare |

---

Prossimo step: [Secure your RaspberryPi](../Secure%20your%20RaspberryPi/) - hardening del sistema prima di esporre servizi.
