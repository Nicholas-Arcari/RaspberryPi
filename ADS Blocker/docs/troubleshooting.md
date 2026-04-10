# Troubleshooting e Verifica del funzionamento

## Verifica del funzionamento

### Dashboard Pi-hole

Accedere a `http://192.168.0.250/admin` e verificare:

- **Total Queries**: il numero deve crescere (ogni dispositivo fa decine di query DNS al minuto)
- **Queries Blocked**: se e' 0 dopo diversi minuti, qualcosa non funziona
- **Percentage Blocked**: tipicamente tra il 15% e il 40% del traffico DNS e' ads/tracking

### Query Log

La sezione **Query Log** mostra ogni singola query DNS in tempo reale:

![Pi-hole Query Log - dettaglio delle query DNS con client, dominio, tipo e stato (Allow/Deny)](../img/pihole-query-log.jpg)

Da qui puoi vedere:
- Quale dispositivo ha fatto la query (colonna **Client**)
- Quale dominio e' stato richiesto
- Se e' stato bloccato (rosso) o permesso (verde)
- Il tempo di risposta in millisecondi

### Test con Speedtest

Un test pratico: visita un sito con molte pubblicita' (es. speedtest.net) e osserva la differenza:

![Speedtest.net - le pubblicita' laterali sono visibili perche' il Pi-hole non era ancora configurato come DNS](../img/speedtest-ads-visible.jpg)

Dopo aver configurato Pi-hole come DNS, le pubblicita' scompariranno dai siti web. Le aree che ospitavano ads appariranno come spazi vuoti o non verranno caricate affatto.

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

### La dashboard non e' raggiungibile

Verifica che il container sia in esecuzione e che l'IP MacVLAN sia attivo:

```bash
docker ps | grep pihole
docker inspect pihole | grep IPAddress
ping 192.168.0.250  # Da un ALTRO dispositivo (non dal Pi - vedi sotto)
```

### Il Raspberry Pi non raggiunge Pi-hole

Per design di sicurezza del kernel Linux, l'host (Raspberry Pi) **non puo' comunicare** con i container MacVLAN sulla stessa interfaccia (vedi sezione VLAN per la spiegazione tecnica). Questo non e' un bug - e' una feature di sicurezza.

**Conseguenza pratica:** Il Raspberry Pi stesso non puo' usare Pi-hole come DNS. Per un server headless, questo non e' un problema - il Pi non naviga su Internet.
