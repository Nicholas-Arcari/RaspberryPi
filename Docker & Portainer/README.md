# Docker + Portainer su Raspberry Pi 5 con OpenMediaVault (OMV)

Questa guida spiega come **installare correttamente Docker e Portainer** su un Raspberry Pi 5 con Debian Trixie e OpenMediaVault (OMV). 

---

## Controllo iniziale

Assicurati che il sistema sia aggiornato:

```bash
sudo apt update -y
```

---

## Rimozione di Docker CE (opzionale ma consigliata)

Se in precedenza hai installato Docker tramite lo script get.docker.com, occorre rimuoverlo:

```bash
sudo apt purge docker-ce docker-ce-cli containerd.io docker-compose-plugin docker-buildx-plugin docker-model-plugin
sudo apt autoremove --purge
```

Avvertenze:

- Non interrompere i comandi durante l’esecuzione
- Sulla Raspberry Pi la rimozione di Docker può sembrare bloccata (barra ferma al 5–23%), è normale

Se il comando sembra fermo, apri un’altra sessione SSH e verifica:

```bash
ps aux | grep dpkg
ls -l /var/lib/dpkg/lock*
```

Se `dpkg` non è in esecuzione, sei pronto per il prossimo passo.

---

## Recupero pacchetti incompleti

Se APT segnala pacchetti “mezzo installati”:

```bash
sudo dpkg --configure -a
sudo apt -f install
```

Motivo: questo ripara pacchetti parziali lasciati da Docker CE e garantisce uno stato coerente del sistema

---

## Installazione di Docker “Debian”

(Raccomandato per Raspberry Pi + OMV, più stabile di Docker CE tramite script)

```bash
sudo apt update
sudo apt install docker.io docker-compose
sudo systemctl enable --now docker
```

---

## Permessi utente

Per usare Docker senza sudo:

```bash
sudo groupadd docker        # solo se il gruppo docker non esiste
sudo usermod -aG docker <nome_utente_dispositivo>
```

Dopo questo passaggio eseguire logout e login via SSH

---

## Verifica dell’installazione

```bash
docker version
docker run hello-world
```

Dev’essere tutto funzionante, con il daemon attivo (Active: active (running))

---

## Installazione di Portainer

### Creazione del volume dati persistente

```bash
docker volume create portainer_data
```

### Avvio del container Portainer

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

Spiegazione porte:

9443 → interfaccia web HTTPS

8000 → tunnel agent Docker (utile per agenti remoti)

![](../img/18.jpg)

### Accesso a Portainer

Dal browser del PC:

```bash
https://<IP_DEL_PI>:9443
```

Creare username e password

Selezionare Docker → Local come endpoint

---

## Consigli pratici

Non installare Portainer come plugin OMV: usare solo container Docker.

Se vuoi aggiornare Portainer, puoi fare:

```bash
docker pull portainer/portainer-ce:latest
docker stop portainer
docker rm portainer
docker run ... (stesso comando utilizzato in precedenza per creare portainer la prima volta)
```

È consigliabile non usare la versione `latest` in produzione, fissare la versione per stabilità:

```bash
docker pull portainer/portainer-ce:2.21.4
```

Il volume `portainer_data` contiene tutti i dati di configurazione, quindi puoi fare backup facilmente

---

## Comandi utili per la manutenzione

Controllare container attivi:

```bash
docker ps
```

Fermare / avviare container:

```bash
docker stop <nome>
docker start <nome>
```

Aggiornare Docker su Debian:

```bash
sudo apt update
sudo apt upgrade docker.io docker-compose
```

---

## Cosa evitare

Non interrompere APT/Dpkg durante installazione/rimozione di Docker

Non usare get.docker.com su OMV, causa conflitti con systemd

Non usare Portainer come plugin OMV

Non ignorare i gruppi (docker): necessario per permessi utente