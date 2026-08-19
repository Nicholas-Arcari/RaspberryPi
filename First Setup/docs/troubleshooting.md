>  [English](troubleshooting.en.md) |  **Italiano**

# Troubleshooting - Primo setup: problemi reali e soluzioni

> Problemi tipici della fase di prima installazione (OS, primo accesso SSH, EEPROM, NVMe) e come risolverli. Per i guasti operativi che capitano **dopo** che il sistema e' in produzione (kernel panic, lockout, boot che smette di funzionare) vedi il runbook [Incident Recovery / accesso perso e boot](../../Incident%20Recovery%20%26%20Resilience/docs/accesso-perso-e-boot.md).

---

## Problema 1: L'NVMe non viene rilevato (`lsblk` non lo mostra)

**Sintomo:** dopo aver collegato l'SSD all'adattatore M.2, `lsblk` non elenca `nvme0n1`. Il disco sembra invisibile.

**Causa:** sul Raspberry Pi 5 le cause sono quasi sempre quattro, in ordine di frequenza: alimentazione insufficiente, un parametro kernel restrittivo, EEPROM datato, o un adattatore incompatibile.

**Soluzione:** diagnostica in sequenza per isolare la causa.

```bash
# 1. Il controller PCIe vede il dispositivo?
lspci -nn | grep -i nvme
#   Nulla -> problema fisico/alimentazione. Controller presente ma lsblk vuoto -> adattatore

# 2. Cosa dice il kernel al boot?
dmesg | grep -i nvme
#   "nvme: max host mem = 0" -> parametro kernel restrittivo (vedi sotto)

# 3. Alimentazione: l'NVMe aumenta il consumo. Con alimentatore sottodimensionato
#    il disco puo' sparire sotto carico.
vcgencmd get_throttled     # atteso 0x0
```

| Causa | Diagnostica | Fix |
|---|---|---|
| Adattatore non alimentato / alimentatore debole | `lspci` non mostra nulla | Alimentatore ufficiale 27W (5.1V/5A) |
| Parametro kernel restrittivo | `dmesg`: `nvme: max host mem = 0` | Rimuovere `nvme.max_host_mem_size_mb=0` da `/boot/firmware/cmdline.txt` |
| Bootloader (EEPROM) datato | NVMe non supportato dal boot | Aggiornare EEPROM (`sudo rpi-eeprom-update -a`) |
| Adattatore incompatibile | `lspci` mostra il controller ma `lsblk` no | Provare un altro adattatore M.2-to-PCIe |

---

## Problema 2: `cmdline.txt` modificato e il sistema ignora le opzioni

**Sintomo:** dopo aver modificato `/boot/firmware/cmdline.txt`, le opzioni non hanno effetto o il boot si comporta in modo strano.

**Causa:** `cmdline.txt` **deve essere una singola riga**. Un editor che va a capo spezza la riga e il kernel ignora tutto cio' che segue l'interruzione.

**Soluzione:**

```bash
# Verifica che non ci siano fine-riga ($) nel mezzo
cat -A /boot/firmware/cmdline.txt
# Deve esserci UN solo $ alla fine. $ nel mezzo -> riga spezzata, ricomponila su una riga sola
```

---

## Problema 3: Il Pi non fa boot dall'NVMe (parte ancora dalla SD)

**Sintomo:** l'NVMe e' rilevato e ha un OS valido, ma all'accensione il Pi parte sempre dalla MicroSD.

**Causa:** l'ordine di boot nell'EEPROM non da' priorita' all'NVMe.

**Soluzione:**

```bash
# Via raspi-config
sudo raspi-config      # Advanced Options -> Boot Order -> NVMe/USB Boot

# Oppure manuale, nell'EEPROM
sudo rpi-eeprom-config --edit
# Imposta: BOOT_ORDER=0xf416   (6=NVMe, 1=SD, 4=USB, f=riparti)
#   0xf416 = prova NVMe, poi SD, poi USB
```

> Per una diagnosi approfondita del boot (EEPROM, chroot, `/etc/fstab` rotto), vedi [Incident Recovery / accesso perso e boot, Parte D](../../Incident%20Recovery%20%26%20Resilience/docs/accesso-perso-e-boot.md).

---

