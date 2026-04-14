>  [English](troubleshooting.en.md) |  **Italiano**

# Troubleshooting e Verifica del funzionamento

## Verifica del funzionamento

### Dashboard Pi-hole

Accedere a `http://192.168.0.250/admin` e verificare:

- **Total Queries**: il numero deve crescere (ogni dispositivo fa decine di query DNS al minuto)
- **Queries Blocked**: se è 0 dopo diversi minuti, qualcosa non funziona
- **Percentage Blocked**: tipicamente tra il 15% e il 40% del traffico DNS è ads/tracking

### Query Log

La sezione **Query Log** mostra ogni singola query DNS in tempo reale:

![Pi-hole Query Log - dettaglio delle query DNS con client, dominio, tipo e stato (Allow/Deny)](../img/pihole-query-log.jpg)

Da qui puoi vedere:
- Quale dispositivo ha fatto la query (colonna **Client**)
- Quale dominio è stato richiesto
- Se è stato bloccato (rosso) o permesso (verde)
- Il tempo di risposta in millisecondi

### Test con Speedtest

Un test pratico: visita un sito con molte pubblicità (es. speedtest.net) e osserva la differenza:

![Speedtest.net - le pubblicità laterali sono visibili perchè il Pi-hole non era ancora configurato come DNS](../img/speedtest-ads-visible.jpg)

Dopo aver configurato Pi-hole come DNS, le pubblicità scompariranno dai siti web. Le aree che ospitavano ads appariranno come spazi vuoti o non verranno caricate affatto.

---

## Troubleshooting

### "I comandi `pihole` non funzionano dal terminale del Pi"

I comandi Pi-hole (`pihole -t`, `pihole status`, ecc.) sono installati **dentro** il container, non sull'host. Dal terminale del Raspberry:

```bash
# Corretto - esegui il comando dentro il container
docker exec -it pihole pihole status

# Errato - il binario non esiste sull'host
pihole status  # Command not found
```

### La dashboard non è raggiungibile

Verifica che il container sia in esecuzione e che l'IP MacVLAN sia attivo:

```bash
docker ps | grep pihole
docker inspect pihole | grep IPAddress
ping 192.168.0.250  # Da un ALTRO dispositivo (non dal Pi - vedi sotto)
```

### Il Raspberry Pi non raggiunge Pi-hole

Per design di sicurezza del kernel Linux, l'host (Raspberry Pi) **non può comunicare** con i container MacVLAN sulla stessa interfaccia (vedi sezione VLAN per la spiegazione tecnica). Questo non è un bug - è una feature di sicurezza.

**Conseguenza pratica:** Il Raspberry Pi stesso non può usare Pi-hole come DNS. Per un server headless, questo non è un problema - il Pi non naviga su Internet.
