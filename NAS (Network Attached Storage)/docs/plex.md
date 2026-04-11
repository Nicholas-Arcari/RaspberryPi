>  [English](plex.en.md) |  **Italiano**

# Step 5: Plex Media Server (Opzionale)

Plex permette di fare streaming dei media presenti sul NAS verso qualsiasi dispositivo (TV, smartphone, tablet).

> **Avvertenza sulle prestazioni:** Plex su Raspberry Pi 5 funziona bene in modalità **Direct Play** (il client supporta il formato originale del file). Se il client richiede **transcoding** (conversione del formato in tempo reale), la CPU ARM quad-core A76 si saturerà rapidamente, specialmente con video 4K. Consiglio: usare formati compatibili (H.264/AAC in container MP4/MKV) e client che supportano Direct Play.

## Installazione

```bash
# Supporto HTTPS per APT
sudo apt update
sudo apt install apt-transport-https -y

# Chiave GPG di Plex
curl https://downloads.plex.tv/plex-keys/PlexSign.key | sudo gpg --dearmor -o /usr/share/keyrings/plex-archive-keyring.gpg

# Repository Plex
echo "deb [signed-by=/usr/share/keyrings/plex-archive-keyring.gpg] https://downloads.plex.tv/repo/deb public main" | sudo tee /etc/apt/sources.list.d/plexmediaserver.list

# Installazione
sudo apt update
sudo apt install plexmediaserver -y
```

## Verifica e accesso

```bash
sudo systemctl status plexmediaserver
```

Interfaccia web:

```
http://<IP_DEL_RASPBERRY>:32400/web
```

Da qui potrai aggiungere le librerie media puntando alle cartelle condivise del NAS (sotto `/srv/dev-disk-by-uuid/...`).

## Consigli di manutenzione

- **Dopo aggiornamenti kernel o firmware**: ricontrollare che l'NVMe sia visibile con `lsblk`
- **Non rimuovere la MicroSD** finchè il boot da NVMe non è confermato funzionante
- **Monitorare SMART regolarmente**: un NVMe in un case chiuso può raggiungere temperature critiche; considerare un dissipatore o il case ufficiale con ventola
- **Backup delle configurazioni OMV**: esportare periodicamente la configurazione da System → Backup
