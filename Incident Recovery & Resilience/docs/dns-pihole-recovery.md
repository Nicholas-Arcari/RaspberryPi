>  [English](dns-pihole-recovery.en.md) |  **Italiano**

# Runbook 02 - DNS / Pi-hole recovery

> **Quando usare questo runbook:** i nomi non si risolvono piu' in tutta la casa, il Pi-hole non risponde, oppure il dominio DDNS e' scaduto e la VPN non e' piu' raggiungibile dall'esterno. Questo runbook copre due "scadenze" diverse ma spesso confuse: il **servizio DNS interno** (Pi-hole) e il **nome DDNS pubblico** (accesso remoto).

Prima di tutto, la parte che spaventa: **perche' un DNS che cade e' un incidente serio e non un fastidio.**

---

## Parte A - Perche' il DNS e' un single point of failure (e un controllo di sicurezza)

Nel lab, il Pi-hole (`192.168.0.250`) e' il **DNS unico** distribuito dal DHCP a tutta la LAN. Questo ha due conseguenze che vanno capite prima di trovarsi nell'emergenza.

### A.1 Impatto sui servizi interni (RTO bassissimo)

Il DNS ha l'RTO piu' basso di tutto il lab: se cade, **entro pochi secondi** ogni dispositivo che chiede un nome fallisce.

```
Pi-hole giu'
   |
   +-- Smartphone/PC/Smart TV: "sito non raggiungibile" anche se Internet e' su
   +-- WireGuard che risolve endpoint per nome: tunnel non si stabilisce
   +-- Container che chiamano servizi per hostname: errori a catena
   +-- OMV/Portainer per IP funzionano ancora (non usano nomi) -> indizio diagnostico
```

Nota diagnostica preziosa: se raggiungi il Pi **per IP** (`https://192.168.0.102`) ma non **per nome**, la rete e' sana e il colpevole e' il DNS. E' esattamente il test `ping 1.1.1.1` OK / `ping google.com` KO del [Runbook 00](triage-diagnostica.md).

### A.2 Impatto sulla sicurezza (il punto meno ovvio)

Il Pi-hole non e' solo un ad-blocker: e' un **controllo di sicurezza**. Blocca a livello DNS domini di malware, phishing e telemetria, e la sua query log e' una fonte di visibilita' sul traffico della rete. Quando muore, non perdi solo le pubblicita':

- **Perdi il filtro anti-malware/phishing DNS.** I dispositivi che fanno fallback su un altro resolver (ISP, router, `8.8.8.8` hardcoded nella Smart TV) tornano a risolvere domini che il sinkhole bloccava.
- **Perdi la telemetria.** Niente query log = un canale di detection in meno per accorgerti di un dispositivo compromesso che chiama casa (C2).
- **Liberi un IP pesante.** L'indirizzo `192.168.0.250` era "il DNS di tutti". Se Pi-hole e' giu' e un dispositivo ostile sulla LAN si appropria di quell'IP, diventa il resolver di tutta la casa: **DNS hijacking / man-in-the-middle completo**. Un Pi-hole morto non e' solo un'assenza, e' una sedia vuota che qualcuno puo' occupare. Vedi [Runbook 06](integrita-post-downtime.md).

Per questo il DNS va trattato come infrastruttura critica, con un piano di ripristino e non solo un "poi lo riavvio".

---

## Parte B - Il servizio Pi-hole non risponde

### B.1 Diagnosi

```bash
# Il resolver risponde? (dall'host o da un client)
dig @192.168.0.250 google.com +short
# Timeout/SERVFAIL -> Pi-hole giu' o FTL morto

# Il container e' vivo? (gira in Docker su rete MacVLAN)
docker ps -a --filter name=pihole --format "{{.Names}}\t{{.Status}}"
# "Up" atteso. "Exited"/"Restarting" -> B.2

# Il motore FTL (il DNS/DHCP di Pi-hole) e' attivo dentro al container?
docker exec pihole pihole status
# Atteso: "FTL is listening on port 53" + "Pi-hole blocking is enabled"

# La porta 53 e' davvero in ascolto sull'IP MacVLAN?
docker exec pihole ss -tulnp | grep :53
```

