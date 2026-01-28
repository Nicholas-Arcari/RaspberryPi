# Raspberry Pi Honeypot: Cowrie + Wazuh SIEM

Un progetto di Cyber Security per trasformare un Raspberry Pi in una "trappola" (Honeypot) capace di attirare attaccanti, registrare le loro azioni e analizzarle in tempo reale tramite un SIEM (Wazuh)

---

## Introduzione e Teoria

- Cos'è un Honeypot?

Un Honeypot è un sistema "esca" configurato per sembrare vulnerabile e interessante per un attaccante. Non contiene dati reali, ma serve a studiare le tecniche di attacco. In questo progetto uso Cowrie, un honeypot che emula un server SSH/Telnet. Quando un hacker tenta di fare brute-force ed entra, crede di essere in un vero sistema Linux, ma in realtà è in un ambiente controllato (sandbox) dove ogni comando viene registrato

- Cos'è un SIEM (Wazuh)?

Wazuh è una piattaforma di sicurezza che raccoglie log da varie fonti, cerca minacce note e genera allarmi. In questo progetto, Wazuh legge i log generati da Cowrie, li decodifica e ci avvisa se qualcuno sta attaccando

---

## Architettura del Progetto

Il sistema gira interamente su Raspberry Pi (o in configurazione ibrida) e utilizza Docker per isolare l'Honeypot dal sistema operativo reale
- L'Attacco: L'hacker si collega alla porta 2222 del Raspberry (esposta da Cowrie)
- La Registrazione: Cowrie registra tutto (IP, password tentate, comandi eseguiti) in un file JSON (`cowrie.json`)
- L'Ingestione: L'agente Wazuh monitora questo file in tempo reale
- L'Analisi: Wazuh Manager confronta i log con le regole di sicurezza
- L'Allarme: Se viene rilevata un'intrusione, appare una notifica sulla Dashboard

---

## Prerequisiti

- Raspberry Pi (3B+ o 4/5 consigliato) con OS a 64-bit
- Docker & Docker Compose installati
- Wazuh Manager e Agent installati (All-in-one sul Pi o Manager su server esterno)

---

## Installazione Passo-Passo

### Step 1: Setup di Docker e Cowrie

Creiamo l'ambiente per l'honeypot

1. Creazione delle directory:

```Bash
mkdir -p ~/cowrie/var/log/cowrie
mkdir -p ~/cowrie/etc
cd ~/cowrie
```

Cosa fa: Crea la struttura delle cartelle ospite dove Cowrie salverà i dati persistenti

2. Creazione del file docker-compose.yml:

```YAML
version: "3"
services:
  cowrie:
    image: cowrie/cowrie:latest
    container_name: cowrie
    restart: always
    ports:
      - "2222:2222" # Porta SSH Honeypot
      - "2223:2223" # Porta Telnet Honeypot
    volumes:
      # IMPORTANTE: Mappare solo i log, non /etc se non si ha una config pronta!
      - ./var/log/cowrie:/cowrie/cowrie-git/var/log/cowrie
```

Nota: Espongo la porta 2222 per non andare in conflitto con il vero SSH del Raspberry (porta 22)

3. Avvio del container:

```Bash
docker compose up -d
```

### Step 2: Configurazione Wazuh

Dobbiamo dire a Wazuh di leggere il file JSON prodotto da Cowrie

1. Modifica di ossec.conf: Aprire il file `/var/ossec/etc/ossec.conf` e aggiungere questo blocco alla fine (prima di `</ossec_config>`):

```XML
<localfile>
  <log_format>json</log_format>
  <location>/home/<tuo_utente>/cowrie/var/log/cowrie/cowrie.json</location>
</localfile>
```

Cosa fa: Istruisce l'agente Wazuh a trattare quel file specifico come una fonte di log in formato JSON

2. Fix dei Permessi (Fondamentale): Poiché Docker crea i file come utente interno, Wazuh potrebbe non riuscire a leggerli

```Bash
sudo chmod -R 755 /home/<tuo_utente>/cowrie/var/log/cowrie/
```

