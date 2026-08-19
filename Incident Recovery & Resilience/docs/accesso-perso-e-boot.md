>  [English](accesso-perso-e-boot.en.md) |  **Italiano**

# Runbook 01 - Accesso perso e boot failure

> **Quando usare questo runbook:** SSH non risponde piu', ti sei chiuso fuori con una regola firewall, hai perso la chiave, il sistema va in kernel panic, oppure il boot da NVMe fallisce. In breve: non riesci piu' a entrare.

Regola mentale: procedi dal metodo di accesso **piu' comodo** a quello **piu' invasivo**, fermandoti appena rientri. La scala e': SSH -> console fisica (HDMI+tastiera) -> console seriale UART -> boot di recovery da MicroSD.

---

## Parte A - SSH non funziona

### A.1 Isolare: e' SSH o e' tutto il Pi?

Dal tuo PC:

```bash
# Il Pi e' vivo a livello di rete?
ping -c3 192.168.0.102
# NO risposta -> non e' SSH, e' rete/host: vai alla Parte B (console)
# SI risposta -> l'host e' su, il problema e' specifico di SSH: prosegui

# La porta 22 e' aperta?
nc -vz 192.168.0.102 22
# "succeeded" -> sshd e' su, problema di auth/config (A.3)
# "refused"   -> sshd e' giu' (A.2)
# "timed out" -> un firewall sta bloccando (A.4)
```

### A.2 sshd e' giu' (connection refused)

Serve accesso locale (Parte B). Una volta a console:

```bash
# Stato e log del servizio
sudo systemctl status ssh
sudo journalctl -u ssh -b --no-pager | tail -30

# Causa frequente: errore di sintassi in sshd_config dopo una modifica
sudo sshd -t
# Output atteso SANO: nessun output. Qualsiasi riga = errore di config con numero di riga

sudo systemctl restart ssh
```

> **Trappola OMV:** OpenMediaVault rigenera `sshd_config` dalla sua web UI. Se una tua modifica manuale sparisce o il servizio si rompe dopo aver toccato le impostazioni SSH nella dashboard, applica le modifiche da **Services -> SSH** nella web UI OMV invece che a mano.

### A.3 sshd e' su ma rifiuta il login (auth)

```bash
# Dal client, con log verboso per vedere DOVE fallisce
ssh -vvv pi@192.168.0.102 2>&1 | grep -Ei "offer|accept|deny|permission|authentication"
```

Cause tipiche e fix:

| Sintomo nel log | Causa | Fix |
|---|---|---|
| `Permission denied (publickey)` | La chiave pubblica non e' piu' in `authorized_keys` | Rientra da console, ri-aggiungi la chiave |
| `no matching host key type` | Client vecchio / algoritmi disabilitati | Aggiorna il client o `-o HostKeyAlgorithms=+ssh-rsa` |
| Login ok ma poi si chiude | Permessi errati su `~/.ssh` | `chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys` |
| `Too many authentication failures` | L'agent offre troppe chiavi | `ssh -o IdentitiesOnly=yes -i <chiave> ...` |

### A.4 Connection timed out (firewall)

Quasi sempre sei tu che ti sei bloccato con UFW o Fail2ban. Vai alla sezione dedicata sotto.

---

## Il classico: lockout con UFW

Hai dato `ufw enable` senza prima `ufw allow ssh`, oppure hai stretto una regola. La sessione SSH corrente puo' restare viva, ma le nuove connessioni cadono. **Se hai ancora una sessione aperta, non chiuderla:** riparala da li'.

```bash
# Vedi cosa blocca
sudo ufw status verbose

# Riapri SSH (solo dalla LAN, piu' sicuro che aprire a tutti)
sudo ufw allow from 192.168.0.0/24 to any port 22 proto tcp

# Se sei disperato e a console: azzera e riparti
sudo ufw disable          # firewall giu' temporaneamente
sudo ufw --force reset     # rimuove tutte le regole
# poi riconfigura da zero (vedi Secure your RaspberryPi/firewall-ufw.md)
```

