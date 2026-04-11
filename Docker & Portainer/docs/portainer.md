>  [English](portainer.en.md) |  **Italiano**

# Portainer: Installazione, Accesso e Aggiornamento

**Portainer** è una web UI per gestire Docker. Permette di creare container, gestire reti, volumi e stack (Docker Compose) da browser, senza dover usare la CLI ogni volta.

## Creazione del volume persistente

```bash
docker volume create portainer_data
```

I volumi Docker sono directory gestite da Docker (sotto `/var/lib/docker/volumes/`) che persistono anche quando il container viene eliminato. I dati di Portainer (utenti, configurazioni, stack) vengono salvati qui.

## Avvio del container

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

> **Sulla sicurezza del Docker socket:** Montare `/var/run/docker.sock` dentro un container è l'equivalente di dare accesso root sull'host. Portainer ne ha bisogno per gestire Docker, ma un attaccante che compromette Portainer avrebbe controllo completo sul sistema. Per questo, l'accesso a Portainer va protetto con password robusta e, idealmente, limitato via firewall alla sola rete locale.

![Portainer - Container list mostra il container Portainer in stato "running"](../img/portainer-container-list.jpg)

## Accesso a Portainer

```
https://<IP_DEL_RASPBERRY>:9443
```

Al primo accesso, Portainer chiede di creare un utente admin con password. Dopo il login, selezionare **Docker → Local** come endpoint.

> **Il browser mostrerà un avviso di certificato:** Portainer genera un certificato SSL self-signed al primo avvio. Il browser non si fida di certificati non emessi da una CA riconosciuta. In un ambiente domestico, questo è accettabile - aggiungi l'eccezione nel browser.

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

## Pinning della versione (consigliato per produzione)

In un ambiente di produzione, usare il tag `latest` è rischioso: un aggiornamento automatico può introdurre breaking changes. Meglio fissare la versione:

```bash
docker pull portainer/portainer-ce:2.21.4
```

E usare `portainer/portainer-ce:2.21.4` nel comando `docker run` al posto di `latest`.
