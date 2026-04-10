# Security Assessment & Hardening - Red Teaming del proprio Lab

Questa e' stata la fase piu' critica e istruttiva dell'intero progetto. Una volta attivi l'Honeypot e il SIEM, ho voluto testarne la sicurezza simulando di essere un attaccante esterno (Red Teaming). L'obiettivo: capire se il mio Raspberry Pi fosse sicuro o se, paradossalmente, avessi appena aperto una porta verso la mia rete domestica.

---

## Metodologia

L'approccio segue il ciclo standard di un penetration test:

1. **Reconnaissance**: scoprire quali servizi sono esposti
2. **Enumeration**: analizzare i servizi per vulnerabilita'
3. **Exploitation**: tentare di sfruttare le debolezze trovate
4. **Post-exploitation**: verificare cosa un attaccante potrebbe fare dopo l'accesso
5. **Remediation**: correggere le vulnerabilita' scoperte

---

## Indice della documentazione

| Documento | Contenuto |
|---|---|
| [Fase 1: Reconnaissance](docs/reconnaissance.md) | Scansione Nmap SYN + version detection, output reale analizzato riga per riga, DMZ come causa |
| [Fase 2-3: Exploitation e Post-Exploitation](docs/exploitation.md) | Brute force con Hydra, test isolamento container, rischio pivot LAN |
| [Fase 4-6: Remediation](docs/remediation.md) | UFW rules (ordine critico), agent disconnesso, CGNAT + Ngrok, tabella vulnerabilita' corrette |
| [Correlazione eventi + Test finale](docs/correlazione-eventi.md) | Alert Wazuh JSON reale, timeline attacco, query Dashboard, correlazione UFW, test end-to-end |
| [Threat Model STRIDE](docs/threat-model.md) | Asset, superficie d'attacco, attaccanti, analisi STRIDE per Honeypot/VPN/SIEM/NAS, rischi residui |
