>  [Italiano](installazione-omv.md) |  **English**

# Step 3: Installing OpenMediaVault

## Prerequisites

- Raspberry Pi OS **Lite** (without Desktop). OMV blocks installation on systems with a GUI
- System up to date (`sudo apt update && sudo apt full-upgrade -y`)

## Installation via official script

```bash
wget -O - https://github.com/OpenMediaVault-Plugin-Developers/installScript/raw/master/install | sudo bash
```

**What the script does:**

1. Adds the OpenMediaVault APT repositories
2. Installs core packages: `openmediavault`, `openmediavault-keyring`
3. Configures system services: nginx (web server), PHP-FPM, monit
4. Sets port 80 for the web UI
5. Creates the admin user with a default password

Installation takes 10-20 minutes on RPi5. Do not interrupt the process.

## Accessing the Web UI

After reboot:

```bash
http://<RASPBERRY_IP>:80
```

Default credentials:

| Field | Value |
|---|---|
| Username | `admin` |
| Password | `openmediavault` |

> **Mandatory first step:** Change the admin password immediately. Go to **User Settings** (gear icon in the top right) and update the password. Anyone on your local network can access port 80 without prior authentication.
