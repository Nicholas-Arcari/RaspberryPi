>  [Italiano](dns-pihole-recovery.md) |  **English**

# Runbook 02 - DNS / Pi-hole recovery

> **When to use this runbook:** names no longer resolve across the whole house, Pi-hole does not respond, or the DDNS domain has expired and the VPN is no longer reachable from outside. This runbook covers two different but often-confused "expiries": the **internal DNS service** (Pi-hole) and the **public DDNS name** (remote access).

First, the scary part: **why a DNS outage is a serious incident and not a nuisance.**

---

## Part A - Why DNS is a single point of failure (and a security control)

In the lab, Pi-hole (`192.168.0.250`) is the **sole DNS** handed out by DHCP to the entire LAN. This has two consequences that must be understood before you find yourself in the emergency.

### A.1 Impact on internal services (very low RTO)

DNS has the lowest RTO of the whole lab: if it goes down, **within seconds** every device that asks for a name fails.

```
Pi-hole down
   |
   +-- Smartphone/PC/Smart TV: "site unreachable" even though Internet is up
   +-- WireGuard resolving an endpoint by name: tunnel won't establish
   +-- Containers calling services by hostname: cascading errors
   +-- OMV/Portainer by IP still work (they don't use names) -> diagnostic clue
```

Valuable diagnostic note: if you can reach the Pi **by IP** (`https://192.168.0.102`) but not **by name**, the network is healthy and the culprit is DNS. It is exactly the `ping 1.1.1.1` OK / `ping google.com` KO test from [Runbook 00](triage-diagnostica.en.md).

### A.2 Impact on security (the less obvious point)

Pi-hole is not just an ad-blocker: it is a **security control**. It blocks malware, phishing and telemetry domains at the DNS level, and its query log is a source of visibility over the network traffic. When it dies, you lose more than ads:

- **You lose the anti-malware/phishing DNS filter.** Devices that fall back to another resolver (ISP, router, `8.8.8.8` hardcoded in the Smart TV) go back to resolving domains the sinkhole was blocking.
- **You lose the telemetry.** No query log = one fewer detection channel to notice a compromised device phoning home (C2).
- **You free up a heavy IP.** The address `192.168.0.250` was "everyone's DNS". If Pi-hole is down and a hostile device on the LAN takes over that IP, it becomes the resolver for the whole house: **DNS hijacking / full man-in-the-middle**. A dead Pi-hole is not just an absence, it is an empty chair someone can occupy. See [Runbook 06](integrita-post-downtime.en.md).

This is why DNS must be treated as critical infrastructure, with a recovery plan and not just an "I'll restart it later".

---

## Part B - The Pi-hole service does not respond

### B.1 Diagnosis

```bash
# Does the resolver respond? (from the host or a client)
dig @192.168.0.250 google.com +short
# Timeout/SERVFAIL -> Pi-hole down or FTL dead

# Is the container alive? (runs in Docker on a MacVLAN network)
docker ps -a --filter name=pihole --format "{{.Names}}\t{{.Status}}"
# "Up" expected. "Exited"/"Restarting" -> B.2

# Is the FTL engine (Pi-hole's DNS/DHCP) active inside the container?
docker exec pihole pihole status
# Expected: "FTL is listening on port 53" + "Pi-hole blocking is enabled"

# Is port 53 really listening on the MacVLAN IP?
docker exec pihole ss -tulnp | grep :53
```

### B.2 Recovery, from least to most invasive

```bash
# 1. Soft restart of just the DNS engine (does not touch the container)
docker exec pihole pihole restartdns

# 2. Restart the container
docker restart pihole

# 3. If it won't restart: read why
docker logs pihole --tail 50
#   "address already in use :53"  -> something else holds 53 (systemd-resolved?)
#   "gravity.db ... malformed"    -> corrupted blocklist database (B.3)
#   MacVLAN / no route errors     -> Docker network problem (B.4)

# 4. Clean recreation from the compose (data persists in the mounted volumes)
cd /path/to/compose/pihole && docker compose up -d --force-recreate
```

### B.3 Corrupted gravity database

```bash
# gravity.db is the DB of blocked domains. If corrupted, FTL won't block or won't start.
docker exec pihole sqlite3 /etc/pihole/gravity.db "PRAGMA integrity_check;"
# Expected: "ok". Anything else -> regenerate:
docker exec pihole pihole -g       # re-download and rebuild the blocklists
```

### B.4 The MacVLAN case: the host cannot talk to Pi-hole

Pi-hole uses a **MacVLAN** network with a dedicated IP (`192.168.0.250`). A known side effect of MacVLAN: **the Docker host cannot reach its own container** on the same MacVLAN (isolation by design). The LAN clients reach it, but the host does not. If your `dig` test from the host fails but works from the clients, it is not a fault: it is MacVLAN behavior. Always test **from a second device too** before declaring Pi-hole dead.

---

## Part C - Emergency: restore resolution NOW

While you repair Pi-hole, the house is without DNS. Restore resolution quickly and safely:

