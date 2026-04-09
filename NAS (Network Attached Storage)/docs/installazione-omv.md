# Step 3: Installazione di OpenMediaVault

## Prerequisiti

- Raspberry Pi OS **Lite** (senza Desktop). OMV blocca l'installazione su sistemi con GUI
- Sistema aggiornato (`sudo apt update && sudo apt full-upgrade -y`)

## Installazione via script ufficiale

```bash
wget -O - https://github.com/OpenMediaVault-Plugin-Developers/installScript/raw/master/install | sudo bash
```

**Cosa fa lo script:**

1. Aggiunge i repository APT di OpenMediaVault
2. Installa i pacchetti core: `openmediavault`, `openmediavault-keyring`
3. Configura i servizi di sistema: nginx (web server), PHP-FPM, monit
4. Imposta la porta 80 per la web UI
5. Crea l'utente admin con password di default

L'installazione richiede 10-20 minuti su RPi5. Non interrompere il processo.

## Accesso alla Web UI

Dopo il reboot:

```bash
http://<IP_DEL_RASPBERRY>:80
```

Credenziali di default:

| Campo | Valore |
|---|---|
| Username | `admin` |
| Password | `openmediavault` |

> **Primo passo obbligatorio:** Cambiare la password admin immediatamente. Vai su **User Settings** (icona ingranaggio in alto a destra) e aggiorna la password. Chiunque sulla tua rete locale puo' accedere alla porta 80 senza autenticazione pregressa.
