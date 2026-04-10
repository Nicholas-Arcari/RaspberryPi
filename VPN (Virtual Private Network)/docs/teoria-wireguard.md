# Teoria: VPN e WireGuard

## Cos'e' una VPN

Una VPN (Virtual Private Network) crea un **tunnel crittografato** tra un dispositivo remoto (smartphone, laptop) e la rete di casa. Il traffico viaggia incapsulato all'interno di pacchetti cifrati - chiunque intercetti il traffico (ISP, Wi-Fi pubblico, attaccante MITM) vede solo dati illeggibili.

Casi d'uso concreti:

- **Wi-Fi pubblico**: il traffico tra il tuo dispositivo e il router del bar e' in chiaro. Con la VPN, tutto passa cifrato fino a casa tua
- **Accesso remoto alla LAN**: da fuori casa puoi raggiungere il NAS, la dashboard Wazuh, le telecamere, come se fossi collegato via Ethernet
- **Elusione georestrizioni**: il tuo traffico Internet "esce" dall'IP di casa tua, non dall'IP dell'hotel o dell'aeroporto

## Perche' WireGuard e non OpenVPN/IPSec

| Caratteristica | WireGuard | OpenVPN | IPSec/IKEv2 |
|---|---|---|---|
| **Linee di codice** | ~4.000 | ~100.000+ | ~400.000+ |
| **Superficie d'attacco** | Minima (auditabile) | Ampia | Molto ampia |
| **Crittografia** | Fissa, moderna (vedi sotto) | Configurabile (rischio misconfiguration) | Configurabile |
| **Performance** | Eccellente (kernel-space) | Buona (user-space) | Buona |
| **Consumo batteria** | Basso (idle = 0 traffico) | Medio (keepalive continui) | Medio |
| **Setup** | Chiavi pubbliche/private | Certificati PKI | Certificati PKI/PSK |

## Crittografia di WireGuard (per i curiosi)

WireGuard usa una suite crittografica fissa e moderna - nessuna negoziazione, nessuna scelta di cipher suite:

| Funzione | Algoritmo | Scopo |
|---|---|---|
| Key exchange | **Curve25519** (ECDH) | Scambio chiavi Diffie-Hellman su curva ellittica |
| Cifratura simmetrica | **ChaCha20** | Cifratura del tunnel (alternativa ad AES, ottimizzata per CPU senza AES-NI come ARM) |
| MAC (autenticazione) | **Poly1305** | Verifica integrita' e autenticita' dei pacchetti |
| Hashing | **BLAKE2s** | Derivazione chiavi e hashing interno |
| Key derivation | **HKDF** | Derivazione di chiavi di sessione dalle chiavi condivise |

> **Nota su ARM e ChaCha20:** AES-256 e' veloce su CPU x86 con l'istruzione AES-NI hardware. Il Raspberry Pi 5 (Cortex-A76) ha supporto ARMv8 Crypto Extensions, quindi AES e' comunque veloce. Tuttavia, ChaCha20 e' progettato per essere veloce anche senza accelerazione hardware, rendendolo una scelta robusta per qualsiasi piattaforma.

## Noise Protocol Framework: l'handshake IK in dettaglio

WireGuard utilizza il pattern **Noise_IKpsk2** dal Noise Protocol Framework. "IK" significa che l'**Initiator** conosce gia' la chiave pubblica statica del **Responder** (configurata manualmente o via QR code), e il Responder apprende quella dell'Initiator durante l'handshake.

L'intero handshake richiede **1-RTT** (un solo round-trip) e si completa in 2 messaggi:

```
Initiator (client)                              Responder (server)
     │                                               │
     │  Possiede: S_i (statica), E_i (effimera)      │  Possiede: S_r (statica)
     │  Conosce:  S_r_pub (chiave pubblica server)    │
     │                                               │
     ├── Handshake Initiation ──────────────────────►│
     │   [sender_index, E_i_pub,                     │
     │    AEAD(S_i_pub), AEAD(timestamp)]            │
     │                                               │
     │   DH #1: E_i × S_r_pub  (effimera × statica) │
     │   DH #2: S_i × S_r_pub  (statica × statica)  │
     │                                               │
     │◄── Handshake Response ────────────────────────┤
     │   [sender_index, receiver_index, E_r_pub,     │
     │    AEAD(empty)]                               │
     │                                               │
     │   DH #3: E_i × E_r_pub  (effimera × effimera)│
     │   DH #4: S_i × E_r_pub  (statica × effimera) │
     │                                               │
     ├── Transport Data ────────────────────────────►│
     │◄── Transport Data ────────────────────────────┤
```

**Le 4 operazioni Diffie-Hellman:**

