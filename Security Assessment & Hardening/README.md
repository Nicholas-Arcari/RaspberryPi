# Security Assessment & Hardening

Questa è stata la fase più critica e istruttiva dell'intero progetto. Una volta attivo l'Honeypot e il siem, ho voluto testarne la sicurezza simulando di essere un attaccante esterno (Red Teaming)

L'obiettivo: Capire se il mio Raspberry Pi fosse sicuro o se, paradossalmente, avessi appena aperto una porta verso la mia rete domestica agli hacker

---

### 1. La scoperta delle Porte Aperte (Lo "Shock")

Ho lanciato una scansione completa con Nmap da un altro computer (Kali Linux) verso il Raspberry Pi

```Bash
nmap -sS -p- -T4 -v <INDIRIZZO_IP_RASPBERRY>
```

Il problema: Il risultato è stato allarmante

Non era aperta solo la porta 2222 (Honeypot), ma un "albero di Natale" di servizi sensibili esposti a chiunque:

- Porta 22 (SSH Reale): APERTA. Un attaccante avrebbe potuto provare a bucare il vero sistema operativo invece della trappola
- Porta 443 (Wazuh Dashboard): APERTA. La pagina di login del mio SIEM era visibile a tutti
- Porte 55000/9200 (API/Database): APERTE. Servizi interni che non dovrebbero mai essere esposti

La causa:

Avevo inizialmente inserito il Raspberry in DMZ sul router per comodità. La DMZ esponeva tutto brutalmente su internet, bypassando ogni protezione

---

### 1.1 Test Funzionale: Attacco Brute Force (Hydra)

Dopo aver individuato la porta 2222 aperta, ho voluto verificare se l'Honeypot fosse effettivamente "appiccicoso", ovvero se accettasse connessioni. Ho lanciato un attacco a forza bruta usando Hydra e la famosa wordlist `rockyou.txt`

```Bash
hydra -l root -P /usr/share/wordlists/rockyou.txt -t 4 ssh://<INDIRIZZO_IP_RASPBERRY>:2222
```

Il Risultato: L'attacco ha avuto successo immediato, trovando diverse password valide in pochi secondi:

```Bash
[2222][ssh] host: <INDIRIZZO_IP_RASPBERRY>   login: root   password: 12345
[2222][ssh] host: <INDIRIZZO_IP_RASPBERRY>   login: root   password: 123456789
[2222][ssh] host: <INDIRIZZO_IP_RASPBERRY>   login: root   password: password
1 of 1 target successfully completed, 3 valid passwords found
```

### Cosa significano quel comando e quell'output?

Stai usando Hydra, uno dei tool più famosi per eseguire attacchi di "Brute Force" (forza bruta) contro i moduli di login

Il Comando: `hydra -l root -P /usr/share/wordlists/rockyou.txt -t 4 ssh://<INDIRIZZO_IP_RASPBERRY>:2222`

- `hydra`: Il nome del programma
- `-l root`: Dice a Hydra di provare a loggarsi sempre con l'utente "root"
- `-P ...rockyou.txt`: Dice a Hydra di usare il file `rockyou.txt` come elenco di password. Questo file è leggendario nell'hacking: contiene milioni di password reali trapelate in data breach passati
- `-t 4`: Usa 4 tentativi paralleli (per essere più veloce)
- `ssh://<INDIRIZZO_IP_RASPBERRY>:2222`: L'obiettivo. Nota che stai attaccando la porta 2222, ovvero quella del tuo Honeypot (Cowrie), non quella reale del Raspberry (22)

L'Output:

```Bash
[DATA] attacking ssh://...: L'attacco è iniziato.
[2222][ssh] host: ... login: root password: 12345: VITTORIA! Hydra ha trovato che la password 12345 funziona.
[2222][ssh] ... password: 123456789: Anche questa funziona.
[2222][ssh] ... password: password: Anche questa funziona.
```

Analisi: Questo non è un fallimento di sicurezza, ma la conferma che Cowrie funziona. L'Honeypot è configurato intenzionalmente per accettare le password più comuni e deboli. Questo serve a illudere gli attaccanti (o i bot automatici) di aver ottenuto l'accesso root, invogliandoli a entrare ed eseguire comandi che verranno poi registrati dal SIEM

---

### 2. Il Test di Isolamento (Pivot Risk)

Ho provato a fare un semplice `ping` dal Raspberry verso il mio PC personale (Windows)

```Bash
ping 192.168.xxx.xxx  # sostituire con indirizzo ip corretto
```

Il problema: Il ping funzionava

