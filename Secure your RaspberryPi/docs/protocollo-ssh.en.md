>  [Italiano](protocollo-ssh.md) |  **English**

# Deep Dive: the SSH Protocol from TCP Connection to Authentication

To understand the `sshd_config` directives, you first need to understand what happens when you type `ssh pi@192.168.0.102`. The SSH protocol (RFC 4251-4254) consists of 5 sequential phases:

```
Client (your PC)                                        Server (Raspberry Pi)
       |                                                       |
       |---- [PHASE 1] TCP Handshake (port 22) -------------->|
       |     SYN -> SYN-ACK -> ACK                            |
       |                                                       |
       |---- [PHASE 2] Version Exchange ---------------------->|
       |     "SSH-2.0-OpenSSH_9.7"                             |
       |<--- "SSH-2.0-OpenSSH_8.4p1 Debian-5+deb11u3" --------|
       |                                                       |
       |---- [PHASE 3] Key Exchange (KEX) -------------------->|
       |     List of supported algorithms (KEX, encryption,    |
       |     MAC, compression) -> negotiation                  |
       |                                                       |
       |     Diffie-Hellman (curve25519-sha256):               |
       |     Client generates e_c (ephemeral), sends Q_c = e_c*G  |
       |<--- Server generates e_s, sends Q_s = e_s*G + host_key --|
       |                                                       |
       |     Both compute: K = e_c * Q_s = e_s * Q_c          |
       |     (identical shared secret, never transmitted)      |
       |                                                       |
       |     H = hash(V_c, V_s, I_c, I_s, K_s, Q_c, Q_s, K)  |
       |     The server SIGNS H with its private host key      |
       |     and sends the signature to the client             |
       |                                                       |
       |     -> Session keys derived from K and H via SHA-256  |
       |     -> From this point ALL traffic is encrypted       |
       |                                                       |
       |---- [PHASE 4] Encrypted channel established --------->|
       |     NEWKEYS -> both sides switch to the new           |
       |     session keys                                      |
       |                                                       |
       |---- [PHASE 5] User Authentication ------------------->|
       |     (see below: password or public key)               |
       |                                                       |
```

---

## Phase 2: Version Exchange

The first bytes exchanged on an SSH connection are **plaintext** - not yet encrypted. Both sides send their version string in the format `SSH-protoversion-softwareversion`:

```
SSH-2.0-OpenSSH_8.4p1 Debian-5+deb11u3
|    |   |              |
|    |   |              +-- Debian package patch
|    |   +-- Software and version (information disclosure!)
|    +-- Protocol version (2.0)
+-- Protocol identifier
```

> **Security implication:** This string is visible to anyone connecting to port 22. It reveals the software, version, and operating system. An attacker uses this information to search for specific CVEs. This is why Cowrie emulates a different version (`OpenSSH_6.0p1`) - to appear as an appealing target.

---

## Phase 3: Key Exchange (Diffie-Hellman on Curve25519)

This is the most critical phase. The client and server must agree on a **shared secret key** without ever transmitting it over the network. They use the Diffie-Hellman protocol on the elliptic curve Curve25519:

**The mathematics (simplified):**

1. Both know an elliptic curve `E` and a generator point `G` (public parameters of Curve25519)
2. The **client** generates a random number `e_c` (private ephemeral key) and computes `Q_c = e_c * G` (scalar multiplication on the curve point). Sends `Q_c` to the server
3. The **server** generates `e_s` and computes `Q_s = e_s * G`. Sends `Q_s` to the client
4. The **client** computes `K = e_c * Q_s = e_c * e_s * G`
5. The **server** computes `K = e_s * Q_c = e_s * e_c * G`
6. `K` is identical on both sides (commutative property of scalar multiplication), but **was never transmitted over the network**

An attacker intercepting `Q_c` and `Q_s` would need to solve the **Elliptic Curve Discrete Logarithm Problem (ECDLP)** to recover `e_c` or `e_s` - computationally infeasible with Curve25519 dimensions (256 bit -> ~128 bit security).