### B.2 Ripristino, dal meno al piu' invasivo

```bash
# 1. Riavvio soft del solo motore DNS (non tocca il container)
docker exec pihole pihole restartdns

# 2. Riavvio del container
docker restart pihole

# 3. Se non riparte: leggi il perche'
docker logs pihole --tail 50
#   "address already in use :53"  -> qualcos'altro tiene la 53 (systemd-resolved?)
#   "gravity.db ... malformed"    -> database blocklist corrotto (B.3)
#   errori MacVLAN / no route     -> problema di rete Docker (B.4)

# 4. Ricreazione pulita dal compose (i dati persistono nei volumi montati)
cd /path/al/compose/pihole && docker compose up -d --force-recreate
```

### B.3 Database gravity corrotto

```bash
# gravity.db e' il DB dei domini bloccati. Se corrotto, FTL non blocca o non parte.
docker exec pihole sqlite3 /etc/pihole/gravity.db "PRAGMA integrity_check;"
# Atteso: "ok". Altro -> rigenera:
docker exec pihole pihole -g       # ri-scarica e ricostruisce le blocklist
```

### B.4 Il caso MacVLAN: l'host non parla col Pi-hole

Pi-hole usa una rete **MacVLAN** con IP dedicato (`192.168.0.250`). Effetto collaterale noto di MacVLAN: **l'host Docker non riesce a raggiungere il proprio container** sulla stessa MacVLAN (isolamento by design). I client LAN lo raggiungono, ma l'host no. Se il tuo test `dig` dall'host fallisce ma dai client va, non e' un guasto: e' il comportamento MacVLAN. Testa sempre **anche da un secondo dispositivo** prima di dichiarare Pi-hole morto.

---

## Parte C - Emergenza: ripristinare la risoluzione SUBITO

Mentre ripari Pi-hole, la casa e' senza DNS. Ripristina la risoluzione in fretta e in sicurezza:

**Opzione 1 - Bypass temporaneo sul router (rapido, tutta la LAN).**
Nel router (`192.168.0.1`), imposta come DNS DHCP un resolver pubblico fidato con DNSSEC (`1.1.1.1` / `9.9.9.9`). Riavvia il DHCP o attendi il rinnovo lease. Perdi il sinkhole ma torni operativo. **Ricordati di rimettere `192.168.0.250` quando Pi-hole torna**, altrimenti resti senza protezione DNS senza accorgertene.

**Opzione 2 - Fix sul singolo dispositivo (chirurgico).**
Sul PC da cui devi lavorare, imposta manualmente `1.1.1.1` come DNS finche' non hai finito.

> **Compromesso di design.** Un DNS secondario permanente (es. il router come fallback) elimina il single point of failure, ma **defeat il sinkhole**: quando Pi-hole rallenta, i client usano il secondario e saltano il filtro. Le due strade corrette sono: (a) accettare l'RTO e ripristinare in fretta con un solo DNS; oppure (b) mettere **due Pi-hole** (un secondo su un altro dispositivo) come DNS primario+secondario, cosi' hai ridondanza senza perdere il filtro. Non usare mai un resolver non filtrante come secondario "per sicurezza": e' la porta di servizio che vanifica il sinkhole.

---

## Parte D - Il nome DDNS pubblico e' scaduto

Questo e' l'altro "DNS scaduto", diverso dal Pi-hole. L'accesso remoto (WireGuard) punta a un nome dinamico tipo `miodominio.ddns.net` (No-IP). I nomi No-IP gratuiti **scadono se non confermati periodicamente**, e l'IP pubblico e' dinamico dietro CGNAT: se il record non e' aggiornato o il nome e' scaduto, **la VPN non e' piu' raggiungibile da fuori**.

### D.1 Diagnosi

```bash
# Il nome DDNS risolve, e verso quale IP?
dig +short miodominio.ddns.net
# Vuoto -> nome scaduto/cancellato.  IP diverso da quello pubblico reale -> record non aggiornato

# Qual e' l'IP pubblico reale visto da Internet?
curl -s https://api.ipify.org ; echo
# Confronta con il dig sopra: devono coincidere
```

