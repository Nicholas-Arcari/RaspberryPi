>  [Italiano](README.md) |  **English**

# Security Assessment & Hardening - Red Teaming Your Own Lab

This was the most critical and instructive phase of the entire project. Once the Honeypot and the SIEM were up and running, I wanted to test their security by simulating an external attacker (Red Teaming). The goal: understand whether my Raspberry Pi was secure or if, paradoxically, I had just opened a door into my home network.

---

## Methodology

The approach follows the standard penetration test cycle:

1. **Reconnaissance**: discover which services are exposed
2. **Enumeration**: analyze the services for vulnerabilities
3. **Exploitation**: attempt to exploit the weaknesses found
4. **Post-exploitation**: verify what an attacker could do after gaining access
5. **Remediation**: fix the discovered vulnerabilities

---

## Documentation Index

| Document | Content |
|---|---|
| [Phase 1: Reconnaissance](docs/reconnaissance.en.md) | Nmap SYN scan + version detection, real output analyzed line by line, DMZ as root cause |
| [Phase 2-3: Exploitation and Post-Exploitation](docs/exploitation.en.md) | Brute force with Hydra, container isolation testing, LAN pivot risk |
| [Phase 4-6: Remediation](docs/remediation.en.md) | UFW rules (critical ordering), disconnected agent, CGNAT + Ngrok, corrected vulnerabilities table |
| [Event Correlation + Final Test](docs/correlazione-eventi.en.md) | Real Wazuh JSON alert, attack timeline, Dashboard query, UFW correlation, end-to-end test |
| [STRIDE Threat Model](docs/threat-model.en.md) | Assets, attack surface, threat actors, STRIDE analysis for Honeypot/VPN/SIEM/NAS, residual risks |
