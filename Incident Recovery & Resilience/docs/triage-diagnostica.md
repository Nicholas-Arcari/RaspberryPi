>  [English](triage-diagnostica.en.md) |  **Italiano**

# Runbook 00 - Triage e diagnostica sistematica

> **Quando usare questo runbook:** qualcosa non funziona e non sai da dove partire. Questo e' il punto di ingresso di tutti gli altri runbook. Ti porta dalla domanda vaga "e' rotto" alla causa isolata, un livello alla volta.

Il principio guida e' uno solo: **diagnostica lo stack dal basso verso l'alto.** Un guasto a un livello basso (alimentazione, kernel, rete) si manifesta come sintomo a un livello alto (un servizio che non risponde). Investigare il servizio prima di aver escluso i livelli sotto e' la causa numero uno di ore perse.

---

## Albero decisionale principale

```
                        "Qualcosa non funziona"
                                 |
                                 v
                    Il Pi risponde al ping?
                    ping 192.168.0.102
                         /            \
                       NO              SI
                        |               |
                        v               v
         Il Pi e' acceso e sano?    SSH funziona?
         (LED, HDMI, alimentaz.)    ssh pi@192.168.0.102
              /        \                 /         \
            NO          SI             NO           SI
             |           |              |            |
             v           v              v            v
        Runbook 01   Problema di    Runbook 01    Sei dentro:
        (power/boot) rete/L2->L3     (accesso     diagnostica
                     Runbook 07      perso)       i servizi (sotto)
                     (LAN health)
```

Una volta **dentro** il sistema (SSH o console), la diagnosi prosegue per livelli con i comandi qui sotto. Esegui i blocchi in ordine e fermati al primo livello che mostra un'anomalia: e' li' la radice.

---

## Livello 0-1: alimentazione, hardware, kernel

Sintomi tipici: il Pi non si accende, si riavvia da solo, e' lentissimo, l'NVMe sparisce.

```bash
# Sotto-alimentazione (la causa hardware n.1 sul Pi 5 con NVMe)
# Se compare "under-voltage detected", l'alimentatore e' inadeguato
vcgencmd get_throttled
# Output atteso SANO: throttled=0x0
# 0x50000 o 0x50005 = under-voltage in corso o passato   <-- PROBLEMA

# Temperatura (throttling termico sopra ~80-85 C)
vcgencmd measure_temp
# Output atteso: temp=45.0'C .. 65.0'C sotto carico normale

# Il disco di boot e' l'NVMe? Il root e' montato?
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT | grep -E "nvme|mmcblk|/$"
# Output atteso: nvme0n1p2 montato su /

# Errori kernel critici recenti (I/O, oom, panic, filesystem)
sudo dmesg -T --level=err,crit,alert,emerg | tail -30
# Output atteso: vuoto o warning innocui. Righe I/O error / EXT4-fs error <-- PROBLEMA disco
```

Se qui trovi under-voltage, throttling o errori NVMe, vai a **[Runbook 01](accesso-perso-e-boot.md)** e **[Runbook 09](risorse-e-credenziali.md)**.

---

## Livello 2-3: rete, link, IP, routing

Sintomi tipici: "non raggiungo il Pi", "internet non va", i servizi web non aprono.

```bash
# L'interfaccia e' UP e ha portante (link fisico)?
ip -br link show end0
# Output atteso: end0   UP   xx:xx:xx:xx:xx:xx
# Stato DOWN o NO-CARRIER <-- problema di cavo/switch/porta

# Ho un IP e quello giusto?
ip -br addr show end0
# Output atteso: end0   UP   192.168.0.102/24

# Raggiungo il gateway (Livello 3 locale)?
ping -c3 192.168.0.1
# Output atteso: 3 received. 100% packet loss <-- problema LAN

# Raggiungo Internet by IP (esclude il DNS)?
ping -c3 1.1.1.1
# Output atteso: risposte. Se questo va ma i nomi no -> e' il DNS (Runbook 02)

# La tabella di routing ha una default route?
ip route | grep default
# Output atteso: default via 192.168.0.1 dev end0
```

Regola chiave: **se `ping 1.1.1.1` funziona ma `ping google.com` no, non e' la rete: e' il DNS.** Vai a **[Runbook 02](dns-pihole-recovery.md)**. Se fallisce gia' il ping al gateway, e' L2/L3: vai a **[Runbook 07](lan-health-check.md)**.

