>  [Italiano](README.md) |  **English**

# Incident Recovery & Resilience

> What to do when something breaks, when you get locked out of the system, when you suspect a compromise, or when you simply need to prove - to yourself - that the defenses still work. This section collects the **operational runbooks**: step-by-step guides to follow under stress, when there is no time to study but you need a clear procedure.

The rest of the repository documents how to **build** the lab. This section documents how to **keep it alive**: diagnosis, recovery, verification and operational continuity. It is the difference between a showcase project and a system that someone actually operates over time.

---

## A note on terminology

"Incident recovery" is the intuitive term, but it actually covers four distinct disciplines that this section addresses in an integrated way:

| Discipline | Question it answers | Time horizon |
|---|---|---|
| **Troubleshooting** | "Why isn't this service working?" | Minutes |
| **Incident Response (IR)** | "Was I compromised? How do I contain it and understand what happened?" | Hours |
| **Disaster Recovery (DR)** | "The system is destroyed: how do I rebuild it and recover the data?" | Hours / days |
| **Business Continuity (BC)** | "Which services must stay up, and how long can I hold out without them?" | Design-level |

In professional language, BC is measured with two parameters that we will use as a compass even in a homelab:

- **RTO (Recovery Time Objective):** how long I can go without a service before it becomes a serious problem. DNS (Pi-hole) has a very low RTO: if it goes down, within minutes the whole LAN loses name resolution. The honeypot has a high RTO: if it is down for a day, nothing critical happens.
- **RPO (Recovery Point Objective):** how much data I can afford to lose. Wazuh custom rules and WireGuard keys have an RPO close to zero (recreating them is painful): they go into the backup. The Pi-hole DNS cache has a very high RPO (it regenerates itself).

Thinking in terms of RTO/RPO turns the vague question "what do I do if it breaks?" into a precise operational priority.

---

## The three golden rules (read them before you need them)

A successful recovery is decided **before** the incident, not during it. Three non-negotiable principles:

1. **Out-of-band (OOB) access always available.** You cannot repair what you cannot reach. If the network goes down or a firewall rule locks you out, the only way in is physical access: HDMI monitor + USB keyboard, or the UART serial console. Always keep the cable and the recovery MicroSD within reach. See [accesso-perso-e-boot.en.md](docs/accesso-perso-e-boot.en.md).
2. **The baseline is captured from a healthy system, not a sick one.** You cannot detect a change if you do not know what the "healthy" system looked like. The hashes of critical files, the list of expected services, the ARP map of the LAN, the firewall configuration: record them **now**, while the system is intact. Wazuh FIM does most of this work, but only if the baseline was taken beforehand. See [integrita-post-downtime.en.md](docs/integrita-post-downtime.en.md).
3. **An untested backup is not a backup.** An archive you have never tried to restore is just a hope. The restore procedure must be run at least once, cold, to discover what is missing **before** you actually need it. See [backup-e-disaster-recovery.en.md](docs/backup-e-disaster-recovery.en.md).

---

## How to use this section: triage

When something is wrong, you do not start from the application service: you diagnose the stack **from the bottom up**, because a fault low down manifests as a symptom higher up. Pi-hole "not blocking ads" can be a Pi-hole problem, but also a network, Docker, or power problem.

```
   LAYER                       "If it's broken here, above you see..."   RUNBOOK
   --------------------------------------------------------------------------------
   [7] Application      Dashboard, alerts, ad blocking     -> wazuh / dns / vpn
        ^
   [6] Container        docker ps, container logs          -> vpn-e-container
        ^
   [5] Host services    systemctl, listening ports         -> triage-diagnostica
        ^
   [4] DNS / names      dig, resolution                    -> dns-pihole-recovery
        ^
   [3] IP / routing     ping gateway, ip addr, ip route    -> lan-health-check
        ^
   [2] Link / L2        cable, link, switch, VLAN tag       -> lan-health-check
        ^
   [1] OS / kernel      boot, kernel panic, fsck           -> accesso-perso-e-boot
        ^
   [0] Hardware/power   LED, power supply, NVMe, temp      -> accesso-perso-e-boot
```

