>  [Italiano](teoria-wireguard.md) |  **English**

# Theory: VPN and WireGuard

## What is a VPN

A VPN (Virtual Private Network) creates an **encrypted tunnel** between a remote device (smartphone, laptop) and the home network. Traffic travels encapsulated within encrypted packets - anyone intercepting the traffic (ISP, public Wi-Fi, MITM attacker) sees only unreadable data.

Concrete use cases:

- **Public Wi-Fi**: the traffic between your device and the coffee shop router is in cleartext. With a VPN, everything passes encrypted all the way to your home
- **Remote LAN access**: from outside the house you can reach the NAS, the Wazuh dashboard, the cameras, as if you were connected via Ethernet
- **Bypassing geo-restrictions**: your Internet traffic "exits" from your home IP, not from the hotel or airport IP

## Why WireGuard and not OpenVPN/IPSec

| Feature | WireGuard | OpenVPN | IPSec/IKEv2 |
|---|---|---|---|
| **Lines of code** | ~4,000 | ~100,000+ | ~400,000+ |
| **Attack surface** | Minimal (auditable) | Large | Very large |
| **Encryption** | Fixed, modern (see below) | Configurable (misconfiguration risk) | Configurable |
| **Performance** | Excellent (kernel-space) | Good (user-space) | Good |
| **Battery consumption** | Low (idle = 0 traffic) | Medium (continuous keepalives) | Medium |
| **Setup** | Public/private keys | PKI certificates | PKI/PSK certificates |

## WireGuard Cryptography (for the curious)

WireGuard uses a fixed and modern cryptographic suite - no negotiation, no cipher suite choice:

| Function | Algorithm | Purpose |
|---|---|---|
| Key exchange | **Curve25519** (ECDH) | Diffie-Hellman key exchange over elliptic curve |
| Symmetric encryption | **ChaCha20** | Tunnel encryption (alternative to AES, optimized for CPUs without AES-NI such as ARM) |
| MAC (authentication) | **Poly1305** | Packet integrity and authenticity verification |
| Hashing | **BLAKE2s** | Key derivation and internal hashing |
| Key derivation | **HKDF** | Deriving session keys from shared keys |

> **Note on ARM and ChaCha20:** AES-256 is fast on x86 CPUs with the hardware AES-NI instruction. The Raspberry Pi 5 (Cortex-A76) has ARMv8 Crypto Extensions support, so AES is fast regardless. However, ChaCha20 is designed to be fast even without hardware acceleration, making it a robust choice for any platform.

## Noise Protocol Framework: the IK handshake in detail

WireGuard uses the **Noise_IKpsk2** pattern from the Noise Protocol Framework. "IK" means that the **Initiator** already knows the static public key of the **Responder** (configured manually or via QR code), and the Responder learns the Initiator's during the handshake.

The entire handshake requires **1-RTT** (a single round-trip) and completes in 2 messages:

```
Initiator (client)                              Responder (server)
     |                                               |
     |  Possesses: S_i (static), E_i (ephemeral)     |  Possesses: S_r (static)
     |  Knows:     S_r_pub (server public key)        |
     |                                               |
     |-- Handshake Initiation ---------------------->|
     |   [sender_index, E_i_pub,                     |
     |    AEAD(S_i_pub), AEAD(timestamp)]            |
     |                                               |
     |   DH #1: E_i x S_r_pub  (ephemeral x static) |
     |   DH #2: S_i x S_r_pub  (static x static)    |
     |                                               |
     |<-- Handshake Response ------------------------|
     |   [sender_index, receiver_index, E_r_pub,     |
     |    AEAD(empty)]                               |
     |                                               |
     |   DH #3: E_i x E_r_pub  (ephemeral x ephemeral)|
     |   DH #4: S_i x E_r_pub  (static x ephemeral) |
     |                                               |
     |-- Transport Data ---------------------------->|
     |<-- Transport Data ----------------------------|
```

**The 4 Diffie-Hellman operations:**

| # | Operation | Purpose |
|---|---|---|
| DH #1 | `E_initiator x S_responder` | Partial forward secrecy: even if the client's static key is compromised in the future, this session remains secure (the ephemeral key is destroyed) |
| DH #2 | `S_initiator x S_responder` | Authenticates the initiator to the responder - confirms the client possesses the declared static key |
| DH #3 | `E_initiator x E_responder` | **Full forward secrecy**: both keys are ephemeral. Even if ALL static keys are compromised, past traffic remains encrypted |
| DH #4 | `S_initiator x E_responder` | Authenticates the responder to the initiator - confirms the server possesses the declared static key |

Each DH produces cryptographic material that is progressively mixed into a **chaining key** via HKDF. The final result is two symmetric keys (one per direction) used to encrypt data with ChaCha20-Poly1305.

**Why the timestamp in the first message:** The `AEAD(timestamp)` field serves as anti-replay protection. The responder only accepts handshakes with an increasing timestamp - an attacker who captures and replays an old handshake packet is rejected.

**Key rotation:** Session keys are automatically rotated every **2 minutes** or after **2^64 - 1 packets** (the ChaCha20 nonce counter). If there is no traffic, WireGuard sends nothing (unlike OpenVPN which sends keepalives) - hence the low battery consumption. After 5 minutes of silence, WireGuard considers the session expired and renegotiates on the next packet.

## Cryptokey Routing: the architectural innovation

The true innovation of WireGuard is not the cryptography, but the concept of the **Cryptokey Routing Table**: a table that directly maps **destination subnets to the peer's public key**.

In a traditional VPN (OpenVPN, IPSec), routing and encryption are separate: first the kernel decides where to send the packet (routing table), then the tunnel encrypts it. In WireGuard, the two operations are **merged**:

```
Interface wg0 - Cryptokey Routing Table:
+---------------------+--------------------------------------------------+-------------------------+
| Allowed IPs         | Peer (public key)                                | Endpoint                |
+---------------------+--------------------------------------------------+-------------------------+
| 10.8.0.2/32         | gN65BkIK...  (Nick's iPhone)                     | 82.XX.XX.XX:43721       |
| 10.8.0.3/32         | 7Rp2kLQm...  (Work laptop)                       | 151.XX.XX.XX:51820      |
| 0.0.0.0/0           | aF9xMnPq...  (Full tunnel - all traffic)         | 93.XX.XX.XX:38442       |
+---------------------+--------------------------------------------------+-------------------------+
```

**When a packet is sent:**
1. The kernel receives a packet destined for `10.8.0.2` on the `wg0` interface
2. WireGuard looks up the Cryptokey Routing Table: `10.8.0.2` matches the row with `gN65BkIK...`
3. The packet is encrypted with the session key derived from the handshake with that peer
4. The encrypted packet is encapsulated in UDP and sent to the peer's endpoint

**When a packet is received:**
1. WireGuard receives an encrypted UDP packet
2. It decrypts it with the sending peer's session key (identified by the `index` in the header)
3. After decryption, it checks the source IP of the inner packet
4. **If the source IP is not in that peer's `Allowed IPs`, the packet is silently dropped** - this is WireGuard's implicit cryptographic firewall

This architecture makes WireGuard inherently resistant to spoofing: a peer cannot send packets pretending to be another IP, because the `source IP in Allowed IPs` check is tied to the cryptographic key.

## Transparent roaming

WireGuard updates a peer's endpoint **automatically**. If your phone switches from Wi-Fi to 4G (changing public IP), the server receives the next valid packet from the new IP, updates the endpoint in the table, and continues without interruption. No handshake renegotiation is needed - the session keys remain valid regardless of IP.
