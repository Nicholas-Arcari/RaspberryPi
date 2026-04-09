# Installazione di Docker su Raspberry Pi 5 con OMV

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
