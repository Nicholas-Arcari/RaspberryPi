>  [Italiano](installazione-os.md) |  **English**

# Operating System Installation

## Overview

The Raspberry Pi 5 will be configured with:

- **Raspberry Pi OS Lite 64-bit (Bookworm)** as the operating system
- **Direct boot from NVMe SSD** for performance and durability
- **SSH-only access** (no monitor, keyboard, or graphical interface)
- **MicroSD** used only for the initial flash and as an emergency recovery option

---

## Why Bookworm and NOT Trixie

At the time of writing, Raspberry Pi OS is available in two versions:

| | Bookworm (Debian 12) | Trixie (Debian 13) |
|---|---|---|
| **Status** | Stable, LTS | Testing/Unstable |
| **OMV Compatibility** | Supported (OMV 7) | **NOT supported** |
| **Wazuh Compatibility** | Supported (4.x) | **NOT supported** |
| **Docker Packages** | Stable | Possible breaking changes |
| **Community Support** | Extensive, well-documented | Limited |

**Practical rule in cybersecurity:** on a system that must serve as a 24/7 server, you *always* use the stable release. Testing/unstable packages can introduce regressions that break production services without warning. Bookworm receives security patches without feature changes - exactly what is needed.

Additionally, **the Lite (headless) version must be used**, without a graphical interface. Reasons:

- OpenMediaVault explicitly blocks installation on systems with a Desktop Environment
- A server does not need a GUI - it wastes RAM and CPU for nothing
- Smaller attack surface: fewer installed packages = fewer potential CVEs

---

## Step 1: Flashing the Operating System

### Tool: Raspberry Pi Imager

Download Raspberry Pi Imager from the official page: https://www.raspberrypi.com/software/

#### 1.1 Device Selection

Launch Imager and select **Raspberry Pi 5** as the target device.

![Device selection in Raspberry Pi Imager](../img/rpi-imager-device-selection.jpg)

#### 1.2 Operating System Selection

Select the **Raspberry Pi OS (other)** category to access the Lite variants.

![OS category selection](../img/rpi-imager-os-selection.jpg)

Select **Raspberry Pi OS Lite (64-bit)** based on Debian Bookworm. The 64-bit version is essential because:

- Wazuh Indexer (OpenSearch) requires 64-bit architecture
- Docker on ARM64 has a broader image ecosystem compared to armhf (32-bit)
- The Raspberry Pi 5 has 8GB of RAM - with a 32-bit OS it would see at most 4GB per process (32-bit address space limit)

![Raspberry Pi OS Lite 64-bit Bookworm selection](../img/rpi-imager-os-lite.jpg)

#### 1.3 Storage Selection

Select the MicroSD as the destination. On first boot, the system will start from the SD, then we will migrate to NVMe.

![MicroSD storage selection](../img/rpi-imager-storage.jpg)

#### 1.4 Customisation

Before writing, click on **Customisation** and configure:

- **Hostname**: an identifying name (e.g., `raspberrypi`, `homelab`, `nickpi`)
- **Username and Password**: create a NON-root user (e.g., `pi` with a strong password)
- **Locale/Timezone**: `Europe/Rome`, keyboard layout `it`
- **SSH**: enable SSH with password authentication (we will configure the public key later)
- **Wi-Fi**: do NOT configure Wi-Fi - a server must use Ethernet for stability and for MacVLAN

> **Security note:** the password set in Imager is saved in plaintext in the `firstrun.sh` file on the SD during flashing. After the first boot, the file is deleted, but anyone with physical access to the SD before boot can read it. If the device is in a shared environment, change the password immediately after first access.

#### 1.5 Writing

Click **Write** and wait for completion. Imager automatically verifies the write integrity via checksum.
