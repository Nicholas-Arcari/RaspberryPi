>  [English](configurazione-rete.en.md) |  **Italiano**

# Configurazione Router e Client

## Configurazione del router come relay DNS

Affinchè **tutti** i dispositivi della rete usino Pi-hole automaticamente, devi dire al router di distribuire l'IP del Pi-hole come DNS tramite DHCP.

Sul router (TP-Link Archer C50 → DHCP → DHCP Settings):

- **Primary DNS**: `192.168.0.250` (IP del Pi-hole)
- **Secondary DNS**: due opzioni:
  - **Hardcore (blocco al 100%)**: lasciare vuoto o `0.0.0.0`. Se Pi-hole va giù, niente Internet - ma nessuna query bypassa il blocco
  - **Failover**: `1.1.1.1` (Cloudflare) o `8.8.8.8` (Google). Se Pi-hole va giù, Internet continua a funzionare, ma alcune query potrebbero bypassare il filtro anche quando Pi-hole è attivo (il SO potrebbe preferire il DNS secondario per velocità)

![Configurazione DHCP del router - Pi-hole come DNS primario](../img/router-dhcp-dns-settings.jpg)

## Perchè i dispositivi non aggiornano subito il DNS

Dopo aver modificato il DNS sul router, i dispositivi non lo usano immediatamente. Il motivo è il **lease DHCP**: ogni dispositivo ha un "contratto" con il router che include l'indirizzo IP assegnato e il DNS. Questo contratto ha una durata (tipicamente 24 ore). Fino al rinnovo, il dispositivo continua a usare il vecchio DNS.

**Soluzioni:**
- Riavviare il Wi-Fi/Ethernet sul dispositivo (forza un nuovo lease)
- Oppure, su Windows: `ipconfig /release && ipconfig /renew`
- Oppure, su Linux/macOS: `sudo dhclient -r && sudo dhclient`

## Il problema del DNS-over-HTTPS (DoH)

**Attenzione critica:** I browser moderni (Chrome, Edge, Firefox, Brave) possono usare **DNS-over-HTTPS (DoH)**, che invia le query DNS direttamente ai server del browser (es. `dns.google`, `cloudflare-dns.com`) bypassando completamente il DNS del sistema operativo e quindi Pi-hole.

Se vedi ancora pubblicità dopo la configurazione, controlla:

**Chrome/Edge:** Impostazioni → Privacy e sicurezza → Sicurezza → **Disattiva "Usa DNS sicuro"**

![Chrome - Disabilitazione del DNS sicuro (DoH) per permettere a Pi-hole di funzionare](../img/chrome-disable-doh.jpg)

![Pi-hole in azione - blocco attivo delle query di advertising e tracking](../img/pihole-blocking-active.jpg)
