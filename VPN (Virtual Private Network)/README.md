>  [English](README.en.md) |  **Italiano**

# VPN Server - WireGuard su Docker con wg-easy

Guida completa per trasformare il Raspberry Pi in un server VPN usando WireGuard. Questa guida nasce dalla mia esperienza diretta e copre non solo l'installazione software, ma anche le complesse configurazioni di rete (DMZ, Double NAT, DDNS) che sono state necessarie per far funzionare il tutto con un provider FWA (Fixed Wireless Access).

---

## In breve

WireGuard è un protocollo VPN moderno con ~4.000 righe di codice (contro le ~100.000+ di OpenVPN), crittografia fissa basata su ChaCha20-Poly1305 e Curve25519, e un handshake Noise IK che si completa in un solo round-trip con 4 operazioni Diffie-Hellman. La sua innovazione architetturale è la Cryptokey Routing Table, che fonde routing e crittografia in un'unica operazione, rendendo il protocollo intrinsecamente resistente allo spoofing.

---

## Indice

| Documento | Contenuto |
|---|---|
| [Teoria: VPN e WireGuard](docs/teoria-wireguard.md) | Cos'è una VPN, perchè WireGuard, suite crittografica, handshake Noise IK (4 DH), Cryptokey Routing Table, roaming trasparente |
| [Rete: DMZ e Doppio NAT](docs/rete-dmz.md) | Problema del Double NAT con provider FWA, soluzione DMZ, prerequisiti, configurazione router (IP statico, DDNS, port forwarding) |
| [Installazione](docs/installazione.md) | Creazione directory, Docker Compose con spiegazione parametri, regole iptables PostUp/PostDown, avvio, output annotato di `wg show` |
| [Alternative a confronto](docs/alternative.md) | WireGuard vs Tailscale vs OpenVPN vs ZeroTier vs NordVPN, impatto architetturale di Tailscale, installazione OpenVPN Docker, Cloudflare Tunnel |
| [Troubleshooting e utilizzo](docs/troubleshooting.md) | 3 problemi reali e soluzioni (bootloop, DNS limbo, MTU 4G), utilizzo quotidiano, test di verifica |

---

Prossimo step: [ADS Blocker](../ADS%20Blocker/) - Pi-hole come DNS sinkhole per bloccare pubblicità e tracking.