## Problema 4: Instabilita' con PCIe Gen 3 forzato

**Sintomo:** dopo aver forzato la modalita' PCIe Gen 3 per piu' velocita', compaiono errori I/O casuali, il disco si "stacca" sotto carico o il filesystem va in read-only.

**Causa:** il Pi 5 certifica ufficialmente il PCIe solo a **Gen 2**. Forzare Gen 3 (`dtparam=pciex1_gen=3`) funziona con molti SSD ma non con tutti: alcuni adattatori/dischi sono instabili a quella frequenza.

**Soluzione:** se compaiono errori I/O, torna a Gen 2 rimuovendo il `dtparam` da `/boot/firmware/config.txt`. La differenza di throughput e' reale ma la stabilita' su un server 24/7 conta di piu'; le IOPS random (cio' che serve a Wazuh/Docker) sono comunque enormemente superiori alla SD anche a Gen 2.

```bash
# Controlla la velocita' di link PCIe negoziata
sudo lspci -vv | grep -i "LnkSta:"
```

---

## Problema 5: Non trovo l'IP del Raspberry per il primo SSH

**Sintomo:** il Pi e' acceso ma non sai a quale IP il DHCP lo ha assegnato.

**Soluzione:**

```bash
# Dalla tabella DHCP del router, oppure scansione della LAN
nmap -sn 192.168.0.0/24
# Cerca l'host con vendor "Raspberry Pi". Su Windows: arp -a
```

Il primo boot richiede ~60 secondi (espansione del filesystem e customizzazioni): se non risponde subito, attendi prima di preoccuparti.

---

## Problema 6: "REMOTE HOST IDENTIFICATION HAS CHANGED"

**Sintomo:** dopo una reinstallazione dell'OS, una reflash della SD o un cambio di dispositivo sullo stesso IP, SSH rifiuta la connessione con un avviso allarmante di identita' cambiata.

**Causa:** la chiave host presentata dal server non coincide con quella salvata in `~/.ssh/known_hosts`. E' il meccanismo anti man-in-the-middle di SSH: interviene ogni volta che la chiave cambia.

**Soluzione (solo se il cambio e' legittimo):**

```bash
# Rimuovi la vecchia entry per quell'IP
ssh-keygen -R 192.168.0.102
# La prossima connessione chiedera' di accettare il nuovo fingerprint
```

> **Attenzione:** se **non** hai reinstallato nulla e vedi questo avviso, fermati e indaga: potrebbe essere un MitM o un ARP spoofing reale. Vedi [Incident Recovery / integrita' post-downtime, Fase 6](../../Incident%20Recovery%20%26%20Resilience/docs/integrita-post-downtime.md).

---

## Problema 7: Riavvii/rallentamenti casuali dopo l'installazione

**Sintomo:** il sistema si riavvia da solo, e' lento senza motivo, o mostra un fulmine sullo schermo.

**Causa:** sotto-alimentazione (under-voltage). Con l'NVMe collegato, il consumo cresce e un alimentatore non ufficiale spesso non regge.

**Soluzione:**

```bash
vcgencmd get_throttled
# 0x0 = ok. 0x50000/0x50005 = under-voltage (ora o in passato) -> alimentatore ufficiale 27W
```

---

## Comandi utili di verifica

```bash
# Da dove sto facendo boot? (root su nvme o su mmcblk?)
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT | grep -E "nvme|mmcblk|/$"

# Versione EEPROM e stato aggiornamento
sudo rpi-eeprom-update

# Ordine di boot attuale
vcgencmd bootloader_config | grep BOOT_ORDER

# Sistema aggiornato con tutte le patch (kernel incluso)
sudo apt update && sudo apt full-upgrade -y
```

---

## Collegamenti

- Guasti operativi post-produzione (panic, lockout, recovery da SD) -> [Incident Recovery / accesso perso e boot](../../Incident%20Recovery%20%26%20Resilience/docs/accesso-perso-e-boot.md)
- Architettura storage e migrazione a NVMe -> [storage-nvme](storage-nvme.md)
- Primo accesso e fingerprint SSH in dettaglio -> [primo-accesso](primo-accesso.md)
- Aggiornamento EEPROM -> [bootloader](bootloader.md)