**Session Key derivation:** From the shared secret `K` and the session hash `H`, SSH derives 6 separate keys using SHA-256:

| Key | Purpose |
|---|---|
| `IV_c->s` | Initialization Vector for client -> server encryption |
| `IV_s->c` | Initialization Vector for server -> client encryption |
| `Enc_c->s` | Encryption key client -> server (ChaCha20 or AES-256) |
| `Enc_s->c` | Encryption key server -> client |
| `MAC_c->s` | HMAC key for client -> server integrity |
| `MAC_s->c` | HMAC key for server -> client integrity |

Separate keys for each direction prevent reflection attacks (an attacker replaying client packets back to the client itself).

---

## Host Keys vs User Keys: the Fundamental Distinction

SSH uses **two types of asymmetric keys** for completely different purposes. Confusing them is a common mistake.

### Host Keys (server keys)

```
/etc/ssh/ssh_host_ed25519_key       <-- Server PRIVATE key (permissions 600)
/etc/ssh/ssh_host_ed25519_key.pub   <-- Server PUBLIC key
/etc/ssh/ssh_host_rsa_key           <-- Same thing, RSA algorithm
/etc/ssh/ssh_host_ecdsa_key         <-- Same thing, ECDSA algorithm
```

- **Automatically generated** on first `sshd` startup (or during OS installation)
- Used to **authenticate the server to the client** - "are you really my Raspberry Pi, or an impostor?"
- The server signs the session hash `H` with the private host key during KEX (Phase 3)
- The client verifies the signature using the public host key saved in `~/.ssh/known_hosts`
- **If they change** (OS reinstallation, different device on the same IP): the warning "REMOTE HOST IDENTIFICATION HAS CHANGED"

### User Keys (user keys)

```
~/.ssh/id_ed25519       <-- User PRIVATE key (protected by passphrase)
~/.ssh/id_ed25519.pub   <-- User PUBLIC key (copied to the server)
```

- **Generated by the user** with `ssh-keygen`
- Used to **authenticate the user to the server** - "are you really Nick, or an impostor?"
- The public key is copied to `~/.ssh/authorized_keys` on the server
- The private key **never leaves the client**

---

## The Fingerprint: What It Is, How It Is Generated, How to Verify It

When you connect to an SSH server for the first time:

```
The authenticity of host '192.168.0.102 (192.168.0.102)' can't be established.
ED25519 key fingerprint is SHA256:xK7vN2mP9qR8sT1uV3wX5yZ7aB9cD2eF4gH6iJ8kL0=.
Are you sure you want to continue connecting (yes/no/[fingerprint])?
```

**What the fingerprint is:**

```
Server public key (Ed25519, 256 bit)
    |
    v SHA-256 hash
[32 bytes of hash]
    |
    v Base64 encode
"xK7vN2mP9qR8sT1uV3wX5yZ7aB9cD2eF4gH6iJ8kL0="
    |
    v Algorithm prefix
"SHA256:xK7vN2mP9qR8sT1uV3wX5yZ7aB9cD2eF4gH6iJ8kL0="
```

It is a **hash of the server's public key**, presented in a compact format for human verification. Verifying 43 Base64 characters is feasible; verifying 256 bits of raw key would be impractical.

**How to verify it manually (on the server):**

```bash
# Show the Ed25519 host key fingerprint
ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
# 256 SHA256:xK7vN2mP9qR8sT1uV3wX5yZ7aB9cD2eF4gH6iJ8kL0= root@raspberrypi (ED25519)
```

If you have physical access to the Pi (or an already-trusted SSH session), you can compare this output with the fingerprint presented by the client. If they match, the connection is authentic.

> **In practice:** In most home setups, the first connection occurs on the same LAN, where a MitM attack is unlikely. But in enterprise environments or on untrusted networks, fingerprint verification is mandatory - ideally the fingerprint is communicated over a separate channel (e.g., in person, by phone, in an internal document).