Fail2ban invece ti banna dopo troppi tentativi falliti: l'IP viene messo in una catena iptables per N minuti.

```bash
# Sei bannato? (da console o da un altro IP)
sudo fail2ban-client status sshd
# Sblocca il tuo IP
sudo fail2ban-client set sshd unbanip <TUO_IP>
```

> **Prevenzione:** aggiungi il tuo IP LAN alla `ignoreip` di Fail2ban e tieni **sempre** una seconda sessione SSH aperta prima di modificare firewall o config SSH. E' la rete di sicurezza piu' economica che esista.

---

## Parte B - Rientrare senza rete: la console fisica

Quando la rete non aiuta, si passa all'accesso out-of-band.

### B.1 Monitor + tastiera (il metodo semplice)

1. Collega un cavo **micro-HDMI** alla porta HDMI0 del Pi 5 e un monitor.
2. Collega una **tastiera USB**.
3. Dai corrente. Al prompt, login con **username e password locali** (l'utente `pi` o l'utente OMV; la password locale funziona anche se SSH accetta solo chiavi - sono cose diverse).
4. Da qui hai una shell root con `sudo` e puoi applicare tutti i fix delle sezioni precedenti.

### B.2 Console seriale UART (quando manca l'HDMI o non c'e' output video)

Se il boot fallisce cosi' presto che l'HDMI resta nero, la seriale mostra tutto dal primissimo stadio.

```bash
# Su Raspberry Pi OS, abilitare la console seriale (se non gia' fatto, da config)
# In /boot/firmware/config.txt:  enable_uart=1
# In /boot/firmware/cmdline.txt: console=serial0,115200

# Collega un adattatore USB-TTL ai pin GPIO: GND(6), TXD(8), RXD(10)
# Dal PC:
sudo screen /dev/ttyUSB0 115200
# oppure
sudo minicom -D /dev/ttyUSB0 -b 115200
```

La seriale e' l'unico modo per vedere un **kernel panic** o un errore di bootloader in diretta.

---

## Parte C - Kernel panic