| # | Operazione | Scopo |
|---|---|---|
| DH #1 | `E_initiator × S_responder` | Forward secrecy parziale: anche se la chiave statica del client viene compromessa in futuro, questa sessione resta sicura (la chiave effimera e' distrutta) |
| DH #2 | `S_initiator × S_responder` | Autentica l'initiator al responder - conferma che il client possiede la chiave statica dichiarata |
| DH #3 | `E_initiator × E_responder` | **Full forward secrecy**: entrambe le chiavi sono effimere. Anche compromettendo TUTTE le chiavi statiche, il traffico passato resta cifrato |
| DH #4 | `S_initiator × E_responder` | Autentica il responder all'initiator - conferma che il server possiede la chiave statica dichiarata |

Ogni DH produce materiale crittografico che viene mixato progressivamente in una **chaining key** tramite HKDF. Il risultato finale sono due chiavi simmetriche (una per direzione) usate per cifrare i dati con ChaCha20-Poly1305.

**Perche' il timestamp nel primo messaggio:** Il campo `AEAD(timestamp)` serve come protezione anti-replay. Il responder accetta solo handshake con timestamp crescente - un attaccante che cattura e riproduce un pacchetto di handshake vecchio viene rifiutato.

**Rotazione delle chiavi:** Le chiavi di sessione vengono ruotate automaticamente ogni **2 minuti** o dopo **2^64 - 1 pacchetti** (il contatore del nonce ChaCha20). Se non c'e' traffico, WireGuard non invia nulla (a differenza di OpenVPN che manda keepalive) - da qui il basso consumo batteria. Dopo 5 minuti di silenzio, WireGuard considera la sessione scaduta e rinegozia al prossimo pacchetto.

## Cryptokey Routing: l'innovazione architetturale

La vera innovazione di WireGuard non e' la crittografia, ma il concetto di **Cryptokey Routing Table**: una tabella che associa direttamente **subnet di destinazione → chiave pubblica del peer**.

In un VPN tradizionale (OpenVPN, IPSec), il routing e la crittografia sono separati: prima il kernel decide dove mandare il pacchetto (routing table), poi il tunnel lo cifra. In WireGuard, le due operazioni sono **fuse**:

```
Interfaccia wg0 - Cryptokey Routing Table:
┌─────────────────────┬──────────────────────────────────────────────────┬─────────────────────────┐
│ Allowed IPs         │ Peer (chiave pubblica)                          │ Endpoint               │
├─────────────────────┼──────────────────────────────────────────────────┼─────────────────────────┤
│ 10.8.0.2/32         │ gN65BkIK...  (iPhone di Nick)                   │ 82.XX.XX.XX:43721      │
│ 10.8.0.3/32         │ 7Rp2kLQm...  (Laptop lavoro)                   │ 151.XX.XX.XX:51820     │
│ 0.0.0.0/0           │ aF9xMnPq...  (Full tunnel - tutto il traffico) │ 93.XX.XX.XX:38442      │
└─────────────────────┴──────────────────────────────────────────────────┴─────────────────────────┘
```

**Quando un pacchetto viene inviato:**
1. Il kernel riceve un pacchetto destinato a `10.8.0.2` sull'interfaccia `wg0`
2. WireGuard cerca nella Cryptokey Routing Table: `10.8.0.2` matcha la riga con `gN65BkIK...`
3. Il pacchetto viene cifrato con la chiave di sessione derivata dall'handshake con quel peer
4. Il pacchetto cifrato viene incapsulato in UDP e inviato all'endpoint del peer

**Quando un pacchetto viene ricevuto:**
1. WireGuard riceve un pacchetto UDP cifrato
2. Lo decifra con la chiave di sessione del peer mittente (identificato dall'`index` nell'header)
3. Dopo la decifratura, controlla l'IP sorgente del pacchetto interno
4. **Se l'IP sorgente non e' nell'`Allowed IPs` di quel peer, il pacchetto viene scartato silenziosamente** - questo e' il firewall crittografico implicito di WireGuard

Questa architettura rende WireGuard intrinsecamente resistente allo spoofing: un peer non puo' inviare pacchetti fingendo di essere un altro IP, perche' la verifica `IP sorgente ∈ Allowed IPs` e' legata alla chiave crittografica.

## Roaming trasparente

WireGuard aggiorna l'endpoint di un peer **automaticamente**. Se il tuo telefono passa dal Wi-Fi al 4G (cambiando IP pubblico), il server riceve il prossimo pacchetto valido dal nuovo IP, aggiorna l'endpoint nella tabella, e continua senza interruzione. Non serve rinegoziare l'handshake - le chiavi di sessione restano valide indipendentemente dall'IP