Perché è grave: Se un hacker fosse riuscito a "evadere" dal container Cowrie (Container Escape), avrebbe avuto libero accesso alla mia rete locale (LAN) per attaccare il mio PC principale o il NAS

L'Honeypot non era isolato

---

### 3. La Soluzione: "Blindare" la rete con UFW

Ho deciso di abbandonare la DMZ e configurare un firewall interno (UFW) per creare una "gabbia" di rete

Qui ho incontrato diversi ostacoli logici

### L'errore dell'ordine delle regole

Nel tentativo di isolare il Raspberry, ho inizialmente bloccato tutto il traffico verso la rete locale (`192.168.0.0/24`)

Risultato: Ho tagliato fuori il Raspberry da Internet! Non poteva più raggiungere il Gateway (Router) per scaricare aggiornamenti o inviare dati

La correzione: Ho imparato che l'ordine delle regole è fondamentale. Ho dovuto permettere prima il Gateway e poi bloccare il resto della sottorete

La configurazione finale applicata:

```Bash
# 1. Blocco tutto in ingresso di default
sudo ufw default deny incoming

# 2. Ordine CRITICO per l'uscita (Prima il Gateway, poi il blocco LAN)
sudo ufw allow out from any to 192.168.0.1
sudo ufw deny out from any to 192.168.0.0/24

# 3. Permessi selettivi in ingresso (Solo dalla mia LAN)
sudo ufw allow from 192.168.0.0/24 to any port 22   # SSH Admin
sudo ufw allow from 192.168.0.0/24 to any port 443  # Dashboard
```

---

### 4. Il Mistero dell'Agente "Disconnected"

Durante i test, ho notato sulla Dashboard che l'agente Wazuh installato sulla mia macchina Kali risultava "Disconnected", anche se la macchina era accesa. La causa: Nella foga di chiudere tutte le porte con UFW (`default deny incoming`), avevo bloccato anche le porte che gli agenti usano per inviare i log al Manager. La soluzione: Ho dovuto aprire manualmente le porte di comunicazione Wazuh, ma limitandole strettamente alla rete locale:

```Bash
sudo ufw allow from 192.168.0.0/24 to any port 1514 proto tcp # Canale Eventi
sudo ufw allow from 192.168.0.0/24 to any port 1515 proto tcp # Canale Registrazione
```

---

### 5. L'Ostacolo Finale: Il Doppio NAT e la Soluzione Ngrok

Quando ho provato ad esporre l'Honeypot su internet usando il Port Forwarding del router, non funzionava nulla

La scoperta: Analizzando l'indirizzo WAN del mio router, ho scoperto che era un IP locale (`192.168.x.x`) e non pubblico. Il mio provider internet (connessione FWA) mi metteva dietro un ulteriore NAT (CGNAT), rendendo impossibile l'apertura porte classica

La soluzione (Tunneling):
Ho usato Ngrok per creare un tunnel sicuro verso internet. Tuttavia, ho dovuto affrontare due sfide tecniche importanti:

- Sfida 1: Persistenza (Il Detach): ngrok normalmente muore se si chiude il terminale. Per tenerlo attivo 24/7 in background, ho usato `screen`:

```Bash
# 1. Installazione
sudo apt install screen -y
    
# 2. Avvio sessione persistente
screen
    
# 3. Avvio tunnel sulla porta dell'Honeypot
ngrok tcp 2222
```

Il trucco: Una volta avviato, per uscire senza spegnerlo ho usato la combinazione `CTRL+A` seguita da `D` (Detach). In questo modo il processo continua a girare "dietro le quinte". Per controllarlo di nuovo, basta usare `screen -r`

- Sfida 2: I Limiti del Free Plan: usando la versione gratuita di Ngrok, ho notato che l'indirizzo pubblico (es. `0.tcp.eu.ngrok.io`) e la porta cambiano ad ogni riavvio del tunnel o del Raspberry

Consiglio: Se si riavvia il dispositivo, bisogna ricordarsi di rientrare (`screen -r`), riavviare ngrok e segnarsi il nuovo indirizzo

Il Test Finale (Successo):

Per confermare che tutto funzionasse, ho scollegato il mio PC di test (Kali) dal Wi-Fi e l'ho collegato all'hotspot del cellulare (simulando una rete esterna reale)

Lanciando il comando:

```Bash
ssh root@<indirizzo_ngrok> -p <porta_ngrok>
```

...l'accesso è stato garantito. Immediatamente dopo, sulla Dashboard di Wazuh è scattato l'allarme rosso "Intrusione Rilevata". Il sistema è ora online e monitorato