Un kernel panic e' l'arresto di emergenza del kernel: ha incontrato uno stato irrecuperabile (spesso I/O sull'NVMe, memoria corrotta, o un modulo difettoso) e si ferma per non fare danni. Il sistema e' congelato: SSH e i servizi sono morti.

### C.1 Leggere il panic

A console (HDMI o seriale) vedrai qualcosa come:

```
Kernel panic - not syncing: VFS: Unable to mount root fs on unknown-block(0,0)
```

L'ultima riga significativa dice la causa. Le piu' comuni sul Pi 5:

| Messaggio | Causa probabile | Direzione |
|---|---|---|
| `Unable to mount root fs` | Il kernel non trova/monta l'NVMe | Boot di recovery (Parte D), controlla NVMe |
| `EXT4-fs error ... I/O error` | Filesystem o disco corrotto | fsck da recovery (Parte D) |
| `Out of memory: Killed process` seguito da freeze | Esaurimento RAM | [Runbook 09](risorse-e-credenziali.md) |
| Panic dopo un aggiornamento kernel | Kernel/DTB incompatibile | Rollback kernel (C.2) |

### C.2 Cosa fare

```bash
# 1. Forza un riavvio pulito. Se il sistema e' congelato del tutto:
#    stacca e riattacca l'alimentazione (unica via su un panic hard).

# 2. Se il panic e' comparso subito dopo un "apt upgrade" del kernel,
#    fai il boot da MicroSD di recovery (Parte D), monta l'NVMe e
#    ripristina il kernel precedente:
sudo apt install --reinstall raspberrypi-kernel     # reinstalla il kernel stabile
# oppure elimina l'ultimo aggiornamento problematico dal chroot

# 3. Se il panic e' su I/O NVMe: vai alla Parte D e lancia fsck.
```

> **Panic ricorrenti da under-voltage:** sul Pi 5, un alimentatore sottodimensionato con NVMe collegato causa panic/reboot casuali che sembrano software ma sono hardware. Controlla sempre `vcgencmd get_throttled` (deve essere `0x0`). Usa l'alimentatore ufficiale 27W.

---

## Parte D - Boot da NVMe fallito: recovery da MicroSD

Se il Pi non parte piu' dall'NVMe (corruzione, EEPROM, filesystem rotto), la MicroSD di recovery e' la tua ancora. Questo e' il motivo per cui il progetto tiene sempre una SD pronta.

### D.1 Boot dalla SD e ispezione dell'NVMe

1. Inserisci la **MicroSD di recovery** (Raspberry Pi OS Lite) e avvia. Con la SD inserita, l'ordine di boot fa partire da li'.
2. A sistema avviato dalla SD, l'NVMe e' un disco secondario che puoi ispezionare e riparare senza montarlo come root.

```bash
# Vedi le partizioni dell'NVMe
lsblk -f /dev/nvme0n1

# Controlla e ripara il filesystem root dell'NVMe (deve essere SMONTATO)
sudo fsck -f /dev/nvme0n1p2
# Rispondi 'y' alle correzioni, oppure: sudo fsck -y /dev/nvme0n1p2

# Se fsck e' pulito, monta e recupera i dati/config
sudo mkdir -p /mnt/nvme
sudo mount /dev/nvme0n1p2 /mnt/nvme
ls /mnt/nvme            # accedi ai file, copia i backup, correggi le config
```

### D.2 Riparare l'ordine di boot / EEPROM

Se l'NVMe e' sano ma il Pi non parte da solo:

```bash
# Verifica la versione dell'EEPROM e l'ordine di boot
sudo rpi-eeprom-update
vcgencmd bootloader_config

# BOOT_ORDER: la cifra indica la sequenza. 0xf416 = prova NVMe poi SD poi USB.
# Aggiorna l'EEPROM all'ultima stabile se necessario
sudo rpi-eeprom-update -a
sudo reboot
```

### D.3 Chroot per riparazioni profonde

Se devi eseguire comandi "come se" fossi nel sistema NVMe (reinstallare pacchetti, sistemare fstab, rigenerare initramfs):

```bash
sudo mount /dev/nvme0n1p2 /mnt/nvme
sudo mount /dev/nvme0n1p1 /mnt/nvme/boot/firmware
for d in dev proc sys run; do sudo mount --bind /$d /mnt/nvme/$d; done
sudo chroot /mnt/nvme
# ora sei "dentro" il sistema NVMe: apt, nano /etc/fstab, ecc.
exit
```

> **Causa comune di boot rotto: `/etc/fstab`.** Una voce sbagliata (UUID cambiato, opzione errata) blocca il boot in emergency mode. Da chroot, correggi l'UUID in `fstab` confrontandolo con `blkid`.

---

## Prevenzione (cosi' non ci ricaschi)

- Tieni **sempre** una seconda sessione SSH aperta prima di toccare SSH/UFW.
- Aggiungi il tuo IP LAN a `ignoreip` in Fail2ban e a una regola UFW `allow` esplicita.
- Mantieni una **MicroSD di recovery testata** e verifica il `BOOT_ORDER` dopo ogni update EEPROM.
- Usa l'alimentatore ufficiale 27W: previene un'intera classe di panic/reboot.
- Dopo ogni `apt upgrade` che tocca il kernel, riavvia **quando sei a portata di console**, non da remoto e poi in vacanza.

---

## Collegamenti

- Se dopo il rientro sospetti che qualcuno sia entrato -> [Runbook 06: integrita' post-downtime](integrita-post-downtime.md)
- Se la causa e' disco pieno / OOM -> [Runbook 09: risorse e credenziali](risorse-e-credenziali.md)
- Configurazione firewall di riferimento -> [Secure your RaspberryPi / firewall-ufw](../../Secure%20your%20RaspberryPi/docs/firewall-ufw.md)
- Deep dive sul protocollo SSH -> [Secure your RaspberryPi / protocollo-ssh](../../Secure%20your%20RaspberryPi/docs/protocollo-ssh.md)