---

## Integrazione e Regole Custom

Per vedere gli allarmi sulla dashboard, ho dovuto creare regole personalizzate, poiché quelle di default non coprivano tutti gli eventi di Cowrie

File: `/var/ossec/etc/rules/local_rules.xml`

```XML
<group name="local,syslog,sshd,">

  <rule id="100010" level="3">
    <decoded_as>json</decoded_as>
    <field name="eventid" type="pcre2">^cowrie\.</field>
    <description>Cowrie: Attività generica Honeypot rilevata</description>
  </rule>

  <rule id="100011" level="5">
    <if_sid>100010</if_sid>
    <field name="eventid">cowrie.login.failed</field>
    <description>Cowrie: Tentativo di accesso fallito (Brute Force)</description>
    <group>authentication_failed,pci_dss_10.2.4,pci_dss_10.2.5,</group>
  </rule>

  <rule id="100012" level="10">
    <if_sid>100010</if_sid>
    <field name="eventid">cowrie.login.success</field>
    <description>Cowrie: INTRUSIONE RIUSCITA! Un attaccante è entrato nell'Honeypot</description>
    <mitre>
      <id>T1078</id>
    </mitre>
    <group>authentication_success,pci_dss_10.2.5,</group>
  </rule>

  <rule id="100013" level="7">
    <if_sid>100010</if_sid>
    <field name="eventid">cowrie.command.input</field>
    <description>Cowrie: L'attaccante ha digitato un comando: $(input)</description>
  </rule>

</group>
```

---

## Troubleshooting e Esperienza Personale (La parte divertente)

Durante la configurazione ho incontrato diversi ostacoli. Ecco come li ho risolti, sperando possa aiutare altri

Errore 1: Il Container Cowrie si riavviava all'infinito (Loop)

- Sintomo: `docker ps` mostrava lo stato "Restarting" e i log davano errore `twistd: Unknown command: cowrie`
- Causa: Nel `docker-compose.yml` avevo mappato un volume `./etc` vuoto sopra la cartella di configurazione interna del container, cancellando di fatto i file di avvio
- Soluzione: Ho commentato/rimosso il volume `- ./etc:/cowrie/cowrie-git/etc` lasciando usare al container la sua configurazione di default

Errore 2: Wazuh Error "Too many fields for JSON decoder"

- Sintomo: Wazuh non mostrava nulla e nel log `ossec.log` appariva ripetutamente questo errore
- Causa: I log JSON di Cowrie sono molto ricchi di dettagli e superavano il limite predefinito di campi analizzabili da Wazuh
- Soluzione: Ho modificato il file `/var/ossec/etc/local_internal_options.conf` aumentando il buffer del decoder:

```Properties
analysisd.decoder_order_size=1024
```
Errore 3: "Connection Refused" durante i test

- Causa: Provavo a collegarmi a `ssh -p 2222 root@127.0.0.1` da una macchina diversa (Kali Linux)
- Soluzione: Bisogna usare l'IP LAN del Raspberry (es. `192.168.x.x`), non localhost, se si testa da un altro computer

Errore 4: Log presenti ma Dashboard vuota

- Sintomo: Vedevo i log arrivare usando la modalità debug (`logall_json`), ma nessun allarme grafico
- Causa: Mancavano le regole XML per mappare l'evento JSON a un livello di allerta
- Soluzione: Ho creato le regole custom (vedi sezione sopra) e usato `wazuh-logtest` per validarle prima di applicarle

---

## Test Finale

Per verificare che tutto funzioni:

Dal terminale di un altro PC (es. Kali Linux):

```Bash
ssh -p 2222 root@<IP-RASPBERRY>
```

Inserire password a caso (genera alert Brute Force)

Inserire una password semplice come root (genera alert Intrusione Riuscita)

Digitare comandi come `ls`, `whoami`, `cat /etc/shadow`

Andare sulla Dashboard di Wazuh -> Threat Hunting e filtrare per `rule.id: 100013` per vedere i comandi catturati