**Option 1 - Temporary bypass on the router (fast, whole LAN).**
On the router (`192.168.0.1`), set the DHCP DNS to a trusted public resolver with DNSSEC (`1.1.1.1` / `9.9.9.9`). Restart DHCP or wait for the lease renewal. You lose the sinkhole but you are operational again. **Remember to put `192.168.0.250` back when Pi-hole returns**, otherwise you stay without DNS protection without noticing.

**Option 2 - Fix on the single device (surgical).**
On the PC you need to work from, manually set `1.1.1.1` as DNS until you are done.

> **Design trade-off.** A permanent secondary DNS (e.g. the router as fallback) removes the single point of failure, but **defeats the sinkhole**: when Pi-hole slows down, clients use the secondary and skip the filter. The two correct paths are: (a) accept the RTO and restore quickly with a single DNS; or (b) run **two Pi-holes** (a second one on another device) as primary+secondary DNS, so you have redundancy without losing the filter. Never use a non-filtering resolver as a "just in case" secondary: it is the back door that defeats the sinkhole.

---

## Part D - The public DDNS name has expired

This is the other "expired DNS", different from Pi-hole. Remote access (WireGuard) points to a dynamic name like `miodominio.ddns.net` (No-IP). Free No-IP names **expire if not periodically confirmed**, and the public IP is dynamic behind CGNAT: if the record is not updated or the name has expired, **the VPN is no longer reachable from outside**.

### D.1 Diagnosis

```bash
# Does the DDNS name resolve, and to which IP?
dig +short miodominio.ddns.net
# Empty -> expired/deleted name.  IP different from the real public one -> record not updated

# What is the real public IP seen from the Internet?
curl -s https://api.ipify.org ; echo
# Compare with the dig above: they must match
```

### D.2 Causes and fixes

| Symptom | Cause | Fix |
|---|---|---|
| Empty `dig` | DDNS name expired (No-IP confirmation missed) | Log back into the No-IP panel, reconfirm/renew the name |
| Record IP != real IP | DDNS client stopped (on the router or the Pi) | Restart the DDNS updater; force a manual update |
| Resolves correctly but the VPN won't connect | Not DNS: it is port-forward or **CGNAT** | See [Runbook 04](vpn-e-container-recovery.en.md) |

> **The CGNAT trap.** The FWA uplink (Comeser) is behind CGNAT: you do not have a dedicated public IP, so port forwarding may not work **even with perfect DDNS**. In that case DDNS is not enough and you need a plan B (an outbound tunnel like Ngrok/Cloudflare Tunnel, or asking the provider for a public IP). The detail is in [Runbook 04](vpn-e-container-recovery.en.md) and in [VPN / rete-dmz](../../VPN%20(Virtual%20Private%20Network)/docs/rete-dmz.en.md).

### D.3 The wifi/modem security angle

DDNS and DNS directly touch the security of the home perimeter:

- **An expired DDNS name can be re-registered by others.** If you let `miodominio.ddns.net` expire and someone takes it back, your clients that trust that name point to a host you do not control. Do not let names you use for access expire.
- **The modem/router DNS is a target.** The router hands out which DNS to use. If an attacker changes the DNS in the router (default credentials, exposed UI), they redirect **the whole** house: this is DNS hijacking at the gateway level. Verify: router DNS = `192.168.0.250` (or the chosen fallback), router UI not exposed to the Internet, router password changed.
- **DNSSEC and DNS rebinding.** Enable DNSSEC on Pi-hole to validate the responses (anti-spoofing). Keep the router/Pi-hole **DNS rebinding** protection active to prevent external names from resolving to internal private IPs.

---

## Recovery verification

```bash
# From a client (not from the host, because of MacVLAN):
dig @192.168.0.250 google.com +short          # resolves -> DNS up
dig @192.168.0.250 ads.doubleclick.net +short # 0.0.0.0 -> sinkhole active again
dig +short miodominio.ddns.net                # = real public IP -> DDNS ok
```

Then re-run the DNS section of the [post-installation checklist](../../docs/checklist-post-installazione.en.md).

---

## Prevention

- Decide the DNS strategy: **accepted RTO with a single Pi-hole** or **two redundant Pi-holes**. Never a non-filtering secondary.
- Set a reminder for the **periodic reconfirmation of the No-IP name** (or move to a DDNS provider without expiry).
- Have Wazuh monitor DNS: an alert if the Pi-hole port 53 stops responding warns you before your sister does.
- Change the router credentials and do not expose its UI: the gateway is the real master of the home DNS.

---

## Links

- The VPN won't connect even with DNS working -> [Runbook 04: VPN and containers](vpn-e-container-recovery.en.md)
- You suspect DNS hijacking / MITM -> [Runbook 06: post-downtime integrity](integrita-post-downtime.en.md)
- How DNS and Pi-hole FTL work -> [ADS Blocker / protocollo-dns](../../ADS%20Blocker/docs/protocollo-dns.en.md), [ftl-engine](../../ADS%20Blocker/docs/ftl-engine.en.md)
- Pi-hole-specific troubleshooting -> [ADS Blocker / troubleshooting](../../ADS%20Blocker/docs/troubleshooting.en.md)