Rule of thumb: **check the lowest plausible layer first.** If the ping to the gateway (layer 3) fails, it is pointless to investigate Pi-hole (layer 7). The [triage-diagnostica.en.md](docs/triage-diagnostica.en.md) runbook is the complete decision tree: always start there if you do not know where to begin.

---

## Runbook index

Each runbook answers one or more concrete "what happens if..." questions.

| # | Runbook | Answers |
|---|---|---|
| 00 | [Triage and diagnostics](docs/triage-diagnostica.en.md) | "Something is wrong and I don't know where to start. How do I isolate the cause systematically?" |
| 01 | [Lost access and boot failure](docs/accesso-perso-e-boot.en.md) | "SSH no longer works. I locked myself out with UFW. Kernel panic and I can no longer log in. Boot from NVMe fails." |
| 02 | [DNS / Pi-hole recovery](docs/dns-pihole-recovery.en.md) | "DNS went down or the DDNS domain expired: what happens to the internal services, the Wi-Fi and security? How do I restore it?" |
| 03 | [Wazuh dashboard inaccessible](docs/wazuh-dashboard-recovery.en.md) | "I can no longer log into the Wazuh dashboard. How do I understand the cause (indexer? certificates? disk? password?) and fix it?" |
| 04 | [VPN and container recovery](docs/vpn-e-container-recovery.en.md) | "The WireGuard VPN no longer lets me in from outside. A container died or won't restart. Docker won't start." |
| 05 | [Verifying active defenses](docs/verifica-difese-attive.en.md) | "How can I be sure that firewall, Fail2ban, FIM, honeypot and segmentation still actually work, not just that they are 'up'?" |
| 06 | [Post-downtime integrity](docs/integrita-post-downtime.en.md) | "The system was off or unreachable. How do I verify that nobody got in, there is no man-in-the-middle, and nothing was tampered with?" |
| 07 | [LAN health check](docs/lan-health-check.en.md) | "How do I run a health check of the home LAN - with and without a managed switch, with and without a modem with built-in hardware defense?" |
| 08 | [Backup and disaster recovery](docs/backup-e-disaster-recovery.en.md) | "What must I save, how, and how do I rebuild everything from scratch if the Pi dies? How do I prove the restore works?" |
| 09 | [Resource exhaustion and credentials](docs/risorse-e-credenziali.en.md) | "The disk is full / the system goes OOM / it goes into thermal throttling. I lost the OMV/Portainer/Pi-hole/Wazuh password." |

---

## Recovery prerequisites (minimum kit)

Before considering the lab "production", verify that you have:

- [ ] **Recovery MicroSD**, updated and tested (alternative boot if the NVMe fails)
- [ ] **Micro-HDMI cable + USB keyboard** or a **USB-serial UART** adapter for the console
- [ ] **Off-device backup** of the critical configurations (see runbook 08), on at least one medium separate from the Pi
- [ ] **Recorded baseline**: hashes of critical files, expected output of `docker ps`, ARP map of the healthy LAN, export of the UFW rules
- [ ] **Offline copy of the credentials** (password manager), including the Wazuh recovery keys and the WireGuard private keys
- [ ] This repository **cloned locally** on a device other than the Pi (the runbooks are useless if they only exist on the system that is down)

---

## Philosophy: assume breach, verify don't trust

The lab includes a honeypot deliberately exposed on the Internet. This changes the mindset: you do not ask "am I safe?" but "when something goes wrong, will I notice, and will I know what to do?". The runbooks in this section are the operational answer to that question. They do not replace the hardening practices documented in [Secure your RaspberryPi](../Secure%20your%20RaspberryPi/) and in [SOC Analyst / Wazuh](../SOC%20Analyst/): they complete them, closing the *prevent -> detect -> respond -> recover* cycle.
