# Perche' Pi-hole e non le alternative

## Pi-hole vs AdGuard Home vs Blocky vs NextDNS

| Aspetto | Pi-hole | AdGuard Home | Blocky | NextDNS |
|---|---|---|---|---|
| **Architettura** | dnsmasq + FTL (C) | CoreDNS custom (Go) | Go, config YAML | Cloud SaaS |
| **Self-hosted** | Si | Si | Si | **No** (server NextDNS) |
| **Interfaccia** | Web (PHP/lighttpd) | Web (integrata, no dipendenze) | Nessuna (solo config file) | Web (cloud) |
| **DNS-over-HTTPS (DoH)** | No nativo (richiede proxy) | **Si** (nativo, server e client) | **Si** (nativo) | **Si** (cloud) |
| **DNS-over-TLS (DoT)** | No nativo | **Si** (nativo) | **Si** | **Si** |
| **Filtro per client** | Parziale (group management) | **Si** (regole per client) | **Si** | **Si** |
| **DHCP server** | Si | Si | No | No |
| **Risorse (RAM)** | ~120MB | ~70MB | ~20MB | 0 (cloud) |
| **RPi ARM64** | Si | Si | Si | N/A (cloud) |
| **Blocklist** | Gravity (SQLite, 80k+ domini) | Filtri stile AdBlock (piu' flessibili) | Lista link in YAML | Preset + custom |
| **Community** | Enorme (piu' vecchio, piu' documentato) | Grande (in crescita rapida) | Piccola (nichia) | Media |
| **Costo** | $0 | $0 | $0 | $0 (300k query/mese) / $20/anno |

## AdGuard Home: l'alternativa principale - quando preferirla

AdGuard Home ha due vantaggi che Pi-hole non ha: **DoH/DoT nativo** (il traffico DNS tra AdGuard e l'upstream e' cifrato senza proxy aggiuntivi) e **filtri per client** (puoi applicare blocklist diverse a dispositivi diversi - es. blocklist piu' aggressiva per i figli, piu' permissiva per il tuo PC).

**Installazione su Docker (stesse porte di Pi-hole):**

```bash
docker run -d \
    --name adguardhome \
    --restart=always \
    --net macvlan_lan \
    --ip 192.168.0.250 \
    -v /home/pi/adguard/work:/opt/adguardhome/work \
    -v /home/pi/adguard/conf:/opt/adguardhome/conf \
    adguard/adguardhome

# Setup wizard su http://192.168.0.250:3000 (primo avvio)
# Dopo il setup, dashboard su http://192.168.0.250:80
```

**Perche' ho scelto Pi-hole e non AdGuard Home:**

1. **Community e documentazione**: Pi-hole e' il progetto piu' maturo, con migliaia di guide e troubleshooting disponibili. Per un progetto educativo, la documentazione conta
2. **Integrazione Wazuh**: Pi-hole scrive log in formato standard syslog (`/var/log/pihole.log`), facilmente ingeribili da Wazuh. AdGuard Home usa un formato proprietario che richiede decoder custom
3. **FTL engine**: Il motore FTL di Pi-hole e' scritto in C e gestisce le query con latenza inferiore al millisecondo. AdGuard Home in Go e' comunque veloce, ma FTL e' piu' efficiente su hardware limitato come il Pi

**Quando scegliere AdGuard Home:** Se hai bisogno di DoH/DoT nativo (senza configurare un proxy come `cloudflared`), o se vuoi regole diverse per dispositivi diversi (es. bambini vs adulti).

## Blocky: l'alternativa minimale per chi vuole solo YAML

Blocky e' per chi trova Pi-hole e AdGuard Home "troppi" - nessuna interfaccia web, solo un file YAML:

```bash
# Installazione via Docker
docker run -d \
    --name blocky \
    --restart=always \
    -p 53:53/udp -p 53:53/tcp \
    -v /home/pi/blocky/config.yml:/app/config.yml \
    spx01/blocky

# config.yml
cat > /home/pi/blocky/config.yml <<'EOF'
upstream:
  default:
    - 1.1.1.1
    - 8.8.8.8
blocking:
  blackLists:
    ads:
      - https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts
  clientGroupsBlock:
    default:
      - ads
port: 53
httpPort: 4000
EOF
```

~20MB di RAM, nessuna dipendenza, configurazione dichiarativa. Ideale per chi preferisce Git + YAML a dashboard web.

## Domande che un analista si farebbe

**"DoH (DNS-over-HTTPS) rende Pi-hole inutile?"**

Parzialmente. Se un dispositivo usa DoH direttamente (Firefox con DoH abilitato verso Cloudflare), le query DNS **bypassano completamente Pi-hole** perche' viaggiano su HTTPS porta 443, non su DNS porta 53.

Mitigazioni:
1. **Bloccare gli IP dei resolver DoH noti** su UFW:
```bash
# Blocca i principali resolver DoH (forza i dispositivi a usare Pi-hole)
sudo ufw deny out to 1.1.1.1 port 443 comment "Block Cloudflare DoH"
sudo ufw deny out to 8.8.8.8 port 443 comment "Block Google DoH"
sudo ufw deny out to 9.9.9.9 port 443 comment "Block Quad9 DoH"
```
2. **Disabilitare DoH nei browser** via policy di gruppo (enterprise) o configurazione manuale
3. **Usare Pi-hole stesso come resolver DoH** con `cloudflared` come proxy upstream

**"Un ad-blocker DNS basta per la privacy?"**

No. Il blocco DNS previene il caricamento di risorse da domini noti di tracking, ma non protegge da:
- **Fingerprinting del browser**: il server identifica il dispositivo dalle caratteristiche del browser (canvas, WebGL, font installati) senza cookie
- **Tracking first-party**: se `example.com` traccia i suoi utenti sul proprio dominio, Pi-hole non lo blocca (blocca solo domini terzi)
- **Tracking a livello di app**: molte app mobile usano SDK di tracking con IP hardcoded, non risolvibili via DNS

Per una protezione completa serve: Pi-hole (DNS) + uBlock Origin (browser) + VPN (nasconde IP) + hardening browser (Firefox con resistFingerprinting).
