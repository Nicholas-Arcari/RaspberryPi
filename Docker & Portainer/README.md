# Docker & Portainer su Raspberry Pi 5 con OpenMediaVault

Questa guida documenta l'installazione di Docker e Portainer su un Raspberry Pi 5 con OpenMediaVault, includendo le insidie specifiche di questa combinazione (OMV + Debian + ARM64) e le best practice per un ambiente stabile.

---

## Teoria: Perche' Docker su un NAS

Docker e' una piattaforma di containerizzazione che permette di eseguire applicazioni in ambienti isolati (container) condividendo il kernel dell'host. A differenza delle Virtual Machine, i container non emulano hardware - usano le primitive del kernel Linux per l'isolamento:

- **Namespaces**: isolano la visibilita' delle risorse. Ogni container ha il proprio albero dei processi (PID namespace), stack di rete (NET namespace), filesystem (MNT namespace) e hostname (UTS namespace). Un processo dentro un container non "vede" i processi dell'host
- **Cgroups (Control Groups)**: limitano le risorse utilizzabili. Puoi imporre a un container un tetto massimo di RAM, CPU, I/O disco. Se un container impazzisce, non puo' saturare l'intero sistema
- **Union Filesystem (OverlayFS)**: Docker sovrappone layer di filesystem in sola lettura (l'immagine) con un layer scrivibile (le modifiche del container). Questo permette a 10 container basati sulla stessa immagine di condividere i layer comuni, risparmiando spazio disco

**Perche' e' fondamentale per il nostro progetto:** OpenMediaVault gestisce il NAS. Se installassimo Wazuh, Pi-hole, Cowrie e WireGuard direttamente sull'host, i loro servizi (nginx, PHP, porte di rete) andrebbero in conflitto con quelli di OMV. Docker risolve il problema alla radice: ogni servizio vive nel suo container con il proprio stack di rete e filesystem.

---

## Step 1: Controllo iniziale

```bash
sudo apt update -y
```

Verifica che il sistema sia aggiornato e che APT funzioni correttamente. Se ci sono errori di repository, risolverli prima di procedere.

---

## Step 2: Rimozione di Docker CE (se precedentemente installato)

Se in passato hai installato Docker tramite lo script `get.docker.com`, **devi rimuoverlo** prima di installare la versione dai repository Debian. Le due installazioni confliggono su systemd, causando errori di avvio del daemon.

```bash
sudo apt purge docker-ce docker-ce-cli containerd.io docker-compose-plugin docker-buildx-plugin docker-model-plugin -y
sudo apt autoremove --purge -y
```

### Il finto "freeze" durante la rimozione

Sul Raspberry Pi, la rimozione di Docker CE puo' sembrare bloccata (la barra di avanzamento resta ferma al 5-23% per diversi minuti). Questo e' **normale**: dpkg sta fermando i container attivi, smontando i filesystem overlay e rimuovendo le regole iptables create da Docker. Non interrompere il processo.

Se sospetti che sia davvero bloccato, apri un'altra sessione SSH e verifica:

```bash
# Controlla se dpkg sta ancora lavorando
ps aux | grep dpkg

# Controlla i lock file
ls -l /var/lib/dpkg/lock*
```

Se `dpkg` non e' in esecuzione ma i lock file esistono, il processo e' stato interrotto in modo anomalo. Recupera con:

```bash
sudo dpkg --configure -a
sudo apt -f install
```

---

## Step 3: Perche' `docker.io` e NON `docker-ce`

Esistono due "distribuzioni" di Docker per Linux:

| | `docker-ce` (Docker Inc.) | `docker.io` (Debian) |
|---|---|---|
| **Fonte** | Repository ufficiale Docker | Repository Debian |
| **Installazione** | `get.docker.com` script | `apt install docker.io` |
| **Aggiornamenti** | Frequenti, a volte breaking | Allineati ai cicli Debian stable |
| **Compatibilita' OMV** | Conflitti con systemd/nginx | Testato e stabile |
| **Versione Docker Compose** | Plugin integrato (`docker compose`) | Pacchetto separato (`docker-compose`) |

**Per un Raspberry Pi con OMV, `docker.io` e' la scelta corretta.** Il pacchetto Docker CE da script talvolta installa versioni di `containerd` che confliggono con le unit systemd di OMV, causando errori di avvio dopo un reboot. Il pacchetto Debian e' piu' conservativo e si integra meglio con il sistema.

### Installazione

```bash
sudo apt update
sudo apt install docker.io docker-compose -y
sudo systemctl enable --now docker
```

Cosa fanno questi comandi:

- `docker.io`: il Docker Engine (daemon + CLI)
- `docker-compose`: il tool per definire stack multi-container via file YAML
- `systemctl enable --now`: abilita Docker all'avvio automatico E lo avvia immediatamente

---

## Step 4: Permessi utente

Per default, il socket Docker (`/var/run/docker.sock`) e' accessibile solo da `root` e dal gruppo `docker`. Per usare Docker senza `sudo`:

```bash
# Crea il gruppo docker (potrebbe gia' esistere)
sudo groupadd docker 2>/dev/null

# Aggiungi il tuo utente al gruppo
sudo usermod -aG docker $USER
```

Dopo questo comando, **esegui logout e login via SSH** (oppure `newgrp docker` per applicare il cambio nella sessione corrente).

> **Nota di sicurezza:** Aggiungere un utente al gruppo `docker` equivale a dargli accesso root sull'host. Chiunque possa eseguire `docker run` puo' montare qualsiasi directory dell'host (inclusa `/etc/shadow`) all'interno di un container privilegiato. Non aggiungere utenti non fidati al gruppo docker.

### Verifica

```bash
docker version    # Deve mostrare sia Client che Server (daemon)
docker run hello-world  # Deve scaricare l'immagine ed eseguire il container
```

Se `docker version` mostra solo il Client e da' errore sul Server, il daemon non e' in esecuzione:

```bash
sudo systemctl status docker
sudo journalctl -u docker --no-pager -n 50
```

---

## Step 5: Installazione di Portainer

**Portainer** e' una web UI per gestire Docker. Permette di creare container, gestire reti, volumi e stack (Docker Compose) da browser, senza dover usare la CLI ogni volta.

### Creazione del volume persistente

```bash
docker volume create portainer_data
```

I volumi Docker sono directory gestite da Docker (sotto `/var/lib/docker/volumes/`) che persistono anche quando il container viene eliminato. I dati di Portainer (utenti, configurazioni, stack) vengono salvati qui.

### Avvio del container

```bash
docker run -d \
  --name portainer \
  --restart=always \
  -p 8000:8000 \
  -p 9443:9443 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v portainer_data:/data \
  portainer/portainer-ce:latest
```

Spiegazione di ogni flag:

| Flag | Significato |
|---|---|
| `-d` | Detached mode - il container gira in background |
| `--name portainer` | Nome del container per riferimento |
| `--restart=always` | Il container si riavvia automaticamente dopo un crash o un reboot |
| `-p 8000:8000` | Tunnel agent - usato per connettere Portainer a Docker Engine remoti |
| `-p 9443:9443` | Web UI HTTPS - la dashboard di gestione |
| `-v /var/run/docker.sock:/var/run/docker.sock` | Monta il socket Docker dell'host nel container, dando a Portainer controllo completo su Docker |
| `-v portainer_data:/data` | Monta il volume persistente per i dati di configurazione |

> **Sulla sicurezza del Docker socket:** Montare `/var/run/docker.sock` dentro un container e' l'equivalente di dare accesso root sull'host. Portainer ne ha bisogno per gestire Docker, ma un attaccante che compromette Portainer avrebbe controllo completo sul sistema. Per questo, l'accesso a Portainer va protetto con password robusta e, idealmente, limitato via firewall alla sola rete locale.

![Portainer - Container list mostra il container Portainer in stato "running"](img/portainer-container-list.jpg)

### Accesso a Portainer

```
https://<IP_DEL_RASPBERRY>:9443
```

Al primo accesso, Portainer chiede di creare un utente admin con password. Dopo il login, selezionare **Docker → Local** come endpoint.

> **Il browser mostrera' un avviso di certificato:** Portainer genera un certificato SSL self-signed al primo avvio. Il browser non si fida di certificati non emessi da una CA riconosciuta. In un ambiente domestico, questo e' accettabile - aggiungi l'eccezione nel browser.

---

## Aggiornamento di Portainer

Portainer non si auto-aggiorna. Per aggiornare:

```bash
# 1. Scarica la nuova immagine
docker pull portainer/portainer-ce:latest

# 2. Ferma e rimuovi il container corrente
docker stop portainer
docker rm portainer

# 3. Ricrea il container con la stessa configurazione
docker run -d \
  --name portainer \
  --restart=always \
  -p 8000:8000 \
  -p 9443:9443 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v portainer_data:/data \
  portainer/portainer-ce:latest
```

Il volume `portainer_data` **non viene toccato** - tutte le configurazioni, utenti e stack sono preservati.

### Pinning della versione (consigliato per produzione)

In un ambiente di produzione, usare il tag `latest` e' rischioso: un aggiornamento automatico puo' introdurre breaking changes. Meglio fissare la versione:

```bash
docker pull portainer/portainer-ce:2.21.4
```

E usare `portainer/portainer-ce:2.21.4` nel comando `docker run` al posto di `latest`.

---

## Cosa evitare

| Errore | Perche' |
|---|---|
| Installare Docker da `get.docker.com` su OMV | Conflitti con systemd, possibili reboot loop |
| Installare Portainer come plugin OMV | I plugin OMV hanno un ciclo di aggiornamento separato e possono restare indietro rispetto alle versioni ufficiali |
| Usare `sudo` per ogni comando Docker | Indica che i permessi del gruppo non sono configurati correttamente |
| Ignorare gli spazi su disco | Docker accumula immagini vecchie, layer e container fermi - `docker system prune` periodico |

---

## Comandi di manutenzione utili

```bash
# Container in esecuzione
docker ps

# Tutti i container (inclusi quelli fermi)
docker ps -a

# Log di un container
docker logs <nome_container> --tail 100

# Utilizzo risorse in tempo reale
docker stats

# Pulizia immagini, container e volumi inutilizzati
docker system prune -a
# ATTENZIONE: rimuove tutto cio' che non e' in uso. Usare con cautela.

# Ispezionare un container (rete, volumi, env variables)
docker inspect <nome_container>
```

---

Prossimo step: [Secure your RaspberryPi](../Secure%20your%20RaspberryPi/) - hardening del sistema prima di esporre servizi.