### D.2 Cause e fix

| Sintomo | Causa | Fix |
|---|---|---|
| `dig` vuoto | Nome DDNS scaduto (mancata conferma No-IP) | Rientra nel pannello No-IP, riconferma/rinnova il nome |
| IP del record != IP reale | Client DDNS fermo (sul router o sul Pi) | Riavvia l'updater DDNS; forza un update manuale |
| Risolve giusto ma la VPN non entra | Non e' il DNS: e' port-forward o **CGNAT** | Vedi [Runbook 04](vpn-e-container-recovery.md) |

> **La trappola CGNAT.** L'uplink FWA (Comeser) e' dietro CGNAT: non hai un IP pubblico dedicato, quindi il port forwarding puo' non funzionare **anche con il DDNS perfetto**. In quel caso il DDNS non basta e serve un piano B (tunnel in uscita come Ngrok/Cloudflare Tunnel, o chiedere un IP pubblico al provider). Il dettaglio e' nel [Runbook 04](vpn-e-container-recovery.md) e in [VPN / rete-dmz](../../VPN%20(Virtual%20Private%20Network)/docs/rete-dmz.md).

### D.3 L'angolo sicurezza wifi/modem

Il DDNS e il DNS toccano direttamente la sicurezza del perimetro domestico:

- **Un nome DDNS scaduto puo' essere ri-registrato da altri.** Se lasci scadere `miodominio.ddns.net` e qualcuno lo riprende, i tuoi client che si fidano di quel nome puntano a un host che non controlli. Non lasciare scadere nomi che usi per l'accesso.
- **Il DNS del modem/router e' un bersaglio.** Il router distribuisce quale DNS usare. Se un attaccante cambia il DNS nel router (credenziali di default, UI esposta), reindirizza **tutta** la casa: e' DNS hijacking a livello gateway. Verifica: DNS del router = `192.168.0.250` (o il fallback scelto), UI del router non esposta a Internet, password del router cambiata.
- **DNSSEC e DNS rebinding.** Abilita DNSSEC su Pi-hole per validare le risposte (anti-spoofing). Tieni attiva la protezione **DNS rebinding** del router/Pi-hole per impedire che nomi esterni risolvano a IP privati interni.

---

## Verifica di ripristino

```bash
# Da un client (non dall'host, per via del MacVLAN):
dig @192.168.0.250 google.com +short          # risolve -> DNS su
dig @192.168.0.250 ads.doubleclick.net +short # 0.0.0.0 -> sinkhole di nuovo attivo
dig +short miodominio.ddns.net                # = IP pubblico reale -> DDNS ok
```

Poi ri-esegui la sezione DNS della [checklist post-installazione](../../docs/checklist-post-installazione.md).

---

## Prevenzione

- Decidi la strategia DNS: **RTO accettato con Pi-hole singolo** oppure **due Pi-hole ridondanti**. Mai un secondario non filtrante.
- Metti un promemoria per la **riconferma periodica del nome No-IP** (o passa a un provider DDNS senza scadenza).
- Fai monitorare il DNS da Wazuh: un alert se la porta 53 del Pi-hole smette di rispondere ti avvisa prima che lo faccia tua sorella.
- Cambia le credenziali del router e non esporne la UI: il gateway e' il vero master del DNS di casa.

---

## Collegamenti

- La VPN non entra anche col DNS a posto -> [Runbook 04: VPN e container](vpn-e-container-recovery.md)
- Sospetti DNS hijacking / MITM -> [Runbook 06: integrita' post-downtime](integrita-post-downtime.md)
- Come funziona il DNS e Pi-hole FTL -> [ADS Blocker / protocollo-dns](../../ADS%20Blocker/docs/protocollo-dns.md), [ftl-engine](../../ADS%20Blocker/docs/ftl-engine.md)
- Troubleshooting Pi-hole specifico -> [ADS Blocker / troubleshooting](../../ADS%20Blocker/docs/troubleshooting.md)
