>  [English](troubleshooting.en.md) |  **Italiano**

# Troubleshooting - Docker & Portainer: problemi reali e soluzioni

> Problemi tipici di Docker su Raspberry Pi 5 con OpenMediaVault: conflitti di installazione, permessi del socket, immagini per l'architettura sbagliata, la trappola di rete MacVLAN e - importante per la sicurezza - il fatto che Docker scavalca UFW. Per il recovery operativo dei container (crash loop, daemon giu', ricreazione da compose) vedi [Incident Recovery / VPN e container](../../Incident%20Recovery%20%26%20Resilience/docs/vpn-e-container-recovery.md).

---

## Problema 1: Il daemon Docker non parte dopo l'installazione

**Sintomo:** `docker version` mostra solo il Client e da' errore sul Server; `systemctl status docker` risulta `failed`.

**Causa:** su un Pi con OMV, la causa piu' frequente e' un residuo di **Docker CE** (installato in passato via `get.docker.com`) che confligge con il pacchetto `docker.io` di Debian sui componenti systemd e su `containerd`.

**Soluzione:**

```bash
# Rimuovi completamente Docker CE se presente
sudo apt purge docker-ce docker-ce-cli containerd.io docker-compose-plugin docker-buildx-plugin -y
sudo apt autoremove --purge -y

# Reinstalla la versione Debian (testata e stabile con OMV)
sudo apt install docker.io docker-compose -y
sudo systemctl enable --now docker

# Se non parte ancora, leggi il perche'
sudo systemctl status docker
sudo journalctl -u docker --no-pager -n 50
```

Vedi il razionale completo `docker.io` vs `docker-ce` in [installazione](installazione.md).

---

## Problema 2: La rimozione di Docker CE sembra "bloccata"

**Sintomo:** durante `apt purge docker-ce`, la barra di avanzamento resta ferma al 5-23% per diversi minuti.

**Causa:** e' **normale**, non un blocco. `dpkg` sta fermando i container attivi, smontando i filesystem overlay e rimuovendo le regole iptables create da Docker: operazioni lente ma legittime.

**Soluzione:** non interrompere. Se vuoi verificare che stia davvero lavorando, da una seconda sessione SSH:

```bash
ps aux | grep dpkg              # dpkg e' ancora in esecuzione?
ls -l /var/lib/dpkg/lock*       # i lock esistono?
```

Se `dpkg` e' stato interrotto in modo anomalo (lock presenti ma processo assente):

```bash
sudo dpkg --configure -a
sudo apt -f install
```

---

## Problema 3: "permission denied" sul socket Docker

**Sintomo:** `docker ps` da' `permission denied while trying to connect to the Docker daemon socket`.

**Causa:** il socket (`/var/run/docker.sock`) e' accessibile solo da `root` e dal gruppo `docker`. Il tuo utente non e' nel gruppo, oppure lo e' ma la sessione corrente non ha ancora ricaricato i gruppi.

**Soluzione:**

```bash
sudo usermod -aG docker $USER
# POI: logout e login via SSH (necessario per ricaricare i gruppi)
# oppure, per la sessione corrente:
newgrp docker
```

> **Nota di sicurezza:** appartenere al gruppo `docker` equivale ad avere accesso root sull'host (chi puo' fare `docker run` puo' montare `/etc/shadow` in un container privilegiato). Non aggiungere utenti non fidati al gruppo docker.

---

## Problema 4: "exec format error" all'avvio di un container

**Sintomo:** un container non parte e i log mostrano `exec format error` o `no matching manifest for linux/arm64`.

**Causa:** stai usando un'immagine compilata per un'architettura diversa (amd64) su un Pi che e' **ARM64**. Non tutte le immagini pubblicano il tag ARM64.

**Soluzione:**

```bash
# Verifica l'architettura dell'immagine
docker image inspect <immagine> --format '{{.Architecture}}'    # deve essere arm64/aarch64

# Forza la piattaforma corretta al pull
docker pull --platform linux/arm64 <immagine>
```

Se un'immagine non ha una variante ARM64, cerca un tag `-arm64` ufficiale o un'immagine alternativa multi-arch.

---

## Problema 5: L'host non riesce a raggiungere il container Pi-hole (MacVLAN)

**Sintomo:** i dispositivi della LAN raggiungono Pi-hole a `192.168.0.250`, ma dall'host Docker un `dig @192.168.0.250` va in timeout.

**Causa:** **non e' un guasto, e' il design di MacVLAN.** Un container su rete MacVLAN e' isolato dall'host per progetto: l'host e il container non possono comunicare direttamente sulla stessa interfaccia MacVLAN, anche se tutti gli altri host della LAN ci riescono.

**Soluzione:** testa sempre Pi-hole **da un secondo dispositivo**, non dall'host. Se ti serve davvero far comunicare host e container MacVLAN, si crea una sotto-interfaccia MacVLAN dedicata sull'host - ma per il lab e' piu' semplice ricordare la regola e testare dai client. Vedi [Incident Recovery / DNS e Pi-hole, B.4](../../Incident%20Recovery%20%26%20Resilience/docs/dns-pihole-recovery.md).

