# Hardening del Raspberry Pi - Guida alla Messa in Sicurezza

Un Raspberry Pi esposto su rete (anche solo LAN) con servizi attivi e' un bersaglio. Questa guida copre le misure di sicurezza fondamentali che ho applicato al mio sistema, spiegando non solo il "come" ma il "perche'" di ogni configurazione.

La filosofia e' **defense in depth**: nessuna singola misura e' sufficiente, ma la combinazione di piu' livelli rende l'attacco significativamente piu' difficile.

---

## Indice della documentazione

| Documento | Contenuto |
|---|---|
| [Deep Dive: Protocollo SSH](docs/protocollo-ssh.md) | 5 fasi della connessione, KEX Diffie-Hellman su Curve25519, host keys vs user keys, fingerprint, known_hosts (TOFU), authorized_keys, challenge-response |
| [Hardening SSH](docs/hardening-ssh.md) | Configurazione sshd_config con giustificazione di ogni direttiva, setup chiave pubblica Ed25519, integrazione OMV |
| [Fail2ban](docs/fail2ban.md) | Protezione brute force: filter, jail, action, configurazione personalizzata |
| [Firewall UFW + netfilter](docs/firewall-ufw.md) | 5 hook points netfilter, 4 tabelle iptables, connection tracking (conntrack), mapping UFW su iptables, regole per il progetto |
| [Kernel Hardening + Aggiornamenti](docs/kernel-hardening.md) | Sysctl: SYN cookies, ICMP redirect, rp_filter, ASLR, symlink protection. Unattended upgrades |
| [Integrazione Wazuh FIM](docs/integrazione-wazuh.md) | Verifica File Integrity Monitoring, test alert, forzare rescan |

---

## Riepilogo: defense in depth

| Layer | Protezione | Cosa rileva/blocca |
|---|---|---|
| **SSH** | Chiave pubblica, no root, no password | Brute force, accesso non autorizzato |
| **Fail2ban** | Ban automatico IP | Bot e scanner automatici |
| **UFW** | Firewall con policy deny-by-default | Scansioni di porta, accessi non autorizzati |
| **sysctl** | Hardening kernel (rete + memoria) | SYN flood, IP spoofing, buffer overflow |
| **Unattended Upgrades** | Patch automatiche | Vulnerabilita' note (CVE) |
| **Wazuh FIM** | Integrity monitoring | Modifiche non autorizzate ai file di sistema |

Wazuh iniziera' a generare alert per:

- Tentativi SSH falliti (rule.id: 5710, 5712)
- Ban di Fail2ban (rule.id: 87101-87105)
- Modifiche a file monitorati (rule.id: 550-554)
- Escalation di privilegi (`sudo` usage - rule.id: 5401-5405)
