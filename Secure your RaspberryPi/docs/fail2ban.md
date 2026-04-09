# Fail2ban - Protezione Brute Force

**Fail2ban** monitora i log di sistema (es. `/var/log/auth.log`) alla ricerca di pattern di attacco (tentativi di login falliti) e banna automaticamente gli IP offensivi tramite regole firewall.

---

## Come funziona internamente

1. **Filter**: una regex che identifica un tentativo fallito nei log (es. `Failed password for .* from <HOST>`)
2. **Jail**: la policy - quanti tentativi (`maxretry`), in quanto tempo (`findtime`), per quanto tempo bannare (`bantime`)
3. **Action**: cosa fare quando il threshold viene superato - di default, aggiunge una regola `iptables -A INPUT -s <IP> -j REJECT`

---

## Installazione e abilitazione

```bash
sudo apt install fail2ban -y
sudo systemctl enable --now fail2ban
```

---

## Verifica dello stato della jail SSH

```bash
sudo fail2ban-client status sshd
```

Output atteso:

```
Status for the jail: sshd
|- Filter
|  |- Currently failed:	2
|  |- Total failed:	15
|  `- File list:	/var/log/auth.log
`- Actions
   |- Currently banned:	1
   |- Total banned:	3
   `- Banned IP list:	203.0.113.45
```

---

## Configurazione personalizzata (opzionale)

Per modificare i parametri della jail senza toccare il file di default (che viene sovrascritto dagli aggiornamenti):

```bash
sudo nano /etc/fail2ban/jail.local
```

```ini
[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 5       # Ban dopo 5 tentativi falliti
findtime = 600     # Finestra di 10 minuti
bantime = 3600     # Ban per 1 ora
```

> **Integrazione con Wazuh:** Fail2ban e Wazuh non sono in conflitto - si complementano. Fail2ban agisce (banna l'IP), Wazuh osserva e alerta (ti notifica dell'attacco). Wazuh legge i log di Fail2ban e genera alert quando un IP viene bannato, dandoti visibilita' centralizzata.