---

## Problema 6: Docker scavalca UFW (le porte dei container restano esposte)

**Sintomo:** hai una regola UFW che nega una porta, ma un container che pubblica quella porta (`-p`) resta comunque raggiungibile dall'esterno.

**Causa:** e' uno dei gotcha piu' insidiosi e piu' rilevanti per la sicurezza. Docker manipola **direttamente** `iptables` (catena `DOCKER`) a un livello che scavalca le regole di UFW. Il risultato: `ufw deny` non protegge le porte pubblicate dai container. Pericoloso in un lab che espone un honeypot.

**Soluzione:**

```bash
# Vedi le regole reali che Docker ha inserito in iptables
sudo iptables -t nat -L DOCKER -n
sudo iptables -L DOCKER -n
```

Approcci corretti:
- **Non pubblicare** una porta che non deve essere raggiungibile: togli il `-p` / il mapping nel compose e usa reti Docker interne per la comunicazione container-a-container.
- Fai il **binding solo su localhost** dove serve accesso locale: `-p 127.0.0.1:9443:9443`.
- Per far rispettare UFW anche alle porte Docker, applica la soluzione nota `ufw-docker` (regole nella catena `DOCKER-USER`, che Docker valuta prima delle proprie).
- La difesa perimetrale reale resta al **router/firewall a monte**: verifica dall'esterno cosa e' davvero esposto (vedi [Incident Recovery / LAN health check, L3.5](../../Incident%20Recovery%20%26%20Resilience/docs/lan-health-check.md)).

---

## Problema 7: Lo spazio disco finisce per colpa di Docker

**Sintomo:** `/` si riempie; i container o il daemon iniziano a fallire.

**Causa:** immagini vecchie, log dei container senza tetto, cache di build che si accumulano.

**Soluzione:**

```bash
docker system df                 # dove sta lo spazio
docker image prune -a            # rimuove immagini non usate
docker builder prune             # cache di build
# Metti un tetto ai log dei container in /etc/docker/daemon.json:
#   { "log-driver":"json-file", "log-opts":{"max-size":"10m","max-file":"3"} }
sudo systemctl restart docker
```

Dettaglio completo (journald, indici Wazuh, ecc.) in [Incident Recovery / risorse e credenziali](../../Incident%20Recovery%20%26%20Resilience/docs/risorse-e-credenziali.md).

---

## Problema 8: Docker Root su NVMe non applicato

**Sintomo:** hai spostato i dati Docker sull'NVMe ma continuano a finire sulla MicroSD (`/var/lib/docker`).

**Causa:** il `data-root` in `daemon.json` non e' stato applicato, o il JSON e' malformato.

**Soluzione:**

```bash
# Verifica la config del daemon (un JSON malformato impedisce l'avvio)
sudo cat /etc/docker/daemon.json | python3 -m json.tool
# Deve contenere: { "data-root": "/mnt/nvme/docker" }

# Dopo la modifica, riavvia e verifica dove Docker scrive davvero
sudo systemctl restart docker
docker info | grep "Docker Root Dir"      # deve puntare all'NVMe
```

---

## Problema 9: Password di Portainer dimenticata

**Sintomo:** non riesci ad accedere a Portainer (`https://192.168.0.102:9443`).

**Soluzione:** reset tramite il container helper ufficiale (richiede accesso alla shell dell'host).

```bash
docker stop portainer
docker run --rm -v portainer_data:/data portainer/helper-reset-password
# Stampa una nuova password temporanea per l'admin
docker start portainer
```

Ricorda che la reset richiede l'accesso all'host: proteggilo e salva le credenziali nel password manager (vedi [Incident Recovery / risorse e credenziali, Parte D](../../Incident%20Recovery%20%26%20Resilience/docs/risorse-e-credenziali.md)).

---

## Comandi utili di verifica

```bash
# Stato del daemon e versione
sudo systemctl status docker
docker version

# Tutti i container, anche fermi/in restart loop, con exit code
docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# Log di un container
docker logs <nome> --tail 80

# Reti Docker e loro driver (bridge, macvlan, ipvlan)
docker network ls
docker network inspect <rete> --format '{{.Driver}} {{.IPAM.Config}}'
```

---

## Collegamenti

- Recovery operativo dei container (crash loop, daemon giu', ricreazione) -> [Incident Recovery / VPN e container](../../Incident%20Recovery%20%26%20Resilience/docs/vpn-e-container-recovery.md)
- Razionale `docker.io` vs `docker-ce`, permessi -> [installazione](installazione.md)
- Reset password e HTTPS Portainer -> [portainer](portainer.md)
- Sicurezza dei container (seccomp, AppArmor, capabilities) -> [sicurezza-container](sicurezza-container.md)
- Spazio disco / risorse -> [Incident Recovery / risorse e credenziali](../../Incident%20Recovery%20%26%20Resilience/docs/risorse-e-credenziali.md)
