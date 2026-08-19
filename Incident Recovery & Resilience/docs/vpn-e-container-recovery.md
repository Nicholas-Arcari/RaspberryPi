>  [English](vpn-e-container-recovery.en.md) |  **Italiano**

# Runbook 04 - VPN e container recovery

> **Quando usare questo runbook:** non riesci piu' a connetterti alla VPN WireGuard da fuori casa, un container e' morto o e' in restart loop, oppure Docker non si avvia affatto. Due famiglie di problemi legate: la VPN gira in un container, e i container girano su Docker.

---

## Parte A - La VPN WireGuard non entra da fuori

WireGuard e' silenzioso per design: se qualcosa lungo il percorso non va, il client non da errori chiari, semplicemente "non completa l'handshake". Si diagnostica dal basso, seguendo il pacchetto dall'esterno fino al container.

```
   Client (4G) -> DNS DDNS -> IP pubblico -> CGNAT? -> Router -> port fwd -> Pi -> container wg
        [1]         [2]          [3]          [4]       [5]        [6]        [7]     [8]
```

### A.1 Il nome DDNS risolve? [2]

```bash
dig +short miodominio.ddns.net
curl -s https://api.ipify.org ; echo    # IP pubblico reale
# I due valori devono coincidere. Se no -> problema DDNS: vai al Runbook 02, Parte D
```

### A.2 La porta VPN e' raggiungibile dall'esterno? [3][5][6]

WireGuard usa **UDP/51820**. Testare UDP dall'esterno e' scomodo (nessun handshake TCP), ma si puo':

```bash
# Sul Pi: WireGuard e' davvero in ascolto sulla UDP giusta?
sudo ss -ulnp | grep 51820
# Atteso: 0.0.0.0:51820

# Da fuori (es. da un VPS o dal telefono in 4G con un'app), verifica la UDP 51820.
# In alternativa, un check indiretto: il honeypot su 2222/TCP e' raggiungibile da fuori?
#   Se nemmeno il port forward TCP del honeypot funziona, il problema e' router/CGNAT (A.3),
#   non WireGuard.
```

### A.3 CGNAT: la causa piu' probabile e la piu' fraintesa [4]

L'uplink e' un'antenna FWA (Comeser) dietro **CGNAT**: l'IP "pubblico" che vedi sul router e' in realta' condiviso e non instradabile dall'esterno verso di te. Sintomo tipico: **il DDNS e' perfetto, il port forward e' configurato, ma da fuori non entra nulla.**

```bash
# Come riconoscere il CGNAT: l'IP WAN del router e' in un range CGNAT (100.64.0.0/10)
#   oppure e' diverso dall'IP visto da api.ipify.org.
# Sul router, guarda l'IP WAN e confrontalo:
curl -s https://api.ipify.org ; echo
# Se l'IP WAN del router (es. 100.x.y.z) != IP di ipify -> sei dietro CGNAT
```

Se sei dietro CGNAT, il port forwarding **non puo' funzionare** e nessuna configurazione WireGuard lo aggira. Le vie d'uscita:

| Soluzione | Come | Nota |
|---|---|---|
| Tunnel in uscita | Cloudflare Tunnel / Tailscale / Ngrok | Non richiede porta in ingresso; il Pi apre la connessione verso l'esterno |
| IP pubblico dal provider | Richiedere a Comeser un IPv4 pubblico statico | A volte a pagamento; risolve alla radice |
| IPv6 | Se il provider offre IPv6 pubblico end-to-end | WireGuard su IPv6 bypassa il CGNAT IPv4 |

Vedi [VPN / rete-dmz](../../VPN%20(Virtual%20Private%20Network)/docs/rete-dmz.md) per il contesto di rete.

### A.4 L'handshake non si completa [7][8]

Se il pacchetto arriva al container ma il tunnel non sale, e' un problema di chiavi o di orario.

```bash
# Stato dei peer: l'ultimo handshake e il traffico
docker exec wireguard wg show
# "latest handshake: 30 seconds ago" -> tunnel vivo
# "latest handshake" assente e transfer 0 -> il peer non completa mai:
#    - chiave pubblica/privata non corrispondenti (peer riconfigurato)
#    - orologio del Pi sballato (WireGuard e' sensibile al tempo per i nonce)
#    - AllowedIPs sbagliati sul client

# Controlla l'orologio (un tempo sballato rompe crypto e log)
timedatectl status | grep -E "System clock|synchronized"
# Atteso: "System clock synchronized: yes"
```

### A.5 Il tunnel sale ma non raggiungo la LAN

Handshake ok, ma non pinghi `192.168.0.102`: e' routing/firewall, non VPN.

```bash
# Sul Pi: l'IP forwarding e' attivo? (serve per instradare il traffico VPN verso la LAN)
sysctl net.ipv4.ip_forward
# Atteso: net.ipv4.ip_forward = 1

# UFW sta bloccando il forward dal subnet VPN (10.8.0.0/24) alla LAN?
sudo ufw status verbose | grep -i 10.8
```

