>  [English](teoria-honeypot.en.md) |  **Italiano**

# Teoria: Cos'è un Honeypot

Un honeypot è un sistema deliberatamente esposto e apparentemente vulnerabile, progettato per attirare attaccanti. Non contiene dati reali e non fa parte dell'infrastruttura produttiva - il suo unico scopo è **osservare e registrare le tecniche di attacco**.

## Classificazione degli Honeypot

| Tipo | Interazione | Esempio | Rischio |
|---|---|---|---|
| **Low interaction** | Emula solo banner e login | Cowrie, Kippo, HoneyD | Basso - l'attaccante interagisce con un simulatore |
| **Medium interaction** | Emula servizi parziali | Cowrie (con comandi), Dionaea | Medio - comandi limitati ma credibili |
| **High interaction** | Sistema operativo reale, completo | VM dedicata, T-Pot | Alto - se l'attaccante evade, ha accesso alla rete |

## Cowrie: Medium-Interaction SSH/Telnet Honeypot

**Cowrie** emula un server SSH e Telnet con un filesystem finto (basato su Debian). Quando un attaccante si collega:

1. Può provare credenziali (brute force) - Cowrie accetta password comuni di proposito
2. Una volta "dentro", crede di essere su un vero server Linux
3. Può eseguire comandi (`ls`, `cat /etc/passwd`, `wget malware.exe`) - Cowrie simula le risposte
4. Se tenta di scaricare file (payload malevoli), Cowrie li cattura per analisi

Ogni azione viene registrata in formato JSON nel file `cowrie.json`, con timestamp, IP sorgente, username, password, comandi eseguiti.

## MITRE ATT&CK Mapping

I comportamenti catturati da Cowrie mappano direttamente alle tecniche del framework MITRE ATT&CK:

| Evento Cowrie | Tecnica MITRE ATT&CK | ID |
|---|---|---|
| Tentativo di login (brute force) | Brute Force: Password Guessing | T1110.001 |
| Login riuscito con credenziali deboli | Valid Accounts: Default Accounts | T1078.001 |
| Esecuzione comandi post-login | Command and Scripting Interpreter: Unix Shell | T1059.004 |
| Download di file malevoli | Ingress Tool Transfer | T1105 |
| Ricognizione (`whoami`, `uname -a`) | System Information Discovery | T1082 |
