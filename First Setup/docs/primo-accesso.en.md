>  [Italiano](primo-accesso.md) |  **English**

# First Access and System Update

## Step 2: First Access via SSH

Insert the MicroSD into the Raspberry Pi, connect the Ethernet cable and the power supply. Wait approximately 60 seconds for the first boot (the initial startup is slower because it expands the filesystem and applies the customisations).

### Finding the Raspberry Pi's IP

If you do not know the IP assigned by DHCP:

```bash
# From the router: check the DHCP clients table
# Or, from another PC on the same network:
nmap -sn 192.168.0.0/24
# Or, on Windows:
arp -a
```

### SSH Connection

```bash
ssh pi@<RASPBERRY_IP>
```

On the first connection, SSH will ask you to confirm the server's fingerprint:

```
The authenticity of host '192.168.0.102 (192.168.0.102)' can't be established.
ED25519 key fingerprint is SHA256:xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx.
Are you sure you want to continue connecting (yes/no/[fingerprint])?
```

**What is happening at a technical level:** SSH uses the Diffie-Hellman key exchange protocol (or the ECDH variant with Curve25519) to establish an encrypted session. The first time you connect, the client has never seen that server and asks you to manually verify the fingerprint - a compressed representation of the server's public key (in `SHA256:base64` format). By typing `yes`, the client saves this `IP -> public key` association in the `~/.ssh/known_hosts` file.

### The Dreaded "REMOTE HOST IDENTIFICATION HAS CHANGED"

If after an OS reinstallation, an SD reflash, or a device swap on the same IP, SSH will display:

```
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@    WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!     @
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
IT IS POSSIBLE THAT SOMEONE IS DOING SOMETHING NASTY!
```

**What is happening:** SSH compared the public key presented by the server with the one saved in `known_hosts` and found a mismatch. This is exactly the mechanism that protects against a **Man-in-the-Middle (MitM) attack**: if an attacker were to position themselves between you and the server, they would present a different key and SSH would block the connection.

In our case, we know the key change is legitimate (we reinstalled the OS), so we can remove the old entry:

```bash
ssh-keygen -R <RASPBERRY_IP>
```

This command removes the line corresponding to that IP from the `~/.ssh/known_hosts` file. The next connection will ask again to accept the new fingerprint.

> **Warning:** If you have not reinstalled anything and you see this warning, **stop and investigate**. It could be a real MitM attack, ARP spoofing on the local network, or another device that has taken the same IP.

---

## Step 3: System Update

After the first access, immediately update all packages:

```bash
sudo apt update && sudo apt full-upgrade -y
sudo reboot
```

**Why `full-upgrade` and not `upgrade`:**

- `apt upgrade`: only updates packages that do not require the removal or installation of new packages
- `apt full-upgrade`: updates everything, even if it requires removing obsolete packages or installing new ones (necessary for kernel and system library updates)

On a freshly installed system, `full-upgrade` ensures you have all the latest security patches, including kernel patches.
