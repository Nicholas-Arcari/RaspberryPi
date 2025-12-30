## Installazione del sistema operativo ( https://www.raspberrypi.com/software/ )

1. Scaricare Raspberry Pi OS Lite (64-bit).
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
