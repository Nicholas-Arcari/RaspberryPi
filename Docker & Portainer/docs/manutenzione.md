# Manutenzione, Domande da Analista e Cosa Evitare

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

## Domande che un analista dovrebbe farsi (e risposte)

### "Se il container Docker viene compromesso, l'attaccante ha root sull'host?"

**Dipende.** Se il container gira come root (default) E ha accesso al Docker socket (`/var/run/docker.sock`), si - un attaccante puo' creare un container privilegiato che monta il filesystem dell'host.

Nel nostro setup:
- **Cowrie**: non ha il Docker socket montato. Un attaccante dentro Cowrie dovrebbe sfruttare un kernel exploit o un bug di runc per evadere
- **Portainer**: **ha** il Docker socket (necessario per gestire Docker). Se Portainer viene compromesso, l'attaccante ha root. Per questo l'accesso a Portainer e' limitato alla LAN via UFW

Mitigazioni avanzate (non implementate nel nostro lab, ma da conoscere):
```bash
# 1. Rootless Docker (il daemon gira come utente non-root)
dockerd-rootless-setuptool.sh install

# 2. User namespace remapping (root nel container = utente non-root sull'host)
# In /etc/docker/daemon.json:
# { "userns-remap": "default" }

# 3. Read-only filesystem del container
docker run --read-only --tmpfs /tmp alpine sh
```

### "Cosa succede ai dati quando un container viene eliminato?"

Tutto cio' che non e' in un **volume** o un **bind mount** viene perso. Questa e' una confusione comune:

```bash
# DATI PERSI se il container viene eliminato:
docker run alpine sh -c "echo 'test' > /data.txt"
# /data.txt vive nel layer scrivibile del container → eliminato con docker rm

# DATI PERSISTENTI:
docker run -v mydata:/data alpine sh -c "echo 'test' > /data/data.txt"
# /data/data.txt vive nel volume Docker → sopravvive a docker rm
```

Nel nostro lab, tutti i servizi usano volumi per i dati importanti:
- Portainer: `portainer_data` (utenti, configurazioni)
- Pi-hole: bind mount su `/home/pi/pihole/` (configurazione, blocklist)
- Cowrie: bind mount su `/home/pi/cowrie/log/` (log degli attaccanti)
- WireGuard: bind mount su `~/wireguard/` (chiavi, configurazioni client)

### "Docker puo' sopravvivere a un reboot senza perdere nulla?"

Si, se i container hanno `--restart=always` o `--restart=unless-stopped`. Al reboot:
1. Il daemon Docker parte (systemd enable)
2. Ripristina tutti i container con restart policy
3. I volumi sono gia' montati (sono directory su disco)
4. Le reti custom (MacVLAN, IPVLAN) vengono ricreate

**Eccezione critica:** La VLAN 150 (`end0.150`) viene persa al reboot se non resa persistente in `/etc/network/interfaces.d/`. Senza la sotto-interfaccia, la rete Docker IPVLAN non funziona e i container su quella rete non partono. Questo e' documentato nella sezione VLAN.

### "Quanto spazio disco consuma Docker nel tempo?"

Docker accumula immagini vecchie, layer orfani e container fermi:

```bash
# Mostra l'uso disco dettagliato
docker system df -v

# Output tipico dopo mesi di uso:
# TYPE          TOTAL    ACTIVE    SIZE      RECLAIMABLE
# Images        12       5         3.2GB     1.8GB (56%)
# Containers    5        5         120MB     0B
# Volumes       4        4         500MB     0B
# Build Cache   0        0         0B        0B
```

Il 56% delle immagini e' reclaimable (vecchie versioni non piu' usate). Pulizia periodica:

```bash
# Rimuovi solo cio' che e' sicuramente non usato
docker image prune -f      # Rimuove immagini dangling (senza tag)
docker container prune -f  # Rimuove container fermi

# Pulizia aggressiva (ATTENZIONE: rimuove TUTTO cio' che non e' in uso)
docker system prune -a -f
```

> **Best practice:** Schedulare `docker image prune -f` via cron settimanale. Non usare `docker system prune -a` automaticamente - potrebbe rimuovere immagini che servono per ricreare container.

---

## Cosa evitare

| Errore | Perche' |
|---|---|
| Installare Docker da `get.docker.com` su OMV | Conflitti con systemd, possibili reboot loop |
| Installare Portainer come plugin OMV | I plugin OMV hanno un ciclo di aggiornamento separato e possono restare indietro rispetto alle versioni ufficiali |
| Usare `sudo` per ogni comando Docker | Indica che i permessi del gruppo non sono configurati correttamente |
| Ignorare gli spazi su disco | Docker accumula immagini vecchie, layer e container fermi - `docker system prune` periodico |
