>  [English](troubleshooting.en.md) |  **Italiano**

# Troubleshooting - Problemi reali e soluzioni

## Problema 1: Container in bootloop (errore password)

**Sintomo:** Il container si riavvia all'infinito. I log (`docker logs wireguard`) mostrano errori relativi all'hash della password.

**Causa:** La versione 14+ di wg-easy ha cambiato il formato della password: non accetta più testo in chiaro nella variabile `PASSWORD`, ma richiede un hash Bcrypt pre-generato nella variabile `PASSWORD_HASH`.

**Soluzione:** Ho fissato la versione a **13** nel Docker Compose (`image: ghcr.io/wg-easy/wg-easy:13`), che accetta ancora password in chiaro. Se vuoi usare la v14+, devi:

```bash
# Generare l'hash Bcrypt
docker run -it ghcr.io/wg-easy/wg-easy wgpw 'LaMiaPasswordSegretà

# Usare il risultato nel compose:
# - PASSWORD_HASH=$$2a$$12$$xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
# Nota: i $ vanno raddoppiati ($$) nel file YAML per evitare l'escape
```

## Problema 2: Connesso ma senza Internet ("Il limbo")

**Sintomo:** Il telefono si connette alla VPN (handshake completato, traffico visibile), ma nessuna pagina web si carica.

**Causa:** Avevo impostato `WG_DEFAULT_DNS=192.168.0.250` pensando di usare il Pi-hole futuro. Ma il Pi-hole non era ancora installato. Il client VPN inviava le query DNS a un server inesistente.

**Soluzione:** Cambiato a `WG_DEFAULT_DNS=8.8.8.8` (Google DNS) e, **passaggio critico**, ho cancellato e ricreato il client dalla Web UI. Le impostazioni DNS vengono "cotte" nel file di configurazione del client al momento della creazione. Modificare il server-side non aggiorna i client già generati.

## Problema 3: Instabilità su reti mobili 4G

**Sintomo:** Su Wi-Fi di casa, la VPN funziona perfettamente. Su rete mobile 4G, la connessione è lenta o cade dopo pochi secondi.

**Causa:** Frammentazione dei pacchetti. Il MTU di default di WireGuard (~1420) sommato all'overhead dell'operatore mobile (che incapsula ulteriormente il traffico) superava il MTU fisico del link, causando frammentazione e ritrasmissioni.

**Soluzione:** Aggiunto `WG_MTU=1280` nel Docker Compose. 1280 byte è il valore più conservativo che garantisce la compatibilità con qualsiasi rete, incluse quelle mobili con tunnel GTP.

---

## Utilizzo quotidiano

1. Apri il browser e vai su `http://<IP_RASPBERRY>:51821`
2. Inserisci la password
3. Clicca **+ New Client** e dai un nome (es. "iPhone", "Laptop-Lavoro")
4. Scarica l'app **WireGuard** sul dispositivo (iOS, Android, Windows, macOS, Linux)
5. Scansiona il **QR Code** generato dalla Web UI (o scarica il file `.conf`)
6. Attiva la VPN quando sei fuori casa

### Test di verifica

Per confermare che la VPN funzioni:

1. Connetti il telefono all'**hotspot cellulare** (simula una rete esterna)
2. Attiva la VPN
3. Prova a raggiungere la Web UI di Portainer (`https://192.168.0.102:9443`)
4. Se si carica, la VPN funziona e hai accesso alla LAN di casa
