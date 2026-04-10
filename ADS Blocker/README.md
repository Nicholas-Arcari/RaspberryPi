# Pi-hole - DNS Sinkhole per il blocco di pubblicita' e tracking

Questa guida documenta l'installazione di Pi-hole su Docker con rete MacVLAN, la configurazione del router per usarlo come DNS primario, e i problemi reali che ho incontrato (spoiler: il conflitto della porta 80 con OpenMediaVault).

---

## Come funziona in breve

Pi-hole si posiziona come **DNS server locale** sulla rete. Tutte le query DNS dei dispositivi passano attraverso di lui: se il dominio richiesto e' in una blocklist (advertising, tracking), Pi-hole risponde con un indirizzo nullo (`0.0.0.0`) e la risorsa non viene mai scaricata. Per il browser, e' come se il server di pubblicita' non esistesse.

```
Dispositivo → Pi-hole (192.168.0.250) → Il dominio e' in blocklist?
                                          ├── SI → Risponde 0.0.0.0 (blocco)
                                          └── NO → Inoltra al DNS upstream (8.8.8.8, 1.1.1.1)
```

A differenza dei browser ad-blocker (uBlock Origin, AdBlock), Pi-hole protegge **tutti** i dispositivi della rete (TV, IoT, smartphone, console) e blocca il tracking anche dalle app, non solo dal browser.

---

## Indice

| Documento | Contenuto |
|---|---|
| [Protocollo DNS](docs/protocollo-dns.md) | Risoluzione DNS (ricorsiva vs iterativa), gerarchia, tipi di record con esempi `dig`, anatomia del pacchetto DNS, dove si inserisce Pi-hole |
| [Installazione Pi-hole](docs/installazione-pihole.md) | Conflitto porta 80 con OMV, soluzione Docker + MacVLAN, configurazione di rete, Docker Compose, avvio e password |
| [Configurazione Rete](docs/configurazione-rete.md) | Router come relay DNS, configurazione DHCP, lease DHCP e aggiornamento client, problema DNS-over-HTTPS (DoH) |
| [FTL Engine](docs/ftl-engine.md) | Motore FTL (Faster Than Light), gravity.db (SQLite), regex/wildcard blocking, DNSSEC |
| [Alternative](docs/alternative.md) | Pi-hole vs AdGuard Home vs Blocky vs NextDNS, installazione AdGuard e Blocky su Docker, domande da analista (DoH, privacy) |
| [Troubleshooting](docs/troubleshooting.md) | Verifica funzionamento (dashboard, query log, speedtest), comandi nel container, problemi MacVLAN |

---

## Sviluppi futuri

La struttura MacVLAN permette di aggiungere altri container con IP dedicati sulla rete locale, semplicemente modificando l'indirizzo IP nel Docker Compose:

| Servizio | IP dedicato | Porta |
|---|---|---|
| Pi-hole | 192.168.0.250 | 80, 53 |
| Honeypot | 192.168.0.251 | 2222, 2223 |
| Home Assistant | 192.168.0.252 | 8123 |

---

Prossimo step: [Honeypot](../Honeypot/) - deployment di Cowrie per catturare attaccanti.