**Legacy MD5 format:** Older versions of OpenSSH displayed the fingerprint in hexadecimal MD5 format:

```bash
ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub -E md5
# 256 MD5:a1:b2:c3:d4:e5:f6:a7:b8:c9:d0:e1:f2:a3:b4:c5:d6 root@raspberrypi (ED25519)
```

The SHA256/Base64 format is preferred because SHA-256 is collision-resistant (finding two keys with the same hash is computationally infeasible), while MD5 has had known collisions since 2004.

---

## The `known_hosts` File: the Trust-On-First-Use (TOFU) Database

When you accept the fingerprint ("yes"), the client saves the association in `~/.ssh/known_hosts`:

```
|1|base64salt=|base64hash= ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

Field format:

| Field | Meaning |
|---|---|
| `\|1\|base64salt=\|base64hash=` | **Hashed hostname** - the server IP/hostname, obfuscated with HMAC-SHA1 for privacy (an attacker who steals the file cannot enumerate the servers you connect to) |
| `ssh-ed25519` | Key type |
| `AAAAC3NzaC1...` | Full public key in Base64 |

On each subsequent connection, the client:
1. Searches for the hostname in the `known_hosts` file
2. Compares the public key presented by the server with the one saved
3. **Match** -> connection proceeds silently
4. **Mismatch** -> "REMOTE HOST IDENTIFICATION HAS CHANGED" (possible MitM)
5. **Not found** -> asks to accept the fingerprint (first connection)

This model is called **TOFU (Trust-On-First-Use)**: you trust the first connection and verify that subsequent ones are consistent. It is weaker than a PKI (where an authority certifies identity), but more practical for SSH.

---

## The `authorized_keys` File: Format and Mechanism

On the server, `~/.ssh/authorized_keys` contains the public keys of authorized users:

```
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx nick@homelab
|            |                                                                    |
|            +-- Public key (Base64)                                              +-- Comment (optional)
+-- Key type
```

Advanced options (prefix to the key):

```
command="/usr/bin/rsync",no-pty,no-port-forwarding ssh-ed25519 AAAAC3...  backup@nas
```

| Option | Effect |
|---|---|
| `command="..."` | Forces execution of a single command (e.g., automated backups) |
| `no-pty` | Prevents allocation of an interactive terminal |
| `no-port-forwarding` | Prevents SSH tunneling |
| `from="192.168.0.0/24"` | Accepts the key only from IPs in the specified subnet |

---

## Public Key Authentication: the Challenge-Response

When `PasswordAuthentication no` and `PubkeyAuthentication yes`, here is what happens in Phase 5:

```
Client                                              Server
   |                                                    |
   |-- "I want to authenticate as pi                    |
   |    with key ssh-ed25519 AAAA..."  ---------------->|
   |                                                    |
   |    The server looks up AAAA... in                  |
   |    ~pi/.ssh/authorized_keys                        |
   |                                                    |
   |    If found:                                       |
   |<-- Challenge: random data encrypted  --------------|
   |    with the client's public key                    |
   |                                                    |
   |    The client SIGNS the challenge                  |
   |    with its PRIVATE key                            |
   |    (the private key is NEVER sent)                 |
   |                                                    |
   |-- Signature(challenge, private_key)  ------------->|
   |                                                    |
   |    The server VERIFIES the signature               |
   |    using the public key                            |
   |    in authorized_keys                              |
   |                                                    |
   |    Valid signature?                                |
   |    YES -> access granted                           |
   |    NO  -> access denied                            |
   |                                                    |
   |<-- SSH_MSG_USERAUTH_SUCCESS  ----------------------|
```

**The crucial point:** the private key never crosses the network. The server sends a challenge, the client signs it with the private key, the server verifies the signature with the public key. This is the fundamental principle of asymmetric cryptography applied to authentication: **knowledge of the public key allows verification, but not forgery, of a signature**.

Even if an attacker intercepted the entire session, they would only obtain the signature of that specific challenge - not the private key, and not a reusable signature (each challenge is unique).
