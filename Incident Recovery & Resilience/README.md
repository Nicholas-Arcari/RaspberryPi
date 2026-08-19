>  [English](README.en.md) |  **Italiano**

# Incident Recovery & Resilience

> Cosa fare quando qualcosa si rompe, quando resti chiuso fuori dal sistema, quando sospetti una compromissione o quando devi semplicemente dimostrare - a te stesso - che le difese funzionano ancora. Questa sezione raccoglie i **runbook operativi**: guide passo-passo da seguire sotto stress, quando non c'e' tempo di studiare ma serve una procedura chiara.

Il resto del repository documenta come **costruire** il lab. Questa sezione documenta come **tenerlo in vita**: diagnosi, recupero, verifica e continuita' operativa. E' la differenza tra un progetto da vetrina e un sistema che qualcuno gestisce davvero nel tempo.

---

## Una nota sulla terminologia

"Incident recovery" e' il termine intuitivo, ma copre in realta' quattro discipline distinte che questa sezione affronta in modo integrato:

| Disciplina | Domanda a cui risponde | Orizzonte temporale |
|---|---|---|
| **Troubleshooting** | "Perche' questo servizio non funziona?" | Minuti |
| **Incident Response (IR)** | "Sono stato compromesso? Come contengo e capisco cosa e' successo?" | Ore |
| **Disaster Recovery (DR)** | "Il sistema e' distrutto: come lo ricostruisco e recupero i dati?" | Ore / giorni |
| **Business Continuity (BC)** | "Quali servizi devono restare su, e per quanto posso reggere senza?" | Progettuale |

Nel linguaggio professionale la BC si misura con due parametri che useremo come bussola anche in un homelab:

- **RTO (Recovery Time Objective):** quanto tempo posso restare senza un servizio prima che diventi un problema serio. Il DNS (Pi-hole) ha un RTO bassissimo: se cade, in pochi minuti tutta la LAN perde la risoluzione dei nomi. Il honeypot ha un RTO alto: se e' giu' per un giorno, non succede nulla di critico.
- **RPO (Recovery Point Objective):** quanti dati posso permettermi di perdere. Le regole custom di Wazuh e le chiavi WireGuard hanno un RPO vicino a zero (ricrearle e' doloroso): vanno nel backup. La cache DNS di Pi-hole ha un RPO altissimo (si rigenera da sola).

Ragionare per RTO/RPO trasforma la domanda vaga "cosa faccio se si rompe?" in una priorita' operativa precisa.

---

## Le tre regole d'oro (leggerle prima che serva)

Un recovery riuscito si decide **prima** dell'incidente, non durante. Tre principi non negoziabili:

1. **Accesso out-of-band (OOB) sempre disponibile.** Non puoi riparare cio' che non riesci a raggiungere. Se la rete cade o una regola firewall ti chiude fuori, l'unica via e' l'accesso fisico: monitor HDMI + tastiera USB, oppure la console seriale UART. Tieni sempre a portata di mano il cavo e la MicroSD di recovery. Vedi [accesso-perso-e-boot.md](docs/accesso-perso-e-boot.md).
2. **La baseline si cattura da sani, non da malati.** Non puoi rilevare una modifica se non sai com'era il sistema "sano". Gli hash dei file critici, la lista dei servizi attesi, la mappa ARP della LAN, la configurazione firewall: vanno registrati **ora**, mentre il sistema e' integro. Wazuh FIM fa gran parte di questo lavoro, ma solo se la baseline e' stata presa prima. Vedi [integrita-post-downtime.md](docs/integrita-post-downtime.md).
3. **Un backup non testato non e' un backup.** Un archivio che non hai mai provato a ripristinare e' solo una speranza. La procedura di restore va eseguita almeno una volta, a freddo, per scoprire cosa manca **prima** che serva davvero. Vedi [backup-e-disaster-recovery.md](docs/backup-e-disaster-recovery.md).

---

## Come si usa questa sezione: il triage

Quando qualcosa non va, non si parte dal servizio applicativo: si diagnostica lo stack **dal basso verso l'alto**, perche' un guasto in basso si manifesta come sintomo in alto. Pi-hole "non blocca gli ads" puo' essere un problema di Pi-hole, ma anche di rete, di Docker, o di alimentazione.

```
   LIVELLO                     "Se e' rotto qui, sopra vedi..."         RUNBOOK
   --------------------------------------------------------------------------------
   [7] Applicazione     Dashboard, alert, blocco ads       -> wazuh / dns / vpn
        ^
   [6] Container        docker ps, log container           -> vpn-e-container
        ^
   [5] Servizi host     systemctl, porte in ascolto        -> triage-diagnostica
        ^
   [4] DNS / nomi       dig, risoluzione                   -> dns-pihole-recovery
        ^
   [3] IP / routing     ping gateway, ip addr, ip route    -> lan-health-check
        ^
   [2] Link / L2        cavo, link, switch, VLAN tag       -> lan-health-check
        ^
   [1] OS / kernel      boot, kernel panic, fsck           -> accesso-perso-e-boot
        ^
   [0] Hardware/power   LED, alimentatore, NVMe, temp      -> accesso-perso-e-boot
```

Regola pratica: **verifica prima il livello piu' basso plausibile.** Se il ping al gateway (livello 3) fallisce, e' inutile investigare Pi-hole (livello 7). Il runbook [triage-diagnostica.md](docs/triage-diagnostica.md) e' l'albero decisionale completo: parti sempre da li' se non sai da dove cominciare.

---

## Indice dei runbook

Ogni runbook risponde a una o piu' domande concrete del tipo "cosa succede se...".

| # | Runbook | Risponde a |
|---|---|---|
| 00 | [Triage e diagnostica](docs/triage-diagnostica.md) | "Qualcosa non va e non so da dove partire. Come isolo la causa in modo sistematico?" |
| 01 | [Accesso perso e boot failure](docs/accesso-perso-e-boot.md) | "SSH non funziona piu'. Mi sono chiuso fuori con UFW. Kernel panic e non riesco piu' ad accedere. Il boot da NVMe fallisce." |
| 02 | [DNS / Pi-hole recovery](docs/dns-pihole-recovery.md) | "Il DNS e' caduto o il dominio DDNS e' scaduto: cosa succede ai servizi interni, al Wi-Fi e alla sicurezza? Come ripristino?" |
| 03 | [Wazuh dashboard inaccessibile](docs/wazuh-dashboard-recovery.md) | "Non riesco piu' a entrare nella dashboard Wazuh. Come capisco la causa (indexer? certificati? disco? password?) e la risolvo?" |
| 04 | [VPN e container recovery](docs/vpn-e-container-recovery.md) | "La VPN WireGuard non mi fa piu' entrare da fuori. Un container e' morto o non riparte. Docker non si avvia." |
| 05 | [Verifica delle difese attive](docs/verifica-difese-attive.md) | "Come faccio a essere sicuro che firewall, Fail2ban, FIM, honeypot e segmentazione funzionino ancora davvero, non solo che siano 'su'?" |
| 06 | [Integrita' post-downtime](docs/integrita-post-downtime.md) | "Il sistema e' stato spento o irraggiungibile. Come verifico che nessuno sia entrato, non ci sia un man-in-the-middle e nulla sia stato manomesso?" |
| 07 | [LAN health check](docs/lan-health-check.md) | "Come faccio un controllo di salute della LAN di casa - con e senza switch gestito, con e senza modem con difesa hardware integrata?" |
| 08 | [Backup e disaster recovery](docs/backup-e-disaster-recovery.md) | "Cosa devo salvare, come, e come ricostruisco tutto da zero se il Pi muore? Come provo che il restore funziona?" |
| 09 | [Esaurimento risorse e credenziali](docs/risorse-e-credenziali.md) | "Il disco e' pieno / il sistema va in OOM / va in throttling termico. Ho perso la password di OMV/Portainer/Pi-hole/Wazuh." |

---

## Prerequisiti di recovery (kit minimo)

Prima di considerare "produzione" il lab, verifica di avere:

- [ ] **MicroSD di recovery** aggiornata e testata (boot alternativo se l'NVMe fallisce)
- [ ] **Cavo micro-HDMI + tastiera USB** oppure adattatore **USB-serial UART** per la console
- [ ] **Backup off-device** delle configurazioni critiche (vedi runbook 08), su almeno un supporto separato dal Pi
- [ ] **Baseline registrata**: hash dei file critici, output atteso di `docker ps`, mappa ARP della LAN sana, export delle regole UFW
- [ ] **Copia offline delle credenziali** (password manager), incluse le chiavi di recovery di Wazuh e le chiavi private WireGuard
- [ ] Questo repository **clonato in locale** su un dispositivo diverso dal Pi (i runbook non ti servono a nulla se sono solo sul sistema che e' giu')

---

## Filosofia: assume breach, verifica non fidarti

Il lab include un honeypot deliberatamente esposto su Internet. Questo cambia la postura mentale: non ci si chiede "sono al sicuro?" ma "quando qualcosa andra' storto, me ne accorgero' e sapro' cosa fare?". I runbook di questa sezione sono la risposta operativa a quella domanda. Non sostituiscono le pratiche di hardening documentate in [Secure your RaspberryPi](../Secure%20your%20RaspberryPi/) e nel [SOC Analyst / Wazuh](../SOC%20Analyst/): le completano, chiudendo il ciclo *prevenire -> rilevare -> rispondere -> recuperare*.