---

## Livello 4: DNS

```bash
# Il Pi-hole risponde e risolve?
dig @192.168.0.250 google.com +short
# Output atteso: uno o piu' IP. "connection timed out" <-- Pi-hole giu' (Runbook 02)

# Il Pi-hole blocca ancora (prova positiva del sinkhole)?
dig @192.168.0.250 ads.doubleclick.net +short
# Output atteso: 0.0.0.0

# Cosa sta usando come DNS l'host stesso?
resolvectl status | grep "DNS Servers" || cat /etc/resolv.conf
```

Dettaglio completo in **[Runbook 02](dns-pihole-recovery.md)**.

---

## Livello 5-6: servizi host e container

```bash
# Panoramica servizi bare-metal critici (Wazuh gira NON in Docker)
sudo systemctl --failed
# Output atteso: "0 loaded units listed". Qualsiasi unit failed <-- indagare

sudo systemctl is-active docker wazuh-manager wazuh-indexer wazuh-dashboard
# Output atteso: active active active active

# Cosa e' in ascolto e su quale porta (mappa servizi <-> porte)
sudo ss -tulnp | grep -E ':(22|53|80|443|9200|9443|51820|2222) '

# Stato di tutti i container (anche quelli morti/in restart loop)
docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
# Output atteso: portainer, pihole, wireguard, cowrie tutti "Up"
# Status "Restarting (1) 5 seconds ago" <-- crash loop (Runbook 04)
# Status "Exited (137)" <-- ucciso per OOM (Runbook 09)
```

Il codice di uscita di un container e' una diagnosi in se':

| Exit code | Significato | Runbook |
|---|---|---|
| `0` | Uscita pulita (fermato di proposito) | - |
| `1` / `2` | Errore applicativo, spesso config errata | 04 |
| `137` | Ucciso (SIGKILL), quasi sempre **OOM** | 09 |
| `139` | Segmentation fault (`128 + 11`) | 04 |
| `143` | Terminato (SIGTERM), shutdown normale | - |

---

## La regola dei "cinque perche'" applicata

Isolare il livello e' meta' del lavoro; l'altra meta' e' non fermarsi al primo sintomo. Esempio reale di catena:

```
Sintomo:   "La dashboard Wazuh non apre"          (livello 7)
  perche'? -> il servizio wazuh-dashboard e' inactive   (livello 5)
  perche'? -> wazuh-indexer non parte                   (livello 5)
  perche'? -> l'indexer non riesce ad allocare la heap  (livello 1)
  perche'? -> la RAM e' esaurita, il disco e' pieno     (livello 0-1)
  CAUSA RADICE -> journald + log Docker hanno riempito / (Runbook 09)
```

Fermarsi a "riavvio la dashboard" avrebbe curato il sintomo per cinque minuti. La cura vera e' liberare spazio e mettere un limite ai log. **Documenta sempre la causa radice, non solo il fix.**

---

## Cassetta degli attrezzi minima

Comandi di diagnosi trasversale da conoscere a memoria:

```bash
uptime                       # da quanto e' su, e il load average
free -h                      # RAM e swap disponibili
df -h /                      # spazio sul root (disco pieno = mille problemi)
journalctl -p err -b --no-pager | tail -40   # errori dal boot corrente
sudo dmesg -T | tail -40     # eventi kernel recenti
docker stats --no-stream     # CPU/RAM per container
```

> **Se sei arrivato qui senza trovare la causa:** salva l'output di tutti i comandi sopra in un file (`comando > /tmp/diag.txt 2>&1`) prima di riavviare qualsiasi cosa. Un riavvio spesso "risolve" nascondendo la causa, e ti toglie le prove per capire se succedera' di nuovo.

---

## Collegamenti

- Non raggiungi affatto il Pi -> [Runbook 01: accesso perso e boot](accesso-perso-e-boot.md)
- Il gateway non risponde -> [Runbook 07: LAN health check](lan-health-check.md)
- I nomi non si risolvono -> [Runbook 02: DNS / Pi-hole](dns-pihole-recovery.md)
- Un servizio e' `failed`/`Exited` -> [Runbook 04: VPN e container](vpn-e-container-recovery.md)
- Sospetti una compromissione dopo un downtime -> [Runbook 06: integrita' post-downtime](integrita-post-downtime.md)
