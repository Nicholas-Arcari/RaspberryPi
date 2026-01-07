# Installazione del sistema operativo ( https://www.raspberrypi.com/software/ )

1. Scaricare Raspberry Pi OS Lite (64-bit) -> suggerisco Bookworm e non Trixie perchè OMV e Wazuh non sono supportati
2. Scrivere l’immagine su microSD (Raspberry Pi Imager o simili).
3. Abilitare SSH e configurare la rete.
4. Inserire la microSD nel Raspberry Pi e avviare il sistema.

---

## Primo accesso e aggiornamento

Accedere via SSH:

```bash
ssh pi@<IP_DEL_RASPBERRY>
```

Aggiornare il sistema:

```bash
sudo apt update && sudo apt upgrade -y
sudo reboot
```

## Verifica e aggiornamento del bootloader

Controllare versione EEPROM / bootloader:

```bash
sudo rpi-eeprom-update
```

e è disponibile un aggiornamento, installarlo:

```bash
sudo rpi-eeprom-update -a
sudo reboot
```

Nessun rischio di perdere l’accesso: il Pi continuerà a fare boot dalla microSD finché il boot da NVMe non viene abilitato.

---

## Architettura dello Storage

Prima ancora di aggiungere software, devi configurare l'hardware come farebbe un professionista.

Il problema: i software di sicurezza (SIEM, IDS) scrivono gigabyte di log. Se scrivi questi log sulla MicroSD, la brucerai in pochi mesi e il sistema sarà lento.

Il progetto da fare: Spostare tutto il carico di I/O sull'NVMe:

- Opzione A (Facile): sposta la `Docker Root Directory` sull'NVMe. In questo modo tutti i container e i volumi persistenti vivono sul disco veloce.
- Opzione B (Pro): boot diretto da NVMe (senza SD).