---

## Parte B - Docker non si avvia

Se il demone Docker e' giu', **tutti** i container (Portainer, Pi-hole, WireGuard, Cowrie) sono giu' insieme. E' un guasto ad alto impatto.

```bash
sudo systemctl status docker --no-pager
sudo journalctl -u docker -b --no-pager | tail -40
```

Cause tipiche e fix:

| Sintomo nei log | Causa | Fix |
|---|---|---|
| `failed to start daemon ... no space` | Disco pieno | [Runbook 09](risorse-e-credenziali.md), poi `systemctl start docker` |
| `error initializing ... /var/lib/docker` | Storage Docker corrotto (spesso dopo spegnimento sporco) | Vedi sotto |
| `dockerd ... permission` dopo update | daemon.json malformato | `sudo dockerd --validate` / correggi il JSON |

```bash
# Verifica la config del demone (un JSON malformato impedisce l'avvio)
sudo cat /etc/docker/daemon.json | python3 -m json.tool

# Docker Root e' su NVMe (/var/lib/docker): controlla che sia montato e sano
df -h /var/lib/docker
# Se dopo uno spegnimento sporco lo storage e' corrotto, potresti dover recuperare
# dai backup dei volumi (Runbook 08). I dati dei servizi stanno nei volumi montati,
# non nell'immagine: e' il motivo per cui il compose + i volumi bastano a ricostruire.
```

---

## Parte C - Un container e' morto o in crash loop

Docker e' su, ma un singolo servizio no. La diagnosi parte dallo stato e dall'exit code.

```bash
docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
# "Restarting (1)" -> crash loop.  "Exited (137)" -> ucciso per OOM

# La verita' e' sempre nei log del container
docker logs <nome> --tail 80
```

Exit code come diagnosi (vedi anche [Runbook 00](triage-diagnostica.md)):

| Exit | Significato | Direzione |
|---|---|---|
| `137` | SIGKILL, quasi sempre **OOM** | [Runbook 09](risorse-e-credenziali.md): RAM/limiti |
| `1`/`2` | Errore app / config errata | Leggi i log, correggi il compose/env |
| `139` | Segfault | Immagine/arch errata (ARM64!) o bug |

Ricreazione pulita (i dati sopravvivono nei volumi):

```bash
# Dalla cartella del compose del servizio
cd /path/al/compose/<servizio>
docker compose down
docker compose up -d --force-recreate

# Se sospetti immagine corrotta o sbagliata (es. non-ARM64):
docker compose pull        # riscarica l'immagine
docker image inspect <img> --format '{{.Architecture}}'   # deve essere arm64/aarch64
```

> **Perche' "ricreare" e' sicuro.** Nel design del lab, ogni servizio tiene i suoi dati in **volumi Docker montati**, non dentro il container. Distruggere e ricreare il container non tocca i dati: e' proprio la proprieta' che rende i container recuperabili in un comando. L'unica cosa da custodire sono i volumi e i file compose/env -> [Runbook 08](backup-e-disaster-recovery.md).

---

## Verifica di ripristino

```bash
# VPN
docker exec wireguard wg show | grep -A1 peer     # handshake recente su un client connesso
# Container
docker ps --format "table {{.Names}}\t{{.Status}}"  # tutti "Up"
# Docker
sudo systemctl is-active docker                    # active
```

---

## Prevenzione

- **CGNAT:** decidi in anticipo la strategia di accesso remoto (tunnel in uscita vs IP pubblico). Non scoprire il CGNAT durante un'emergenza, mentre sei fuori casa e ti serve entrare.
- **Restart policy:** imposta `restart: unless-stopped` nei compose cosi' i container ripartono da soli dopo un reboot; ma un crash loop persistente va indagato, non ignorato.
- **Limiti risorse:** metti `mem_limit` sui container non critici cosi' non e' l'indexer di Wazuh a morire per OOM quando Cowrie impazzisce.
- **Orologio:** tieni `systemd-timesyncd` attivo; un tempo sballato rompe WireGuard, i certificati e i log in un colpo solo.

---

## Collegamenti

- OOM / disco pieno dietro un exit 137 -> [Runbook 09: risorse e credenziali](risorse-e-credenziali.md)
- Il nome DDNS non risolve -> [Runbook 02: DNS / Pi-hole](dns-pihole-recovery.md)
- Ricostruire i volumi da backup -> [Runbook 08: backup e disaster recovery](backup-e-disaster-recovery.md)
- WireGuard e DMZ in dettaglio -> [VPN / teoria-wireguard](../../VPN%20(Virtual%20Private%20Network)/docs/teoria-wireguard.md), [VPN / troubleshooting](../../VPN%20(Virtual%20Private%20Network)/docs/troubleshooting.md)
