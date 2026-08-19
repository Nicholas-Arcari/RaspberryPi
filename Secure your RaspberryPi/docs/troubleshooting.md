>  [English](troubleshooting.en.md) |  **Italiano**

# Troubleshooting - Hardening: problemi reali e soluzioni

> Problemi tipici delle misure di hardening (SSH, Fail2ban, UFW, sysctl, unattended-upgrades, Wazuh FIM): configurazioni che si ritorcono contro, ban che non scattano o che colpiscono te, regole firewall inefficaci, sysctl che non persistono. Per il **recupero d'emergenza** quando l'hardening ti chiude fuori (console, lockout) vedi [Incident Recovery / accesso perso e boot](../../Incident%20Recovery%20%26%20Resilience/docs/accesso-perso-e-boot.md); per **provare** che le difese funzionino davvero vedi [Incident Recovery / verifica difese attive](../../Incident%20Recovery%20%26%20Resilience/docs/verifica-difese-attive.md).

---

## Problema 1: Mi sono chiuso fuori dopo l'hardening SSH

**Sintomo:** dopo aver applicato `sshd_config` (o cambiato porta/chiavi), la nuova connessione SSH viene rifiutata.

**Causa:** un errore di sintassi in `sshd_config`, un `AuthorizedKeysFile` sbagliato, o password auth disabilitata prima di aver caricato la chiave.

**Soluzione (prevenzione + fix):**

```bash
# PRIMA di riavviare sshd: valida la config e tieni aperta una SECONDA sessione SSH
sudo sshd -t            # nessun output = ok. Qualsiasi riga = errore con numero di riga
sudo systemctl restart ssh
```

Se sei gia' chiuso fuori, rientra da console (HDMI/tastiera) e correggi: la procedura completa e' in [Incident Recovery / accesso perso e boot, Parte A/B](../../Incident%20Recovery%20%26%20Resilience/docs/accesso-perso-e-boot.md).

> **Trappola OMV:** OpenMediaVault **rigenera** `sshd_config` dalle sue impostazioni. Se una modifica manuale sparisce, applicala da **Services -> SSH** nella web UI OMV. Vedi il dettaglio in [hardening-ssh](hardening-ssh.md).

---

## Problema 2: Fail2ban non banna gli IP

**Sintomo:** vedi tentativi di brute force in `auth.log`, ma Fail2ban non banna nessuno.

**Causa:** tipicamente la jail `sshd` non e' abilitata, il `logpath` punta al file sbagliato, o il backend di lettura log non intercetta gli eventi (su sistemi con journald, `backend = systemd`).

**Soluzione:**

```bash
# La jail e' attiva e sta leggendo il log giusto?
sudo fail2ban-client status sshd
sudo fail2ban-client get sshd logpath

# Test del filtro contro il log reale (quante righe matcha?)
sudo fail2ban-regex /var/log/auth.log /etc/fail2ban/filter.d/sshd.conf

# Config: assicurati in /etc/fail2ban/jail.local che sshd sia enabled e con backend corretto
#   [sshd]
#   enabled = true
#   backend = systemd        # su Debian/Bookworm con journald
sudo systemctl restart fail2ban
```

---

## Problema 3: Fail2ban ha bannato ME

**Sintomo:** dopo qualche errore di digitazione della chiave/password, non riesci piu' a connetterti dal tuo IP.

**Causa:** il tuo IP ha superato `maxretry` e Fail2ban lo ha messo in ban.

**Soluzione:**

```bash
# Da console o da un altro IP: sblocca il tuo IP
sudo fail2ban-client set sshd unbanip 192.168.0.50
```

**Prevenzione:** aggiungi il tuo IP/subnet LAN alla `ignoreip` in `jail.local` (`ignoreip = 127.0.0.1/8 192.168.0.0/24`) cosi' non potrai mai auto-bannarti dalla rete di casa.

---

## Problema 4: Una regola UFW "deny" sembra non avere effetto

**Sintomo:** hai aggiunto una regola per bloccare una porta/IP, ma il traffico passa ancora.

**Causa:** due cause frequenti. (1) **Ordine delle regole:** UFW valuta in ordine e la **prima** che matcha vince; una `allow` inserita prima di una `deny` piu' specifica la annulla. (2) **Docker scavalca UFW:** le porte pubblicate dai container non sono governate da UFW.

**Soluzione:**

```bash
# Vedi le regole NUMERATE nell'ordine di valutazione
sudo ufw status numbered
# Inserisci una regola nella posizione giusta (prima di quella che la annulla)
sudo ufw insert 1 deny from 203.0.113.10
# Rimuovi per numero se serve riordinare
sudo ufw delete <numero>
```

