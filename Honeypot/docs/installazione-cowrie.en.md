>  [Italiano](installazione-cowrie.md) |  **English**

# Cowrie Installation with Wazuh Integration

## Project Architecture

```
Attacker (Internet/LAN)
    |
    | SSH port 2222
    v
[Cowrie Container] --JSON log--> [Wazuh Agent] --events--> [Wazuh Manager]
                                                                |
                                                                v
                                                         [Wazuh Indexer]
                                                                |
                                                                v
                                                         [Wazuh Dashboard]
                                                         (Alert + Threat Hunting)
```

The complete flow:

1. **The attacker** connects to port 2222 (exposed by Cowrie, not the real SSH port 22)
2. **Cowrie** logs everything to `/var/log/cowrie/cowrie.json` (IP, passwords, commands)
3. **The Wazuh agent** monitors that file in real time (conceptually a tail -f)
4. **Wazuh Manager** receives the events, decodes them with the JSON decoder, and matches them against the rules
5. If a rule matches, it generates an **alert** that appears on the Dashboard

## Prerequisites

- Raspberry Pi with Docker and Docker Compose installed
- Wazuh Manager and Agent installed (All-in-One on the Pi or Manager on an external server)
- Port 2222 available (not occupied by other services)

## Step-by-Step Installation

### Step 1: Cowrie Setup with Docker

#### Creating the directories

```bash
mkdir -p ~/cowrie/var/log/cowrie
mkdir -p ~/cowrie/etc
cd ~/cowrie
```

The `var/log/cowrie` structure will be mounted as a volume in the container - Cowrie logs will be written here, where Wazuh can read them.

#### Docker Compose

Create the `docker-compose.yml` file:

```yaml
version: "3"
services:
  cowrie:
    image: cowrie/cowrie:latest
    container_name: cowrie
    restart: always
    ports:
      - "2222:2222"  # Porta SSH Honeypot
      - "2223:2223"  # Porta Telnet Honeypot
    volumes:
      # Monta SOLO i log - NON montare /etc (vedi Troubleshooting Errore 1)
      - ./var/log/cowrie:/cowrie/cowrie-git/var/log/cowrie
```

> **Why port 2222 and not 22:** Port 22 is occupied by the Raspberry Pi's real SSH server. If we used port 22 for the honeypot, we would lose real SSH access to the system. In a production deployment, you could use NAT to expose port 2222 as port 22 to the Internet (from the attacker's perspective, it looks like a normal SSH service).

#### Startup

```bash
docker compose up -d
```

Verify that the container is running:

```bash
docker ps | grep cowrie
# Stato atteso: Up X minutes (non "Restarting")
```

### Step 2: Wazuh Configuration for Cowrie Log Ingestion

We need to instruct the Wazuh agent to monitor the JSON file produced by Cowrie.

#### Editing ossec.conf

Open the Wazuh agent configuration file:

```bash
sudo nano /var/ossec/etc/ossec.conf
```

Add this block **before** the closing `</ossec_config>` tag:

```xml
<localfile>
  <log_format>json</log_format>
  <location>/home/<tuo_utente>/cowrie/var/log/cowrie/cowrie.json</location>
</localfile>
```

**What this does:** It instructs the Wazuh agent to:

1. Monitor the specified file in real time (like `tail -f`)
2. Parse each new line as JSON (not as traditional syslog)
3. Send the parsed events to the Wazuh Manager for analysis

#### Permission Fix

Docker creates log files with the container's internal user. Wazuh (which runs as the `wazuh` or `ossec` user) may not be able to read them:

```bash
sudo chmod -R 755 /home/<tuo_utente>/cowrie/var/log/cowrie/
```

> **Note:** In a production environment, it would be better to use ACLs or add the `wazuh` user to the container's group. The `chmod 755` is the quick fix for a home lab.

#### Restarting the agent

```bash
sudo systemctl restart wazuh-agent
# oppure, se è all-in-one:
sudo /var/ossec/bin/wazuh-control restart
```
