# Kernel Hardening con sysctl e Aggiornamenti Automatici

## Hardening sysctl

Oltre al firewall, il kernel Linux espone parametri configurabili via `sysctl` che rafforzano il network stack e la memoria. Questi parametri sono particolarmente importanti per un sistema esposto su Internet (anche indirettamente tramite honeypot).

### Configurazione

Creare il file `/etc/sysctl.d/99-hardening.conf`:

```bash
sudo nano /etc/sysctl.d/99-hardening.conf
```

```ini
# === NETWORK STACK HARDENING ===

# Abilita protezione SYN flood (SYN cookies)
# Quando la coda SYN e' piena, il kernel genera un SYN cookie crittografico
# invece di allocare memoria - previene DoS da SYN flood
net.ipv4.tcp_syncookies = 1

# Disabilita il source routing
# Il source routing permette al mittente di specificare il percorso dei pacchetti
# attraverso la rete - usato in attacchi di routing manipulation
net.ipv4.conf.all.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0

# Ignora ICMP redirect
# I redirect ICMP dicono all'host di usare un gateway diverso
# Un attaccante puo' usarli per redirigere il traffico (MITM)
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0

# Disabilita invio di ICMP redirect
# Un server non dovrebbe mai agire da router - non invia redirect
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0

# Abilita Reverse Path Filtering (anti-spoofing)
# Il kernel verifica che l'IP sorgente di un pacchetto in ingresso sia
# raggiungibile dall'interfaccia su cui e' arrivato - blocca pacchetti con
# IP sorgente falsificato
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# Ignora ping broadcast (prevenzione Smurf attack)
# Un attaccante invia ping all'indirizzo broadcast della rete con IP sorgente
# falsificato (la vittima) - tutti gli host rispondono alla vittima
net.ipv4.icmp_echo_ignore_broadcasts = 1

# Log dei pacchetti "marziani" (IP sorgente impossibile)
# Utile per debug e per rilevare tentativi di spoofing
net.ipv4.conf.all.log_martians = 1

# === MEMORY PROTECTION ===

# ASLR (Address Space Layout Randomization) - livello massimo
# Randomizza le posizioni di stack, heap, mmap e librerie in memoria
# Rende molto piu' difficile sfruttare vulnerabilita' di buffer overflow
# 0 = disabilitato, 1 = stack/mmap, 2 = stack/mmap/heap (massimo)
kernel.randomize_va_space = 2

# Proteggi i symlink e hardlink in directory world-writable (/tmp)
# Previene attacchi di symlink race condition (privilege escalation)
fs.protected_symlinks = 1
fs.protected_hardlinks = 1

# Limita l'accesso a dmesg a utenti con CAP_SYSLOG
# dmesg puo' rivelare informazioni sulla memoria del kernel (utili per exploit)
kernel.dmesg_restrict = 1

# Disabilita la possibilita' di caricare moduli kernel non firmati
# Previene il caricamento di rootkit come moduli kernel
# NOTA: abilitare solo se tutti i moduli necessari sono gia' caricati
# kernel.modules_disabled = 1   # <-- COMMENTATO: WireGuard potrebbe aver bisogno di caricare moduli

# Limita l'uso di perf (performance counters) - usabili per side-channel attacks
kernel.perf_event_paranoid = 3
```

### Applicare le modifiche

```bash
sudo sysctl --system
```

### Verifica

```bash
# Controlla che i parametri siano attivi
sysctl net.ipv4.tcp_syncookies
# net.ipv4.tcp_syncookies = 1

sysctl kernel.randomize_va_space
# kernel.randomize_va_space = 2
```

> **Nota su `kernel.modules_disabled`:** Se lo abiliti (valore 1), nessun modulo kernel potra' piu' essere caricato fino al prossimo reboot. Questo blocca i rootkit kernel-mode, ma impedisce anche a WireGuard di caricare il suo modulo se non e' gia' caricato. Abilitare solo dopo aver verificato che tutti i servizi funzionano correttamente.

---

## Aggiornamenti Automatici

Le vulnerabilita' vengono scoperte quotidianamente. Un sistema non aggiornato e' un bersaglio facile. `unattended-upgrades` installa automaticamente le patch di sicurezza senza intervento manuale.

```bash
sudo apt install unattended-upgrades -y
sudo dpkg-reconfigure unattended-upgrades
```

Il comando `dpkg-reconfigure` mostra una schermata interattiva - selezionare **Yes** per abilitare gli aggiornamenti automatici.

**Cosa viene aggiornato automaticamente:**

- Patch di sicurezza Debian (repository `*-security`)
- **NON** aggiornamenti di funzionalita' o nuove versioni major

Questo e' il comportamento corretto per un server: vuoi le fix di sicurezza, non vuoi che un aggiornamento ti rompa OMV o Docker senza preavviso.