> Se la porta esposta e' di un container Docker, UFW non basta: vedi [Docker / troubleshooting, Problema 6](../../Docker%20%26%20Portainer/docs/troubleshooting.md). Il mapping UFW -> iptables/netfilter e' spiegato in [firewall-ufw](firewall-ufw.md).

---

## Problema 5: I sysctl di hardening non sopravvivono al reboot

**Sintomo:** dopo un riavvio, `sysctl` mostra valori tornati ai default (es. `rp_filter=0`).

**Causa:** il file in `/etc/sysctl.d/` non viene applicato (nome file, ordine di caricamento) o un altro file lo sovrascrive.

**Soluzione:**

```bash
# Verifica il valore effettivo ORA
sudo sysctl net.ipv4.tcp_syncookies kernel.randomize_va_space net.ipv4.conf.all.rp_filter

# Riapplica tutti i file sysctl.d e guarda quale file imposta cosa
sudo sysctl --system 2>&1 | grep -i "sysctl.d\|rp_filter"

# Assicurati che il tuo file (es. /etc/sysctl.d/99-hardening.conf) esista e sia caricato per ultimo
```

Dettaglio dei parametri (SYN cookies, rp_filter, ASLR) in [kernel-hardening](kernel-hardening.md).

---

## Problema 6: Unattended-upgrades non aggiorna (o rompe qualcosa)

**Sintomo:** le patch automatiche non si applicano, oppure un aggiornamento automatico ha causato un problema.

**Causa:** il servizio non e' abilitato, un pacchetto e' in `hold`, o serve un reboot per applicare aggiornamenti del kernel.

**Soluzione:**

```bash
# Simula un ciclo per vedere cosa farebbe
sudo unattended-upgrade --dry-run --debug | tail -30
# Log delle esecuzioni reali
cat /var/log/unattended-upgrades/unattended-upgrades.log | tail -30
# Un aggiornamento del kernel richiede reboot per avere effetto
[ -f /var/run/reboot-required ] && echo "REBOOT necessario"
```

Su un sistema con OMV, evita major-release upgrade automatici che potrebbero disallineare i pacchetti gestiti da OMV (vedi [NAS / troubleshooting, Problema 8](../../NAS%20(Network%20Attached%20Storage)/docs/troubleshooting.md)).

---

## Problema 7: Wazuh FIM non genera alert sulle modifiche

**Sintomo:** modifichi un file monitorato ma nessun alert compare.

**Causa:** la directory non e' in `<syscheck>`, il FIM e' in modalita' scheduled (non realtime) e il ciclo non e' ancora passato, o l'agent e' disconnesso.

**Soluzione:**

```bash
# L'agent e' connesso al manager?
sudo /var/ossec/bin/agent_control -l

# Test rapido su una dir monitorata (es. /etc) e ricerca dell'alert syscheck
sudo touch /etc/test-fim-$(date +%s).conf
sudo tail -n 50 /var/ossec/logs/alerts/alerts.json | grep -i syscheck
sudo rm /etc/test-fim-*.conf
```

Verifica in `ossec.conf` che la directory sia monitorata e, se serve realtime, con `realtime="yes"`. La procedura completa e i rule.id sono in [integrazione-wazuh](integrazione-wazuh.md) e nel test attivo [Incident Recovery / verifica difese, sez.5](../../Incident%20Recovery%20%26%20Resilience/docs/verifica-difese-attive.md).

---

## Comandi utili di verifica

```bash
# Config SSH EFFETTIVA (non quella che credi di aver scritto)
sudo sshd -T | grep -Ei "permitrootlogin|passwordauthentication|pubkeyauthentication"

# Stato delle difese in un colpo
sudo ufw status verbose
sudo fail2ban-client status
sudo sysctl net.ipv4.tcp_syncookies kernel.randomize_va_space

# Alert Wazuh attesi da questo modulo:
#   SSH falliti 5710/5712, ban Fail2ban 87101-87105, FIM 550-554, sudo 5401-5405
sudo tail -f /var/ossec/logs/alerts/alerts.json
```

---

## Collegamenti

- Recupero d'emergenza da lockout (console, UFW, Fail2ban) -> [Incident Recovery / accesso perso e boot](../../Incident%20Recovery%20%26%20Resilience/docs/accesso-perso-e-boot.md)
- Provare attivamente che le difese funzionino -> [Incident Recovery / verifica difese attive](../../Incident%20Recovery%20%26%20Resilience/docs/verifica-difese-attive.md)
- Docker scavalca UFW -> [Docker / troubleshooting](../../Docker%20%26%20Portainer/docs/troubleshooting.md)
- Deep dive UFW/netfilter -> [firewall-ufw](firewall-ufw.md); kernel -> [kernel-hardening](kernel-hardening.md); SSH -> [hardening-ssh](hardening-ssh.md)
